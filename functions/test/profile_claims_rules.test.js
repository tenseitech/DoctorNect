'use strict';

const fs = require('fs');
const path = require('path');
const { before, after, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-doctornect-claims-rules';

let testEnv;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('firestore profile claims rules tests (skipped: FIRESTORE_EMULATOR_HOST not set)', { skip: 'FIRESTORE_EMULATOR_HOST not set' }, () => {});
  return;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

const ROLES = [
  {
    role: 'patient',
    prefix: 'p_',
    collection: 'patients',
    profileData: (profileId, uid) => ({
      patientId: profileId,
      ownerUid: uid,
      role: 'patient',
      verified: true,
      createdAt: new Date(),
    }),
  },
  {
    role: 'doctor',
    prefix: 'd_',
    collection: 'doctors',
    profileData: (profileId, uid) => ({
      doctorId: profileId,
      ownerUid: uid,
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    }),
  },
  {
    role: 'medicalStore',
    prefix: 'm_',
    collection: 'medical_stores',
    profileData: (profileId, uid) => ({
      storeId: profileId,
      ownerUid: uid,
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    }),
  },
  {
    role: 'lab',
    prefix: 'l_',
    collection: 'labs',
    profileData: (profileId, uid) => ({
      labId: profileId,
      ownerUid: uid,
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    }),
  },
  {
    role: 'ambulance',
    prefix: 'a_',
    collection: 'ambulances',
    profileData: (profileId, uid) => ({
      ambulanceId: profileId,
      authUid: uid,
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    }),
  },
];

test('legit registration for all 5 roles succeeds via client-shaped 3-doc batch (claim + user + profile)', async () => {
  for (const { role, prefix, collection, profileData } of ROLES) {
    const uid = `uid_legit_${role}`;
    const profileId = `${prefix}valid_claim_${role}`;
    const ctx = testEnv.authenticatedContext(uid);
    const db = ctx.firestore();

    const batch = db.batch();
    // 1. profile_claims
    const claimRef = db.collection('profile_claims').doc(profileId);
    batch.set(claimRef, {
      uid,
      role,
      createdAt: new Date(),
    });

    // 2. users/{uid}
    const userRef = db.collection('users').doc(uid);
    batch.set(userRef, {
      role,
      profileId,
      displayName: `Test User ${role}`,
      createdAt: new Date(),
    });

    // 3. Domain profile doc
    const profileRef = db.collection(collection).doc(profileId);
    batch.set(profileRef, profileData(profileId, uid));

    await assertSucceeds(batch.commit());
  }
});

test('registering with an existing claimed profileId fails (duplicate profileId)', async () => {
  const victimUid = 'uid_victim_user';
  const victimProfileId = 'p_victim_claim_123';
  const attackerUid = 'uid_attacker_user';

  // Seed existing claim and user
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(victimProfileId).set({
      uid: victimUid,
      role: 'patient',
      createdAt: new Date(),
    });
    await db.collection('users').doc(victimUid).set({
      role: 'patient',
      profileId: victimProfileId,
      createdAt: new Date(),
    });
    await db.collection('patients').doc(victimProfileId).set({
      patientId: victimProfileId,
      ownerUid: victimUid,
      verified: true,
      createdAt: new Date(),
    });
  });

  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();

  const batch = attackerDb.batch();
  batch.set(attackerDb.collection('profile_claims').doc(victimProfileId), {
    uid: attackerUid,
    role: 'patient',
    createdAt: new Date(),
  });
  batch.set(attackerDb.collection('users').doc(attackerUid), {
    role: 'patient',
    profileId: victimProfileId,
    createdAt: new Date(),
  });
  batch.set(attackerDb.collection('patients').doc(victimProfileId), {
    patientId: victimProfileId,
    ownerUid: attackerUid,
    verified: true,
    createdAt: new Date(),
  });

  await assertFails(batch.commit());
});

