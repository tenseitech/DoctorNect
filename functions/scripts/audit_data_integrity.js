/**
 * Read-only integrity audit for users/profile collections.
 *
 * Usage:
 *   node scripts/audit_data_integrity.js
 *
 * Optional env:
 *   FIREBASE_PROJECT_ID=medibond-45fad
 */
'use strict';

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = String(process.env.FIREBASE_PROJECT_ID || 'medibond-45fad').trim();

const PROFILE_COLLECTION_BY_ROLE = {
  doctor: 'doctors',
  patient: 'patients',
  medicalStore: 'medical_stores',
  lab: 'labs',
  ambulance: 'ambulances',
};

const PROFILE_COLLECTIONS = ['doctors', 'patients', 'medical_stores', 'labs', 'ambulances'];

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

function nowIso() {
  return new Date().toISOString();
}

function roleToCollection(role) {
  const r = String(role || '').trim();
  return PROFILE_COLLECTION_BY_ROLE[r] || null;
}

async function buildExistingIdIndex(db) {
  const index = {};
  await Promise.all(
    PROFILE_COLLECTIONS.map(async (coll) => {
      const snap = await db.collection(coll).select().get();
      index[coll] = new Set(snap.docs.map((d) => d.id));
    }),
  );
  return index;
}

async function auditUsers(db, existingIdsByCollection) {
  const usersSnap = await db.collection('users').get();
  const issues = [];

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    const role = String(data.role || '').trim();
    const profileId = String(data.profileId || '').trim();
    const expectedCollection = roleToCollection(role);

    if (!expectedCollection) {
      issues.push({
        collection: 'users',
        id: doc.id,
        issue: 'unsupported-or-missing-role',
        details: { role, profileId },
      });
      continue;
    }

    if (!profileId) {
      issues.push({
        collection: 'users',
        id: doc.id,
        issue: 'missing-profileId',
        details: { role, expectedCollection },
      });
      continue;
    }

    if (!existingIdsByCollection[expectedCollection].has(profileId)) {
      issues.push({
        collection: 'users',
        id: doc.id,
        issue: 'profileId-target-missing',
        details: {
          role,
          profileId,
          expectedProfilePath: `${expectedCollection}/${profileId}`,
        },
      });
    }
  }

  return {
    scanned: usersSnap.size,
    issues,
  };
}

async function auditProfileCollection(db, collectionName, idFieldName) {
  const snap = await db.collection(collectionName).get();
  const issues = [];

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const ownerUid = String(data.ownerUid || '').trim();
    const idFieldValue = String(data[idFieldName] || '').trim();

    if (!ownerUid) {
      issues.push({
        collection: collectionName,
        id: doc.id,
        issue: 'missing-ownerUid',
        details: { expectedField: 'ownerUid' },
      });
    }

    if (!idFieldValue) {
      issues.push({
        collection: collectionName,
        id: doc.id,
        issue: 'missing-id-field',
        details: { field: idFieldName, expected: doc.id, actual: '' },
      });
    } else if (idFieldValue !== doc.id) {
      issues.push({
        collection: collectionName,
        id: doc.id,
        issue: 'id-field-mismatch',
        details: { field: idFieldName, expected: doc.id, actual: idFieldValue },
      });
    }
  }

  return {
    scanned: snap.size,
    issues,
  };
}

async function main() {
  const db = getFirestore();
  const startedAt = nowIso();

  const existingIdsByCollection = await buildExistingIdIndex(db);
  const usersResult = await auditUsers(db, existingIdsByCollection);
  const medicalStoresResult = await auditProfileCollection(db, 'medical_stores', 'storeId');
  const labsResult = await auditProfileCollection(db, 'labs', 'labId');
  const doctorsResult = await auditProfileCollection(db, 'doctors', 'doctorId');
  const ambulancesResult = await auditProfileCollection(db, 'ambulances', 'ambulanceId');

  const allIssues = [
    ...usersResult.issues,
    ...medicalStoresResult.issues,
    ...labsResult.issues,
    ...doctorsResult.issues,
    ...ambulancesResult.issues,
  ];

  const report = {
    meta: {
      projectId: PROJECT_ID,
      startedAt,
      completedAt: nowIso(),
      readOnly: true,
    },
    summary: {
      scanned: {
        users: usersResult.scanned,
        medical_stores: medicalStoresResult.scanned,
        labs: labsResult.scanned,
        doctors: doctorsResult.scanned,
        ambulances: ambulancesResult.scanned,
      },
      totalIssues: allIssues.length,
    },
    issuesByCollection: {
      users: usersResult.issues,
      medical_stores: medicalStoresResult.issues,
      labs: labsResult.issues,
      doctors: doctorsResult.issues,
      ambulances: ambulancesResult.issues,
    },
    issues: allIssues,
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        error: err?.message || String(err),
        stack: err?.stack || null,
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
