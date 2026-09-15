/**
 * Audits Firestore role docs used by KYC storage paths for ownership fields.
 *
 * Usage (from functions/):
 *   gcloud auth application-default login
 *   node scripts/audit-kyc-owneruid.js
 *
 * Optional env:
 *   FIREBASE_PROJECT_ID (default: medibond-45fad)
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'medibond-45fad';

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();

const COLLECTIONS = [
  {
    storagePrefix: 'doctors',
    collection: 'doctors',
    ownerField: 'ownerUid',
  },
  {
    storagePrefix: 'pharmacies',
    collection: 'medical_stores',
    ownerField: 'ownerUid',
  },
  {
    storagePrefix: 'labs',
    collection: 'labs',
    ownerField: 'ownerUid',
  },
  {
    storagePrefix: 'ambulances',
    collection: 'ambulances',
    ownerField: 'authUid',
    note: 'Ambulance ownership uses authUid, not ownerUid.',
    skipUsersDocCheck: true,
  },
];

function summarizeDoc(doc, ownerField) {
  const data = doc.data() || {};
  const ownerValue = String(data[ownerField] || '').trim();
  const usersProfileIdMatch = ownerValue;
  return {
    id: doc.id,
    ownerField,
    ownerValue: ownerValue || null,
    hasOwner: ownerValue.length > 0,
    email: data.email || null,
    verified: data.verified ?? null,
    authUid: data.authUid || null,
    ownerUid: data.ownerUid || null,
    usersDocExistsHint: usersProfileIdMatch,
  };
}

async function auditCollection(config) {
  const snap = await db.collection(config.collection).get();
  const rows = snap.docs.map((doc) => summarizeDoc(doc, config.ownerField));
  const missing = rows.filter((row) => !row.hasOwner);
  const mismatchedUsers = [];

  for (const row of rows.filter((entry) => entry.hasOwner)) {
    if (config.skipUsersDocCheck) {
      continue;
    }
    const userSnap = await db.collection('users').doc(row.ownerValue).get();
    if (!userSnap.exists) {
      mismatchedUsers.push({
        ...row,
        issue: 'owner points to missing users/{uid} doc',
      });
      continue;
    }
    const profileId = String(userSnap.data()?.profileId || '').trim();
    if (profileId && profileId !== row.id) {
      mismatchedUsers.push({
        ...row,
        issue: `users/${row.ownerValue}.profileId=${profileId} != ${config.collection}/${row.id}`,
        usersProfileId: profileId,
      });
    }
  }

  return {
    ...config,
    total: rows.length,
    missingOwner: missing,
    mismatched: mismatchedUsers,
  };
}

async function main() {
  console.log(`Auditing KYC ownership fields in project ${PROJECT_ID}\n`);
  const reports = [];
  for (const config of COLLECTIONS) {
    reports.push(await auditCollection(config));
  }

  let blockRuleTightening = false;
  for (const report of reports) {
    console.log(`=== ${report.collection} (storage: ${report.storagePrefix}/) ===`);
    if (report.note) console.log(report.note);
    console.log(`Total docs: ${report.total}`);
    console.log(`Missing ${report.ownerField}: ${report.missingOwner.length}`);
    console.log(`Mismatched ownership: ${report.mismatched.length}`);

    if (report.missingOwner.length > 0) {
      blockRuleTightening = true;
      console.log('Missing owner samples:');
      for (const row of report.missingOwner.slice(0, 10)) {
        console.log(`  - ${row.id} email=${row.email ?? '(none)'} verified=${row.verified}`);
      }
      if (report.missingOwner.length > 10) {
        console.log(`  ... and ${report.missingOwner.length - 10} more`);
      }
    }

    if (report.mismatched.length > 0) {
      blockRuleTightening = true;
      console.log('Mismatch samples:');
      for (const row of report.mismatched.slice(0, 10)) {
        console.log(`  - ${row.id}: ${row.issue}`);
      }
      if (report.mismatched.length > 10) {
        console.log(`  ... and ${report.mismatched.length - 10} more`);
      }
    }
    console.log('');
  }

  if (blockRuleTightening) {
    console.log('RESULT: DO NOT tighten storage.rules yet — fix ownership data first.');
    process.exitCode = 2;
    return;
  }

  console.log('RESULT: Ownership data looks consistent. Safe to proceed with storage.rules tightening.');
}

main().catch((err) => {
  console.error('Audit failed:', err.message || err);
  process.exitCode = 1;
});
