'use strict';

const { bootstrapMutatingScript } = require('./lib/mutating_script_bootstrap');

/**
 * scripts/seed_reviewer_accounts.js
 *
 * Provisions or cleans up server-side pre-approved Play Store / App Store reviewer
 * accounts in Firebase (Auth + Firestore) via Firebase Admin SDK.
 *
 * Safety Guards:
 *   - DRY-RUN by default. Zero writes without explicit --apply or --delete flag.
 *   - Only fictitious dummy numbers (9999900001 - 9999900005).
 *   - Strictly guarded cleanup: --delete will REFUSE to delete any UID or document ID
 *     that does not start with the strict prefix "rev_".
 *   - Idempotent: Can be run multiple times safely without duplicate errors or data corruption.
 *   - ZERO secret values, keys, or tokens are printed or logged.
 *
 * Usage:
 *   node scripts/seed_reviewer_accounts.js            # DRY RUN (safe preview)
 *   node scripts/seed_reviewer_accounts.js --dry-run  # Explicit DRY RUN
 *   node scripts/seed_reviewer_accounts.js --apply    # Execute idempotent seed writes
 *   node scripts/seed_reviewer_accounts.js --delete   # Clean up only rev_* accounts
 *   node scripts/seed_reviewer_accounts.js --delete --dry-run # Preview deletion without writing
 */

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const isApply = args.includes('--apply');
const isDelete = args.includes('--delete');
const isExplicitDryRun = args.includes('--dry-run');
const isDryRun = isExplicitDryRun || (!isApply && !isDelete) || (isDelete && isExplicitDryRun);

const REVIEWER_ACCOUNTS = [
  {
    role: 'patient',
    profileId: 'rev_pat_001',
    firebaseUid: 'rev_fb_pat_001',
    displayName: 'Reviewer Patient',
    mobile: '9999900001',
    email: 'reviewer.patient@doctornect.test',
    collection: 'patients',
    profileData: {
      patientId: 'rev_pat_001',
      ownerUid: 'rev_fb_pat_001',
      name: 'Reviewer Patient',
      email: 'reviewer.patient@doctornect.test',
      mobile: '9999900001',
      phone: '9999900001',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      shareRecordsWithDoctors: true,
    },
  },
  {
    role: 'doctor',
    profileId: 'rev_doc_001',
    firebaseUid: 'rev_fb_doc_001',
    displayName: 'Dr. Reviewer',
    mobile: '9999900002',
    email: 'reviewer.doctor@doctornect.test',
    collection: 'doctors',
    profileData: {
      doctorId: 'rev_doc_001',
      ownerUid: 'rev_fb_doc_001',
      displayName: 'Dr. Reviewer',
      name: 'Dr. Reviewer',
      email: 'reviewer.doctor@doctornect.test',
      mobile: '9999900002',
      phone: '9999900002',
      specialization: 'General Medicine',
      qualification: 'MBBS, MD',
      experienceYears: 10,
      consultationFee: 500,
      councilReg: 'REV-MCI-99999',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'medicalStore',
    profileId: 'rev_store_001',
    firebaseUid: 'rev_fb_store_001',
    displayName: 'Reviewer Pharmacy',
    mobile: '9999900003',
    email: 'reviewer.pharmacy@doctornect.test',
    collection: 'medical_stores',
    profileData: {
      storeId: 'rev_store_001',
      ownerUid: 'rev_fb_store_001',
      storeName: 'Reviewer Pharmacy',
      name: 'Reviewer Pharmacy',
      ownerName: 'Reviewer Owner',
      email: 'reviewer.pharmacy@doctornect.test',
      mobile: '9999900003',
      phone: '9999900003',
      drugLicenseNumber: 'REV-20B-99999',
      address: 'Shop 101, Medical Market, Review City',
      city: 'Review City',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'lab',
    profileId: 'rev_lab_001',
    firebaseUid: 'rev_fb_lab_001',
    displayName: 'Reviewer Diagnostics',
    mobile: '9999900004',
    email: 'reviewer.lab@doctornect.test',
    collection: 'labs',
    profileData: {
      labId: 'rev_lab_001',
      ownerUid: 'rev_fb_lab_001',
      labName: 'Reviewer Diagnostics',
      name: 'Reviewer Diagnostics',
      email: 'reviewer.lab@doctornect.test',
      mobile: '9999900004',
      phone: '9999900004',
      licenseNumber: 'REV-NABL-99999',
      address: 'Diagnostic Complex, Sector 4, Review City',
      city: 'Review City',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'ambulance',
    profileId: 'rev_amb_001',
    firebaseUid: 'rev_fb_amb_001',
    displayName: 'Reviewer Ambulance',
    mobile: '9999900005',
    email: 'reviewer.ambulance@doctornect.test',
    collection: 'ambulances',
    profileData: {
      id: 'rev_amb_001',
      ambulanceId: 'rev_amb_001',
      authUid: 'rev_fb_amb_001',
      username: 'rev_driver', // Required: length >= 3 for completeAmbulanceMobileOtpLogin / isRegisteredAmbulanceData
      driverName: 'Reviewer Driver',
      serviceName: 'Reviewer Emergency Ambulance',
      email: 'reviewer.ambulance@doctornect.test',
      mobile: '9999900005',
      phone: '9999900005', // Required: completeAmbulanceMobileOtpLogin queries ambulances on 'phone'
      vehicleNumber: 'DL-01-REV-108',
      ambulanceType: 'als',
      city: 'Review City',
      isAvailable: true,
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
];

function initializeAdminSdk() {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) return admin;

  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
    || path.join(__dirname, 'service-account.json');

  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || 'medibond-45fad',
    });
  } else {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT || 'medibond-45fad',
    });
  }
  return admin;
}

