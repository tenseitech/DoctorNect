#!/usr/bin/env node
'use strict';

/**
 * Administrative purge script for DoctorNect user and associated profiles by phone number.
 *
 * Performs:
 * 1. Deep discovery across all Firestore collections, Auth, and Storage.
 * 2. Cascade deletion across Auth, profiles, transactions, and audit records.
 * 3. Preserves unrelated users by stripping cross-references instead of deleting.
 *
 * Usage:
 *   node scripts/purge-user-by-phone.js --phone=9146324098 [--dry-run]
 *   node scripts/purge-user-by-phone.js --phone=9146324098 --execute
 *   node scripts/purge-user-by-phone.js --phone=9146324098 --role=medicalStore --execute
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { Firestore } = require('@google-cloud/firestore');
const { OAuth2Client } = require('google-auth-library');

// Command-line argument parsing
const args = process.argv.slice(2);
let targetPhoneRaw = '9146324098';
let roleFilter = 'all';
let isDryRun = true;

for (const arg of args) {
  if (arg.startsWith('--phone=')) {
    targetPhoneRaw = arg.split('=')[1].trim();
  } else if (arg.startsWith('--role=')) {
    roleFilter = arg.split('=')[1].trim().toLowerCase();
  } else if (arg === '--execute') {
    isDryRun = false;
  } else if (arg === '--dry-run') {
    isDryRun = true;
  }
}

// Normalize phone digits
function normalizeDigits(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith('0')) return digits.slice(1);
  return digits;
}

const targetDigits = normalizeDigits(targetPhoneRaw);
if (!targetDigits || targetDigits.length !== 10) {
  console.error(`Invalid phone number: ${targetPhoneRaw}. Expected 10 digits.`);
  process.exit(1);
}

const PHONE_VARIANTS = [
  targetDigits,
  `+91${targetDigits}`,
  `91${targetDigits}`,
  `0${targetDigits}`,
  `+91 ${targetDigits}`,
];

const OTP_ROLES = ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance'];
function mobileHash(role, digits) {
  return crypto.createHash('sha256').update(`${role}:${digits}`).digest('hex');
}
function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'medibond-45fad';
const STORAGE_BUCKET = `${PROJECT_ID}.firebasestorage.app`;

// Resolve Google OAuth credentials from firebase-tools config
function getAuthDetails() {
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (fs.existsSync(configPath)) {
    try {
      const conf = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      if (conf.tokens?.access_token) {
        const client = new OAuth2Client();
        client.setCredentials(conf.tokens);
        return { client, token: conf.tokens.access_token };
      }
    } catch (e) {
      console.warn('Warning: Could not parse firebase-tools.json:', e.message);
    }
  }
  return { client: null, token: null };
}

const { client: authClient, token: oauthToken } = getAuthDetails();
if (!authClient || !oauthToken) {
  console.error('Error: Could not obtain OAuth token from Firebase CLI.');
  process.exit(1);
}

const db = new Firestore({ projectId: PROJECT_ID, authClient });

async function deleteFirebaseAuthUser(uid) {
  const url = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:delete`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${oauthToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ localId: uid }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    if (body.error?.message === 'USER_NOT_FOUND') return { ok: true, notFound: true };
    throw new Error(`Auth delete error for ${uid}: ${JSON.stringify(body)}`);
  }
  return { ok: true };
}

async function deleteStorageObject(name) {
  const encoded = encodeURIComponent(name);
  const url = `https://storage.googleapis.com/storage/v1/b/${STORAGE_BUCKET}/o/${encoded}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${oauthToken}` },
  });
  if (!res.ok && res.status !== 404) {
    const body = await res.text().catch(() => '');
    throw new Error(`Storage delete error for ${name}: ${body}`);
  }
  return { ok: true };
}

async function runPurge() {
  console.log('======================================================================');
  console.log(`DOCTORNECT PRIVACY PURGE: Phone Number ${targetDigits}`);
  console.log(`Role Filter: ${roleFilter} | Mode: ${isDryRun ? 'DRY-RUN (AUDIT ONLY)' : 'EXECUTE (DATA WIPE)'}`);
  console.log('======================================================================\n');

  // 1. Discover target users from 'users' collection
  const userSnaps = await db.collection('users').get();
  const matchedUsers = [];

  userSnaps.forEach((doc) => {
    const data = doc.data();
    const str = JSON.stringify(data);
    const matchesPhone = PHONE_VARIANTS.some((v) => str.includes(v));
    if (matchesPhone) {
      const userRole = String(data.role || '').toLowerCase();
      if (
        roleFilter === 'all' ||
        userRole === roleFilter ||
        (roleFilter === 'pharmacy' && userRole === 'medicalstore') ||
        (roleFilter === 'medicalstore' && userRole === 'pharmacy')
      ) {
        matchedUsers.push({ id: doc.id, ...data });
      }
    }
  });

  const uids = new Set(matchedUsers.map((u) => u.id));
  const profileIds = new Set(matchedUsers.map((u) => u.profileId).filter(Boolean));
  const emails = new Set(matchedUsers.map((u) => u.email).filter(Boolean));

  // 2. Discover role-specific profiles matching this phone or owned by these UIDs
  const roleCollectionsMap = {
    medicalstore: ['medical_stores'],
    pharmacy: ['medical_stores'],
    doctor: ['doctors'],
    patient: ['patients'],
    lab: ['labs'],
    ambulance: ['ambulances'],
  };
  const roleCollections = roleFilter === 'all'
    ? ['medical_stores', 'doctors', 'patients', 'labs', 'ambulances']
    : (roleCollectionsMap[roleFilter] || ['medical_stores']);
  const matchedProfiles = {};

  for (const coll of roleCollections) {
    matchedProfiles[coll] = [];
    const snap = await db.collection(coll).get();
    snap.forEach((doc) => {
      const data = doc.data();
      const str = JSON.stringify(data);
      let match = false;
      if (profileIds.has(doc.id)) match = true;
      if (data.ownerUid && uids.has(data.ownerUid)) match = true;
      if (data.authUid && uids.has(data.authUid)) match = true;
      if (PHONE_VARIANTS.some((v) => str.includes(v))) {
        // Exclude unrelated patients whose careTeam simply referenced a target doctor
        if (coll === 'patients' && data.mobile && !PHONE_VARIANTS.some((v) => data.mobile.includes(v))) {
          match = false;
        } else {
          match = true;
        }
      }

      if (match) {
        matchedProfiles[coll].push({ id: doc.id, data });
        profileIds.add(doc.id);
        if (data.ownerUid) uids.add(data.ownerUid);
        if (data.authUid) uids.add(data.authUid);
      }
    });
  }

  // 3. Discover transactional and history records
  const historyCollections = [
    'doctor_availability',
    'appointments',
    'referrals',
    'community_medicines',
    'in_app_notifications',
    'otp_challenges',
    'otp_verification_sessions',
    'otp_rate_limits',
    'admin_audit_logs',
  ];

  const matchedHistory = {};
  const activeOtpRoles =
    roleFilter === 'all'
      ? OTP_ROLES
      : roleFilter === 'pharmacy' || roleFilter === 'medicalstore'
      ? ['medicalStore']
      : [roleFilter];
  const targetHashes = activeOtpRoles.map((r) => mobileHash(r, targetDigits));

  for (const coll of historyCollections) {
    matchedHistory[coll] = [];
    const snap = await db.collection(coll).get();
    snap.forEach((doc) => {
      const id = doc.id;
      const data = doc.data();
      const str = JSON.stringify(data);

      let match = false;
      if (profileIds.has(id) || uids.has(id) || targetHashes.includes(id)) {
        match = true;
      } else if (coll === 'in_app_notifications' && uids.has(data.recipientUid)) {
        match = true;
      } else if (coll === 'community_medicines' && profileIds.has(data.addedByDoctorId)) {
        match = true;
      } else if (coll === 'referrals' && profileIds.has(data.fromDoctorId)) {
        match = true;
      } else if (coll === 'appointments' && (profileIds.has(data.patientId) || profileIds.has(data.doctorId))) {
        match = true;
      } else if (coll === 'admin_audit_logs' && profileIds.has(data.targetId)) {
        match = true;
      } else if (coll === 'otp_verification_sessions' && PHONE_VARIANTS.some((v) => str.includes(v))) {
        if (roleFilter === 'all' || activeOtpRoles.includes(data.role)) {
          match = true;
        }
      } else if (coll === 'otp_challenges' && PHONE_VARIANTS.some((v) => str.includes(v))) {
        if (roleFilter === 'all' || activeOtpRoles.includes(data.role)) {
          match = true;
        }
      } else if (coll === 'otp_rate_limits') {
        if (targetHashes.some((h) => id.includes(h))) match = true;
      }

      if (match) {
        matchedHistory[coll].push({ id, data });
      }
    });
  }

  // 4. Discover subcollections (e.g. patients/{id}/doctor_links)
  const matchedSubcollections = [];
  for (const pid of profileIds) {
    for (const parentColl of ['patients', 'medical_stores', 'doctors', 'users']) {
      try {
        const docRef = db.collection(parentColl).doc(pid);
        const subcols = await docRef.listCollections();
        for (const subcol of subcols) {
          const subSnap = await subcol.get();
          subSnap.forEach((subDoc) => {
            matchedSubcollections.push({
              path: `${parentColl}/${pid}/${subcol.id}/${subDoc.id}`,
              ref: subDoc.ref,
            });
          });
        }
      } catch (_) {}
    }
  }

  // 5. Discover Firebase Storage files
  const matchedStorage = [];
  try {
    const listUrl = `https://storage.googleapis.com/storage/v1/b/${STORAGE_BUCKET}/o`;
    const res = await fetch(listUrl, { headers: { Authorization: `Bearer ${oauthToken}` } });
    const storageData = await res.json();
    if (storageData.items && Array.isArray(storageData.items)) {
      for (const item of storageData.items) {
        const matchesTarget = [...uids, ...profileIds, targetDigits].some((id) => item.name.includes(id));
        if (matchesTarget) {
          matchedStorage.push(item);
        }
      }
    }
  } catch (e) {
    console.warn('Storage discovery warning:', e.message);
  }

  // 6. Discover Firebase Auth users
  const matchedAuthUsers = [];
  try {
    const authLookupUrl = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:lookup`;
    const res = await fetch(authLookupUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${oauthToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ localId: Array.from(uids) }),
    });
    const authRes = await res.json();
    if (authRes.users) {
      matchedAuthUsers.push(...authRes.users);
    }
  } catch (e) {
    console.warn('Auth lookup warning:', e.message);
  }

  // 7. Find unaffected patients whose doctor links need reference cleanup
  const cleanReferencesList = [];
  const patientSnap = await db.collection('patients').get();
  patientSnap.forEach((doc) => {
    const data = doc.data();
    if (profileIds.has(doc.id)) return; // Skipped (already scheduled for deletion)

    const needsCareTeamClean = (data.careTeamDoctorIds || []).some((did) => profileIds.has(did));
    const needsAddedClean = (data.addedDoctorIds || []).some((did) => profileIds.has(did));
    const needsHiddenClean = (data.hiddenDoctorIds || []).some((did) => profileIds.has(did));

    if (needsCareTeamClean || needsAddedClean || needsHiddenClean) {
      cleanReferencesList.push({ id: doc.id, ref: doc.ref, data });
    }
  });

  // Print Audit Report
  console.log('--- DISCOVERED RECORDS AUDIT ---');
  console.log(`Matched UIDs (${uids.size}):`, Array.from(uids));
  console.log(`Matched Profile IDs (${profileIds.size}):`, Array.from(profileIds));
  console.log(`Matched Auth Accounts: ${matchedAuthUsers.length}`);
  matchedAuthUsers.forEach((u) => console.log(`  * Auth UID: ${u.localId} | Email: ${u.email || '(none)'}`));

  console.log(`\nMatched 'users' documents: ${matchedUsers.length}`);
  matchedUsers.forEach((u) => console.log(`  * users/${u.id} (${u.role}: "${u.displayName || u.email}")`));

  for (const coll of roleCollections) {
    const count = matchedProfiles[coll].length;
    console.log(`\nMatched '${coll}' documents: ${count}`);
    matchedProfiles[coll].forEach((p) => console.log(`  * ${coll}/${p.id} (${p.data.name || p.data.storeName || p.data.serviceName || ''})`));
  }

  for (const coll of historyCollections) {
    const count = matchedHistory[coll].length;
    if (count > 0) {
      console.log(`\nMatched '${coll}' documents: ${count}`);
      matchedHistory[coll].forEach((h) => console.log(`  * ${coll}/${h.id}`));
    }
  }

  if (matchedSubcollections.length > 0) {
    console.log(`\nMatched Subcollections: ${matchedSubcollections.length}`);
    matchedSubcollections.forEach((s) => console.log(`  * ${s.path}`));
  }

  if (matchedStorage.length > 0) {
    console.log(`\nMatched Storage files: ${matchedStorage.length}`);
    matchedStorage.forEach((f) => console.log(`  * ${f.name} (${f.size} bytes)`));
  }

  if (cleanReferencesList.length > 0) {
    console.log(`\nPatients requiring reference cleanup (NOT deleting): ${cleanReferencesList.length}`);
    cleanReferencesList.forEach((p) => console.log(`  * patients/${p.id} (${p.data.name}) -> strip doctor reference`));
  }

  const totalDocs =
    matchedUsers.length +
    Object.values(matchedProfiles).reduce((acc, a) => acc + a.length, 0) +
    Object.values(matchedHistory).reduce((acc, a) => acc + a.length, 0) +
    matchedSubcollections.length;

  console.log('\n----------------------------------------------------------------------');
  console.log(`TOTALS: ${matchedAuthUsers.length} Auth users, ${totalDocs} Firestore documents, ${matchedStorage.length} Storage files.`);
  console.log('----------------------------------------------------------------------\n');

  if (isDryRun) {
    console.log('>>> DRY-RUN COMPLETE. No data was modified or deleted.');
    console.log('>>> To execute cascade deletion, re-run with --execute flag.');
    return;
  }

  // EXECUTE CASCADE DELETION
  console.log('>>> EXECUTING DATA WIPE...');

  // 1. Delete Storage Files
  for (const file of matchedStorage) {
    try {
      await deleteStorageObject(file.name);
      console.log(`[DELETED STORAGE] ${file.name}`);
    } catch (e) {
      console.error(`[STORAGE ERROR] ${file.name}:`, e.message);
    }
  }

  // 2. Delete Subcollections
  for (const item of matchedSubcollections) {
    try {
      await item.ref.delete();
      console.log(`[DELETED SUBCOLLECTION] ${item.path}`);
    } catch (e) {
      console.error(`[SUBCOLLECTION ERROR] ${item.path}:`, e.message);
    }
  }

  // 3. Delete History & Transactional Records
  for (const coll of historyCollections) {
    for (const item of matchedHistory[coll]) {
      try {
        await db.collection(coll).doc(item.id).delete();
        console.log(`[DELETED FIRESTORE] ${coll}/${item.id}`);
      } catch (e) {
        console.error(`[FIRESTORE ERROR] ${coll}/${item.id}:`, e.message);
      }
    }
  }

  // 4. Delete Role Profile Documents
  for (const coll of roleCollections) {
    for (const item of matchedProfiles[coll]) {
      try {
        await db.collection(coll).doc(item.id).delete();
        console.log(`[DELETED FIRESTORE] ${coll}/${item.id}`);
      } catch (e) {
        console.error(`[FIRESTORE ERROR] ${coll}/${item.id}:`, e.message);
      }
    }
  }

  // 5. Delete Users Documents
  for (const user of matchedUsers) {
    try {
      await db.collection('users').doc(user.id).delete();
      console.log(`[DELETED FIRESTORE] users/${user.id}`);
    } catch (e) {
      console.error(`[FIRESTORE ERROR] users/${user.id}:`, e.message);
    }
  }

  // 6. Clean up references in other patients (preserve patient, strip target doctorId)
  for (const p of cleanReferencesList) {
    try {
      const updatedCareTeam = (p.data.careTeamDoctorIds || []).filter((did) => !profileIds.has(did));
      const updatedAdded = (p.data.addedDoctorIds || []).filter((did) => !profileIds.has(did));
      const updatedHidden = (p.data.hiddenDoctorIds || []).filter((did) => !profileIds.has(did));
      const updatedDoctorsArray = (p.data.addedDoctors || []).filter((docObj) => !profileIds.has(docObj.id));

      await p.ref.update({
        careTeamDoctorIds: updatedCareTeam,
        addedDoctorIds: updatedAdded,
        hiddenDoctorIds: updatedHidden,
        addedDoctors: updatedDoctorsArray,
      });
      console.log(`[CLEANED REFERENCES] patients/${p.id} stripped deleted doctor IDs`);
    } catch (e) {
      console.error(`[REFERENCE CLEANUP ERROR] patients/${p.id}:`, e.message);
    }
  }

  // 7. Delete Firebase Auth Accounts
  for (const authUser of matchedAuthUsers) {
    try {
      await deleteFirebaseAuthUser(authUser.localId);
      console.log(`[DELETED AUTH USER] ${authUser.localId} (${authUser.email || 'no-email'})`);
    } catch (e) {
      console.error(`[AUTH DELETE ERROR] ${authUser.localId}:`, e.message);
    }
  }

  console.log('\n======================================================================');
  console.log(`COMPLETE PURGE SUCCESSFUL: All traces of ${targetDigits} have been eradicated.`);
  console.log('======================================================================\n');
}

runPurge().catch((err) => {
  console.error('FATAL ERROR DURING PURGE:', err);
  process.exit(1);
});