test('CONTROL: registering with a unique unclaimed profileId succeeds', async () => {
  const legitUid = 'uid_control_unique_user';
  const legitProfileId = 'p_control_unique_claim_123';
  const legitCtx = testEnv.authenticatedContext(legitUid);
  const legitDb = legitCtx.firestore();

  const batch = legitDb.batch();
  batch.set(legitDb.collection('profile_claims').doc(legitProfileId), {
    uid: legitUid,
    role: 'patient',
    createdAt: new Date(),
  });
  batch.set(legitDb.collection('users').doc(legitUid), {
    role: 'patient',
    profileId: legitProfileId,
    displayName: 'Control Patient',
    createdAt: new Date(),
  });
  batch.set(legitDb.collection('patients').doc(legitProfileId), {
    patientId: legitProfileId,
    ownerUid: legitUid,
    role: 'patient',
    verified: true,
    createdAt: new Date(),
  });

  await assertSucceeds(batch.commit());
});

test('claiming an unclaimed profile doc that already exists fails (!profileDocExistsForRole)', async () => {
  const orphanDoctorProfileId = 'd_legacy_orphan_999';
  const attackerUid = 'uid_attacker_preclaim';

  // Seed existing legacy doctor profile doc WITHOUT any claim doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(orphanDoctorProfileId).set({
      doctorId: orphanDoctorProfileId,
      ownerUid: 'uid_legacy_owner',
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    });
  });

  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();

  const batch = attackerDb.batch();
  batch.set(attackerDb.collection('profile_claims').doc(orphanDoctorProfileId), {
    uid: attackerUid,
    role: 'doctor',
    createdAt: new Date(),
  });
  batch.set(attackerDb.collection('users').doc(attackerUid), {
    role: 'doctor',
    profileId: orphanDoctorProfileId,
    createdAt: new Date(),
  });

  // Must fail because !profileDocExistsForRole('doctor', orphanDoctorProfileId) evaluates to false!
  await assertFails(batch.commit());
});

test('CONTROL: claiming an unclaimed profile doc by its legitimate owner succeeds', async () => {
  const orphanDoctorProfileId = 'd_control_orphan_888';
  const ownerUid = 'uid_legit_owner_888';

  // Seed existing legacy doctor profile doc owned by ownerUid
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(orphanDoctorProfileId).set({
      doctorId: orphanDoctorProfileId,
      ownerUid: ownerUid,
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    });
  });

  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();

  const batch = ownerDb.batch();
  batch.set(ownerDb.collection('profile_claims').doc(orphanDoctorProfileId), {
    uid: ownerUid,
    role: 'doctor',
    createdAt: new Date(),
  });
  batch.set(ownerDb.collection('users').doc(ownerUid), {
    role: 'doctor',
    profileId: orphanDoctorProfileId,
    displayName: 'Dr. Legit Owner',
    createdAt: new Date(),
  });

  await assertSucceeds(batch.commit());
});

test('registration with role mismatch between user doc and claim doc fails', async () => {
  const uid = 'uid_role_mismatch_user';
  const profileId = 'd_mismatch_claim_789';

  const ctx = testEnv.authenticatedContext(uid);
  const db = ctx.firestore();

  const batch = db.batch();
  // Claim says doctor
  batch.set(db.collection('profile_claims').doc(profileId), {
    uid,
    role: 'doctor',
    createdAt: new Date(),
  });
  // User doc claims patient
  batch.set(db.collection('users').doc(uid), {
    role: 'patient',
    profileId,
    displayName: 'Mismatch User',
    createdAt: new Date(),
  });

  await assertFails(batch.commit());
});

test('CONTROL: registration with matching roles between user doc and claim doc succeeds', async () => {
  const uid = 'uid_matching_roles_user';
  const profileId = 'd_matching_claim_789';

  const ctx = testEnv.authenticatedContext(uid);
  const db = ctx.firestore();

  const batch = db.batch();
  batch.set(db.collection('profile_claims').doc(profileId), {
    uid,
    role: 'doctor',
    createdAt: new Date(),
  });
  batch.set(db.collection('users').doc(uid), {
    role: 'doctor',
    profileId,
    displayName: 'Matching Roles User',
    createdAt: new Date(),
  });
  batch.set(db.collection('doctors').doc(profileId), {
    doctorId: profileId,
    ownerUid: uid,
    verified: false,
    verificationStatus: 'profile_incomplete',
    createdAt: new Date(),
  });

  await assertSucceeds(batch.commit());
});