/**
 * Asserts strict rev_ prefix invariant on all identifiers to guarantee
 * zero possibility of touching or deleting production user documents.
 */
function assertReviewerIdPrefix(acc) {
  if (!acc.firebaseUid.startsWith('rev_')) {
    throw new Error(`SAFETY FATAL: firebaseUid "${acc.firebaseUid}" does not start with "rev_" prefix! Refusing operation.`);
  }
  if (!acc.profileId.startsWith('rev_')) {
    throw new Error(`SAFETY FATAL: profileId "${acc.profileId}" does not start with "rev_" prefix! Refusing operation.`);
  }
}

async function handleDryRun(admin) {
  const db = admin.firestore();
  const auth = admin.auth();

  console.log('\n[DRY RUN] Inspecting live state to preview actions (NO WRITES):');
  console.log('----------------------------------------------------------------');

  for (const acc of REVIEWER_ACCOUNTS) {
    assertReviewerIdPrefix(acc);

    let authUserExists = false;
    try {
      await auth.getUser(acc.firebaseUid);
      authUserExists = true;
    } catch (err) {
      if (err.code !== 'auth/user-not-found') throw err;
    }

    const [userDocSnap, claimDocSnap, domainDocSnap] = await Promise.all([
      db.collection('users').doc(acc.firebaseUid).get(),
      db.collection('profile_claims').doc(acc.profileId).get(),
      db.collection(acc.collection).doc(acc.profileId).get(),
    ]);

    const authAction = authUserExists ? 'SKIP (already exists)' : 'CREATE';
    const userAction = userDocSnap.exists ? 'MERGE / UPDATE' : 'CREATE';
    const claimAction = claimDocSnap.exists ? 'MERGE / UPDATE' : 'CREATE';
    const domainAction = domainDocSnap.exists ? 'MERGE / UPDATE' : 'CREATE';

    console.log(`\nRole: ${acc.role.toUpperCase()} (Phone: ${acc.mobile})`);
    console.log(`  Auth User:         ${acc.firebaseUid} -> [${authAction}]`);
    console.log(`  Firestore Paths:`);
    console.log(`    - users/${acc.firebaseUid} -> [${userAction}]`);
    console.log(`    - profile_claims/${acc.profileId} -> [${claimAction}]`);
    console.log(`    - ${acc.collection}/${acc.profileId} -> [${domainAction}]`);
    console.log(`  Auth Custom Claims: { role: '${acc.role}', verified: true, profileId: '${acc.profileId}' }`);
  }

  console.log('\n================================================================');
  console.log('DRY RUN COMPLETE: 0 documents written, 0 auth users touched.');
  console.log('To apply these changes, rerun with:');
  console.log('  node scripts/seed_reviewer_accounts.js --apply');
  console.log('================================================================\n');
}

async function handleDeleteDryRun(admin) {
  const db = admin.firestore();
  const auth = admin.auth();

  console.log('\n[DELETE DRY-RUN] Inspecting existing reviewer documents to delete (NO WRITES):');
  console.log('----------------------------------------------------------------');

  for (const acc of REVIEWER_ACCOUNTS) {
    assertReviewerIdPrefix(acc);

    let authUserExists = false;
    try {
      await auth.getUser(acc.firebaseUid);
      authUserExists = true;
    } catch (_) {}

    const [userDocSnap, claimDocSnap, domainDocSnap] = await Promise.all([
      db.collection('users').doc(acc.firebaseUid).get(),
      db.collection('profile_claims').doc(acc.profileId).get(),
      db.collection(acc.collection).doc(acc.profileId).get(),
    ]);

    console.log(`\nRole: ${acc.role.toUpperCase()}`);
    console.log(`  Auth UID:          ${acc.firebaseUid} -> ${authUserExists ? '[WOULD DELETE]' : '[NOT FOUND / NO-OP]'}`);
    console.log(`  Firestore Paths:`);
    console.log(`    - users/${acc.firebaseUid} -> ${userDocSnap.exists ? '[WOULD DELETE]' : '[NOT FOUND / NO-OP]'}`);
    console.log(`    - profile_claims/${acc.profileId} -> ${claimDocSnap.exists ? '[WOULD DELETE]' : '[NOT FOUND / NO-OP]'}`);
    console.log(`    - ${acc.collection}/${acc.profileId} -> ${domainDocSnap.exists ? '[WOULD DELETE]' : '[NOT FOUND / NO-OP]'}`);
  }

  console.log('\n================================================================');
  console.log('DELETE DRY-RUN COMPLETE: 0 documents deleted.');
  console.log('To execute deletion, rerun with:');
  console.log('  node scripts/seed_reviewer_accounts.js --delete');
  console.log('================================================================\n');
}

async function handleDelete(admin) {
  const db = admin.firestore();
  const auth = admin.auth();

  console.log('\n[DELETE] Executing cleanup of reviewer accounts (rev_* ONLY)...');
  console.log('----------------------------------------------------------------');

  for (const acc of REVIEWER_ACCOUNTS) {
    // 1. Strict invariant check: must start with rev_
    assertReviewerIdPrefix(acc);

    console.log(`\nCleaning up ${acc.role} (${acc.firebaseUid} / ${acc.profileId})...`);

    // 2. Delete Auth User if exists
    try {
      await auth.deleteUser(acc.firebaseUid);
      console.log(`  Deleted Auth user: ${acc.firebaseUid}`);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        console.log(`  Auth user ${acc.firebaseUid} not found (already clean).`);
      } else {
        console.warn(`  Warning deleting Auth user ${acc.firebaseUid}:`, err.message);
      }
    }

    // 3. Delete Firestore docs
    const batch = db.batch();
    const userRef = db.collection('users').doc(acc.firebaseUid);
    const claimRef = db.collection('profile_claims').doc(acc.profileId);
    const domainRef = db.collection(acc.collection).doc(acc.profileId);

    batch.delete(userRef);
    batch.delete(claimRef);
    batch.delete(domainRef);

    await batch.commit();
    console.log(`  Deleted Firestore docs: users/${acc.firebaseUid}, profile_claims/${acc.profileId}, ${acc.collection}/${acc.profileId}`);
  }

  console.log('\n================================================================');
  console.log('DELETE COMPLETE: All rev_* reviewer accounts cleaned up.');
  console.log('Non-rev_ documents were strictly untouched.');
  console.log('================================================================\n');
}