test('users doc created without claim fails', async () => {
  const uid = 'uid_no_claim_user';
  const profileId = 'p_unclaimed_999';

  const ctx = testEnv.authenticatedContext(uid);
  const db = ctx.firestore();

  // Attempt to write users/{uid} directly without creating a profile_claim in the batch
  await assertFails(
    db.collection('users').doc(uid).set({
      role: 'patient',
      profileId,
      displayName: 'No Claim User',
      createdAt: new Date(),
    })
  );
});

test('CONTROL: users doc created with valid claim in batch succeeds', async () => {
  const uid = 'uid_with_claim_user';
  const profileId = 'p_claimed_control_999';

  const ctx = testEnv.authenticatedContext(uid);
  const db = ctx.firestore();

  const batch = db.batch();
  batch.set(db.collection('profile_claims').doc(profileId), {
    uid,
    role: 'patient',
    createdAt: new Date(),
  });
  batch.set(db.collection('users').doc(uid), {
    role: 'patient',
    profileId,
    displayName: 'Claimed User',
    createdAt: new Date(),
  });
  batch.set(db.collection('patients').doc(profileId), {
    patientId: profileId,
    ownerUid: uid,
    role: 'patient',
    verified: true,
    createdAt: new Date(),
  });

  await assertSucceeds(batch.commit());
});

test('profile_claims read permissions: owner and superadmin succeed, third party fails', async () => {
  const ownerUid = 'uid_claim_owner_1';
  const otherUid = 'uid_claim_snooper_2';
  const adminEmail = 'admin@doctornect.com';
  const profileId = 'p_claim_read_test_1';

  // Seed claim doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: new Date(),
    });
  });

  // 1. Owner reads own claim -> succeeds
  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  await assertSucceeds(ownerCtx.firestore().collection('profile_claims').doc(profileId).get());

  // 2. Super admin reads claim -> succeeds
  const adminCtx = testEnv.authenticatedContext('uid_admin_user', {
    email: adminEmail,
    email_verified: true,
  });
  await assertSucceeds(adminCtx.firestore().collection('profile_claims').doc(profileId).get());

  // 3. Unrelated user reads claim -> fails
  const otherCtx = testEnv.authenticatedContext(otherUid);
  await assertFails(otherCtx.firestore().collection('profile_claims').doc(profileId).get());
});

test('existing user update paths still work after initial creation', async () => {
  const uid = 'uid_update_tester';
  const profileId = 'p_update_tester_123';

  // Seed user with claim
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid,
      role: 'patient',
      createdAt: new Date(),
    });
    await db.collection('users').doc(uid).set({
      role: 'patient',
      profileId,
      displayName: 'Original Name',
      profileCompleted: false,
      createdAt: new Date(),
    });
  });

  const ctx = testEnv.authenticatedContext(uid);
  const db = ctx.firestore();

  // Update allowed fields
  await assertSucceeds(
    db.collection('users').doc(uid).update({
      displayName: 'New Updated Name',
      profileCompleted: true,
    })
  );
});

test('(a) legacy user with profile doc and no claim: legitimate owner can claim, attacker is blocked', async () => {
  const legacyOwnerUid = 'uid_legacy_owner_doc';
  const legacyDoctorProfileId = 'd_legacy_doctor_888';
  const attackerUid = 'uid_attacker_legacy';

  // Seed existing doctor profile doc with ownerUid = legacyOwnerUid, WITHOUT claim or users doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(legacyDoctorProfileId).set({
      doctorId: legacyDoctorProfileId,
      ownerUid: legacyOwnerUid,
      name: 'Dr. Legacy',
      verified: false,
      verificationStatus: 'profile_incomplete',
      createdAt: new Date(),
    });
  });

  // 1. Attacker attempts to claim it -> FAILS
  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();
  const attackerBatch = attackerDb.batch();
  attackerBatch.set(attackerDb.collection('profile_claims').doc(legacyDoctorProfileId), {
    uid: attackerUid,
    role: 'doctor',
    createdAt: new Date(),
  });
  attackerBatch.set(attackerDb.collection('users').doc(attackerUid), {
    role: 'doctor',
    profileId: legacyDoctorProfileId,
    displayName: 'Attacker Impersonator',
    createdAt: new Date(),
  });
  await assertFails(attackerBatch.commit());

  // 2. Legitimate owner repairs/claims it -> SUCCEEDS
  const ownerCtx = testEnv.authenticatedContext(legacyOwnerUid);
  const ownerDb = ownerCtx.firestore();
  const ownerBatch = ownerDb.batch();
  ownerBatch.set(ownerDb.collection('profile_claims').doc(legacyDoctorProfileId), {
    uid: legacyOwnerUid,
    role: 'doctor',
    createdAt: new Date(),
  });
  ownerBatch.set(ownerDb.collection('users').doc(legacyOwnerUid), {
    role: 'doctor',
    profileId: legacyDoctorProfileId,
    displayName: 'Dr. Legacy',
    createdAt: new Date(),
  });
  await assertSucceeds(ownerBatch.commit());
});

test('(b) user with existing claim: legitimate owner can repair/update claim, attacker is blocked', async () => {
  const ownerUid = 'uid_owner_repair_b';
  const profileId = 'p_patient_repair_b';
  const attackerUid = 'uid_attacker_repair_b';

  const seededCreatedAt = new Date();

  // Seed existing claim
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: seededCreatedAt,
    });
  });

  // 1. Attacker attempts to update/overwrite the existing claim -> FAILS
  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();
  await assertFails(
    attackerDb.collection('profile_claims').doc(profileId).set({
      uid: attackerUid,
      role: 'patient',
      createdAt: seededCreatedAt,
    }, { merge: true })
  );

  // 2. Legitimate owner running repairMissingProfile update -> SUCCEEDS
  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();
  await assertSucceeds(
    ownerDb.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: seededCreatedAt,
    }, { merge: true })
  );
});

test('(c) users doc missing: legitimate owner repairs missing users doc using existing claim in batch', async () => {
  const ownerUid = 'uid_missing_user_doc_owner';
  const profileId = 'p_patient_missing_user_c';
  const seededCreatedAt = new Date();

  // Seed claim and patient doc, but NO users doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: seededCreatedAt,
    });
    await db.collection('patients').doc(profileId).set({
      patientId: profileId,
      ownerUid: ownerUid,
      name: 'Repaired Patient',
      verified: true,
      createdAt: seededCreatedAt,
    });
  });

  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();

  // Execute repairMissingProfile batch: set claim with merge + set users/{uid}
  const repairBatch = ownerDb.batch();
  repairBatch.set(ownerDb.collection('profile_claims').doc(profileId), {
    uid: ownerUid,
    role: 'patient',
    createdAt: seededCreatedAt,
  }, { merge: true });

  repairBatch.set(ownerDb.collection('users').doc(ownerUid), {
    role: 'patient',
    profileId: profileId,
    displayName: 'Repaired Patient',
    createdAt: seededCreatedAt,
    updatedAt: seededCreatedAt,
  });

  await assertSucceeds(repairBatch.commit());
});

test('(1) a new claim for a profileId whose role profile doc exists and is owned by someone else is denied', async () => {
  const victimUid = 'uid_victim_doctor_owner';
  const attackerUid = 'uid_attacker_claim_attempt';
  const profileId = 'd_victim_doc_1';

  // Seed doctor doc owned by victim, but NO claim doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(profileId).set({
      doctorId: profileId,
      ownerUid: victimUid,
      name: 'Dr. Victim',
      verified: true,
      createdAt: new Date(),
    });
  });

  // Attacker attempts to claim this profileId -> FAILS
  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();
  await assertFails(
    attackerDb.collection('profile_claims').doc(profileId).set({
      uid: attackerUid,
      role: 'doctor',
      createdAt: new Date(),
    })
  );
});

test('CONTROL for (1): legitimate owner can create claim for their existing doctor doc', async () => {
  const ownerUid = 'uid_victim_doctor_owner_ctrl';
  const profileId = 'd_owner_ctrl_doc_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(profileId).set({
      doctorId: profileId,
      ownerUid: ownerUid,
      name: 'Dr. Owner Control',
      verified: true,
      createdAt: new Date(),
    });
  });

  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();
  await assertSucceeds(
    ownerDb.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'doctor',
      createdAt: new Date(),
    })
  );
});

test('(2) owner cannot change claim role', async () => {
  const ownerUid = 'uid_owner_role_change_attempt';
  const profileId = 'p_owner_immutable_role';
  const createdAt = new Date();

  // Seed valid claim doc
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: createdAt,
    });
  });

  // Owner attempts to change claim role from patient to doctor -> FAILS
  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();
  await assertFails(
    ownerDb.collection('profile_claims').doc(profileId).update({
      role: 'doctor',
    })
  );
});