async function handleApply(admin) {
  const db = admin.firestore();
  const auth = admin.auth();
  const now = admin.firestore.FieldValue.serverTimestamp();

  console.log('\n[APPLY] Executing idempotent seed of reviewer accounts...');
  console.log('----------------------------------------------------------------');

  for (const acc of REVIEWER_ACCOUNTS) {
    assertReviewerIdPrefix(acc);

    console.log(`\nSeeding ${acc.role} (${acc.profileId})...`);

    // 1. Ensure Firebase Auth user exists
    let authUser;
    try {
      authUser = await auth.getUser(acc.firebaseUid);
      console.log(`  Found existing Auth user: ${authUser.uid} (updating)`);
      await auth.updateUser(acc.firebaseUid, {
        displayName: acc.displayName,
        email: acc.email,
        phoneNumber: `+91${acc.mobile}`,
        emailVerified: true,
      });
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        authUser = await auth.createUser({
          uid: acc.firebaseUid,
          email: acc.email,
          phoneNumber: `+91${acc.mobile}`,
          displayName: acc.displayName,
          emailVerified: true,
        });
        console.log(`  Created Auth user: ${authUser.uid}`);
      } else {
        throw err;
      }
    }

    // 2. Set Custom Claims
    await auth.setCustomUserClaims(acc.firebaseUid, {
      role: acc.role,
      verified: true,
      profileId: acc.profileId,
    });
    console.log(`  Set Custom Claims: role=${acc.role}, verified=true, profileId=${acc.profileId}`);

    // 3. Write Firestore batch (idempotent merge)
    const batch = db.batch();

    // profile_claims/{profileId}
    const claimRef = db.collection('profile_claims').doc(acc.profileId);
    batch.set(claimRef, {
      uid: acc.firebaseUid,
      role: acc.role,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    // users/{uid}
    const userRef = db.collection('users').doc(acc.firebaseUid);
    batch.set(userRef, {
      role: acc.role,
      profileId: acc.profileId,
      displayName: acc.displayName,
      email: acc.email,
      mobile: acc.mobile,
      phone: acc.mobile,
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    // domain profile ({collection}/{profileId})
    const domainRef = db.collection(acc.collection).doc(acc.profileId);
    batch.set(domainRef, {
      ...acc.profileData,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    await batch.commit();
    console.log(`  Committed Firestore docs for ${acc.role} (${acc.collection}/${acc.profileId})`);
  }

  console.log('\n================================================================');
  console.log('APPLY COMPLETE: All 5 reviewer accounts successfully seeded.');
  console.log('Idempotent run: repeat executions maintain exact valid state.');
  console.log('================================================================\n');
}

async function main() {
  bootstrapMutatingScript('scripts/seed_reviewer_accounts.js');
  console.log('================================================================');
  console.log('  DOCTORNECT: PLAY STORE / APP STORE REVIEWER ACCOUNTS TOOL     ');
  console.log('================================================================');

  let modeStr = 'DRY-RUN (Safe preview — NO WRITES)';
  if (isDelete && !isExplicitDryRun) modeStr = 'DELETE (Cleanup rev_* accounts)';
  else if (isDelete && isExplicitDryRun) modeStr = 'DELETE DRY-RUN (Preview cleanup)';
  else if (isApply) modeStr = 'APPLY (Idempotent writes)';

  console.log(`MODE: ${modeStr}`);
  console.log(`Target accounts: ${REVIEWER_ACCOUNTS.length} (9999900001 - 9999900005)`);

  const admin = initializeAdminSdk();

  if (isDelete && !isExplicitDryRun) {
    await handleDelete(admin);
  } else if (isDelete && isExplicitDryRun) {
    await handleDeleteDryRun(admin);
  } else if (isDryRun) {
    await handleDryRun(admin);
  } else if (isApply) {
    await handleApply(admin);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Fatal error in reviewer accounts tool:', err);
    process.exit(1);
  });
}

module.exports = {
  REVIEWER_ACCOUNTS,
  isDryRun,
  assertReviewerIdPrefix,
};