test('CONTROL for (2): owner updating claim with unchanged role succeeds', async () => {
  const ownerUid = 'uid_owner_role_ctrl_2';
  const profileId = 'p_owner_role_ctrl_2';
  const createdAt = new Date();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('profile_claims').doc(profileId).set({
      uid: ownerUid,
      role: 'patient',
      createdAt: createdAt,
    });
  });

  const ownerCtx = testEnv.authenticatedContext(ownerUid);
  const ownerDb = ownerCtx.firestore();
  await assertSucceeds(
    ownerDb.collection('profile_claims').doc(profileId).update({
      uid: ownerUid,
      role: 'patient',
      createdAt: createdAt,
    })
  );
});

test('(3) attacker cannot claim an existing victim doc', async () => {
  const victimUid = 'uid_victim_patient_3';
  const attackerUid = 'uid_attacker_takeover_3';
  const profileId = 'p_victim_patient_3';

  // Seed patient doc owned by victim
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('patients').doc(profileId).set({
      patientId: profileId,
      ownerUid: victimUid,
      name: 'Patient Victim',
      verified: true,
      createdAt: new Date(),
    });
  });

  // Attacker tries to register / create claim for victim's patient doc -> FAILS
  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();
  await assertFails(
    attackerDb.collection('profile_claims').doc(profileId).set({
      uid: attackerUid,
      role: 'patient',
      createdAt: new Date(),
    })
  );
});

test('CONTROL for (3): legitimate owner claiming their own existing patient doc succeeds', async () => {
  const victimUid = 'uid_victim_patient_3_ctrl';
  const profileId = 'p_victim_patient_3_ctrl';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('patients').doc(profileId).set({
      patientId: profileId,
      ownerUid: victimUid,
      name: 'Patient Owner Control',
      verified: true,
      createdAt: new Date(),
    });
  });

  const ownerCtx = testEnv.authenticatedContext(victimUid);
  const ownerDb = ownerCtx.firestore();
  await assertSucceeds(
    ownerDb.collection('profile_claims').doc(profileId).set({
      uid: victimUid,
      role: 'patient',
      createdAt: new Date(),
    })
  );
});

test('(4) cross-role claim: attacker claims role patient with existing doctors/<id> of another user -> denied', async () => {
  const victimDoctorUid = 'uid_victim_doctor_4';
  const attackerUid = 'uid_attacker_cross_4';
  const doctorProfileId = 'd_victim_doc_4';

  // Seed doctor doc owned by victimDoctorUid
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(doctorProfileId).set({
      doctorId: doctorProfileId,
      ownerUid: victimDoctorUid,
      name: 'Dr. Victim',
      verified: true,
      createdAt: new Date(),
    });
  });

  // Attacker tries to claim role 'patient' using the existing doctor doc id -> FAILS
  const attackerCtx = testEnv.authenticatedContext(attackerUid);
  const attackerDb = attackerCtx.firestore();
  await assertFails(
    attackerDb.collection('profile_claims').doc(doctorProfileId).set({
      uid: attackerUid,
      role: 'patient',
      createdAt: new Date(),
    })
  );
});

test('(5) cross-role claim: owner of that doctor doc claiming role doctor -> allowed', async () => {
  const victimDoctorUid = 'uid_victim_doctor_5';
  const doctorProfileId = 'd_victim_doc_5';

  // Seed doctor doc owned by victimDoctorUid
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('doctors').doc(doctorProfileId).set({
      doctorId: doctorProfileId,
      ownerUid: victimDoctorUid,
      name: 'Dr. Victim 5',
      verified: true,
      createdAt: new Date(),
    });
  });

  // Legitimate owner claims role 'doctor' for their own doc -> ALLOWED
  const ownerCtx = testEnv.authenticatedContext(victimDoctorUid);
  const ownerDb = ownerCtx.firestore();
  await assertSucceeds(
    ownerDb.collection('profile_claims').doc(doctorProfileId).set({
      uid: victimDoctorUid,
      role: 'doctor',
      createdAt: new Date(),
    })
  );
});

