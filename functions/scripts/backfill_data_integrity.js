/**
 * Backfill integrity issues reported by audit_data_integrity.
 *
 * Default mode is DRY-RUN (no writes). Use --confirm to apply writes.
 *
 * Usage:
 *   node scripts/backfill_data_integrity.js
 *   node scripts/backfill_data_integrity.js --confirm
 *
 * Optional env:
 *   FIREBASE_PROJECT_ID=medibond-45fad
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = String(process.env.FIREBASE_PROJECT_ID || 'medibond-45fad').trim();
const APPLY_WRITES = process.argv.includes('--confirm');

const ROLE_CONFIG = {
  doctor: { collection: 'doctors', idField: 'doctorId' },
  patient: { collection: 'patients', idField: 'patientId' },
  medicalStore: { collection: 'medical_stores', idField: 'storeId' },
  lab: { collection: 'labs', idField: 'labId' },
  ambulance: { collection: 'ambulances', idField: 'ambulanceId' },
};

const PROVIDER_ROLE_COLLECTIONS = [
  { role: 'medicalStore', collection: 'medical_stores', idField: 'storeId' },
  { role: 'lab', collection: 'labs', idField: 'labId' },
  { role: 'doctor', collection: 'doctors', idField: 'doctorId' },
  { role: 'ambulance', collection: 'ambulances', idField: 'ambulanceId' },
];

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

function nowIso() {
  return new Date().toISOString();
}

function fileTimestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function normalizeEmail(v) {
  return String(v || '').trim().toLowerCase();
}

function normalizeMobileDigits(v) {
  const digits = String(v || '').replace(/\D/g, '');
  if (!digits) return '';
  return digits.length >= 10 ? digits.slice(-10) : digits;
}

function toArraySetMap(map, key, value) {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key).add(value);
}

function singletonFromSet(set) {
  if (!set || set.size !== 1) return null;
  return [...set][0];
}

function buildGroundTruthDescription() {
  return {
    roleDocIdField: 'For doctors/ambulances/labs/medical_stores, id field (doctorId/ambulanceId/labId/storeId) source of truth is document ID.',
    roleDocOwnerUid: [
      'Primary source: users/{uid} where role matches and profileId == roleDoc.id.',
      'Fallback: unique users doc for same role matched by normalized email/mobile fields from role doc.',
      'If ambiguous or no candidate, do not write ownerUid; mark unresolved.',
    ],
    usersProfileId: [
      'Primary source: existing role collection doc for users.role with ownerUid == users.uid (must be unique).',
      'If current profileId points to missing doc or a doc not owned by user, and unique ownerUid-linked doc exists, update profileId.',
      'If ambiguous or no role doc candidate, do not write profileId; mark unresolved.',
    ],
  };
}

async function main() {
  const db = getFirestore();
  const startedAt = nowIso();

  const usersSnap = await db.collection('users').get();
  const usersByUid = new Map();
  const usersByRoleProfile = new Map(); // key role:profileId -> Set<uid>
  const usersByRoleEmail = new Map(); // key role:email -> Set<uid>
  const usersByRoleMobile = new Map(); // key role:digits -> Set<uid>

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    const uid = doc.id;
    const role = String(data.role || '').trim();
    const profileId = String(data.profileId || '').trim();
    const email = normalizeEmail(data.email);
    const mobile = normalizeMobileDigits(
      data.mobile || data.phone || data.phoneNumber || data.mobileNumber,
    );

    usersByUid.set(uid, { ...data, uid, role, profileId, email, mobile });
    if (role && profileId) toArraySetMap(usersByRoleProfile, `${role}:${profileId}`, uid);
    if (role && email) toArraySetMap(usersByRoleEmail, `${role}:${email}`, uid);
    if (role && mobile) toArraySetMap(usersByRoleMobile, `${role}:${mobile}`, uid);
  }

  const roleCollectionState = {};
  for (const { role, collection, idField } of PROVIDER_ROLE_COLLECTIONS) {
    const snap = await db.collection(collection).get();
    const docsById = new Map();
    const idsByOwnerUid = new Map(); // uid -> Set<docId>

    for (const d of snap.docs) {
      const data = d.data() || {};
      docsById.set(d.id, data);
      const ownerUid = String(data.ownerUid || '').trim();
      if (ownerUid) toArraySetMap(idsByOwnerUid, ownerUid, d.id);
    }

    roleCollectionState[role] = {
      role,
      collection,
      idField,
      snap,
      docsById,
      idsByOwnerUid,
    };
  }

  // Include patients for user profileId resolution.
  const patientSnap = await db.collection('patients').get();
  roleCollectionState.patient = {
    role: 'patient',
    collection: 'patients',
    idField: 'patientId',
    snap: patientSnap,
    docsById: new Map(patientSnap.docs.map((d) => [d.id, d.data() || {}])),
    idsByOwnerUid: (() => {
      const m = new Map();
      for (const d of patientSnap.docs) {
        const ownerUid = String((d.data() || {}).ownerUid || '').trim();
        if (ownerUid) toArraySetMap(m, ownerUid, d.id);
      }
      return m;
    })(),
  };

  const plannedDocUpdates = []; // { path, updates, changes[] }
  const unresolved = [];

  // STEP A: provider/doc collection checks (ownerUid + id field)
  for (const { role, collection, idField } of PROVIDER_ROLE_COLLECTIONS) {
    const state = roleCollectionState[role];
    for (const doc of state.snap.docs) {
      const data = doc.data() || {};
      const patch = {};
      const changes = [];

      const idCurrent = String(data[idField] || '').trim();
      if (!idCurrent || idCurrent !== doc.id) {
        patch[idField] = doc.id;
        changes.push({
          field: idField,
          oldValue: idCurrent || null,
          newValue: doc.id,
          reason: idCurrent ? 'id-field-mismatch' : 'id-field-missing',
          inference: 'document-id-is-source-of-truth',
        });
      }

      const ownerUidCurrent = String(data.ownerUid || '').trim();
      let ownerUidTarget = null;
      let ownerInference = null;

      const exactMatchUid = singletonFromSet(usersByRoleProfile.get(`${role}:${doc.id}`));
      if (exactMatchUid) {
        ownerUidTarget = exactMatchUid;
        ownerInference = 'users-role+profileId-exact-match';
      } else {
        const email = normalizeEmail(data.email);
        const mobile = normalizeMobileDigits(
          data.mobile || data.phone || data.phoneNumber || data.mobileNumber,
        );
        const byEmail = email ? singletonFromSet(usersByRoleEmail.get(`${role}:${email}`)) : null;
        const byMobile = mobile ? singletonFromSet(usersByRoleMobile.get(`${role}:${mobile}`)) : null;

        if (byEmail && byMobile && byEmail === byMobile) {
          ownerUidTarget = byEmail;
          ownerInference = 'users-role-email+mobile-unique-match';
        } else if (byEmail && !byMobile) {
          ownerUidTarget = byEmail;
          ownerInference = 'users-role-email-unique-match';
        } else if (byMobile && !byEmail) {
          ownerUidTarget = byMobile;
          ownerInference = 'users-role-mobile-unique-match';
        }
      }

      const ownerLooksInvalid = !ownerUidCurrent
        || !usersByUid.has(ownerUidCurrent)
        || usersByUid.get(ownerUidCurrent).role !== role
        || usersByUid.get(ownerUidCurrent).profileId !== doc.id;

      if (ownerLooksInvalid) {
        if (ownerUidTarget) {
          if (ownerUidCurrent !== ownerUidTarget) {
            patch.ownerUid = ownerUidTarget;
            changes.push({
              field: 'ownerUid',
              oldValue: ownerUidCurrent || null,
              newValue: ownerUidTarget,
              reason: ownerUidCurrent ? 'ownerUid-mismatch' : 'ownerUid-missing',
              inference: ownerInference,
            });
          }
        } else {
          unresolved.push({
            path: `${collection}/${doc.id}`,
            issue: ownerUidCurrent ? 'ownerUid-mismatch-unresolved' : 'ownerUid-missing-unresolved',
            details: {
              currentOwnerUid: ownerUidCurrent || null,
              role,
              suggestion: 'Manual review required (no unique owner candidate).',
            },
          });
        }
      }

      if (changes.length > 0) {
        patch.updatedAt = FieldValue.serverTimestamp();
        plannedDocUpdates.push({
          path: `${collection}/${doc.id}`,
          updates: patch,
          changes,
        });
      }
    }
  }

  // Build owner index that reflects planned ownerUid updates too.
  const projectedOwnerIndex = new Map(); // key role:uid -> Set<docId>
  for (const role of Object.keys(ROLE_CONFIG)) {
    const state = roleCollectionState[role];
    if (!state) continue;
    for (const doc of state.snap.docs) {
      const existing = doc.data() || {};
      let ownerUid = String(existing.ownerUid || '').trim();
      const planned = plannedDocUpdates.find((u) => u.path === `${state.collection}/${doc.id}`);
      if (planned && planned.updates.ownerUid) ownerUid = String(planned.updates.ownerUid).trim();
      if (ownerUid) toArraySetMap(projectedOwnerIndex, `${role}:${ownerUid}`, doc.id);
    }
  }

  // STEP B: users profileId corrections
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const data = userDoc.data() || {};
    const role = String(data.role || '').trim();
    const cfg = ROLE_CONFIG[role];
    if (!cfg) continue;

    const profileIdCurrent = String(data.profileId || '').trim();
    const roleState = roleCollectionState[role];

    const currentExists = profileIdCurrent
      ? roleState.docsById.has(profileIdCurrent)
      : false;
    const currentOwnedByUid = currentExists
      ? String((roleState.docsById.get(profileIdCurrent) || {}).ownerUid || '').trim() === uid
      : false;

    const ownerCandidates = projectedOwnerIndex.get(`${role}:${uid}`) || new Set();
    const uniqueOwnedId = singletonFromSet(ownerCandidates);

    const needsFix = !profileIdCurrent || !currentExists || !currentOwnedByUid;
    if (!needsFix) continue;

    if (uniqueOwnedId) {
      const updates = {
        profileId: uniqueOwnedId,
        updatedAt: FieldValue.serverTimestamp(),
      };
      plannedDocUpdates.push({
        path: `users/${uid}`,
        updates,
        changes: [{
          field: 'profileId',
          oldValue: profileIdCurrent || null,
          newValue: uniqueOwnedId,
          reason: !profileIdCurrent
            ? 'profileId-missing'
            : (!currentExists ? 'profileId-target-missing' : 'profileId-owner-mismatch'),
          inference: 'unique-role-doc-owned-by-user',
        }],
      });
    } else {
      unresolved.push({
        path: `users/${uid}`,
        issue: !profileIdCurrent ? 'profileId-missing-unresolved' : 'profileId-mismatch-unresolved',
        details: {
          role,
          profileIdCurrent: profileIdCurrent || null,
          ownerCandidateCount: ownerCandidates.size,
          suggestion: 'Manual review required (no unique role doc candidate).',
        },
      });
    }
  }

  let appliedWrites = 0;
  let writeErrors = [];
  if (APPLY_WRITES) {
    for (const op of plannedDocUpdates) {
      const [collection, id] = op.path.split('/');
      try {
        await db.collection(collection).doc(id).set(op.updates, { merge: true });
        appliedWrites += 1;
      } catch (err) {
        writeErrors.push({
          path: op.path,
          error: err?.message || String(err),
        });
      }
    }
  }

  const completedAt = nowIso();
  const changeLog = plannedDocUpdates.flatMap((op) =>
    op.changes.map((c) => ({
      mode: APPLY_WRITES ? 'apply' : 'dry-run',
      path: op.path,
      field: c.field,
      oldValue: c.oldValue,
      newValue: c.newValue,
      reason: c.reason,
      inference: c.inference,
    })),
  );

  const report = {
    meta: {
      projectId: PROJECT_ID,
      mode: APPLY_WRITES ? 'confirm-write' : 'dry-run',
      readOnly: !APPLY_WRITES,
      startedAt,
      completedAt,
      fileGeneratedAt: completedAt,
    },
    groundTruth: buildGroundTruthDescription(),
    summary: {
      scanned: {
        users: usersSnap.size,
        medical_stores: roleCollectionState.medicalStore.snap.size,
        labs: roleCollectionState.lab.snap.size,
        doctors: roleCollectionState.doctor.snap.size,
        ambulances: roleCollectionState.ambulance.snap.size,
        patients: roleCollectionState.patient.snap.size,
      },
      plannedDocumentUpdates: plannedDocUpdates.length,
      plannedFieldChanges: changeLog.length,
      appliedWrites,
      writeErrors: writeErrors.length,
      unresolved: unresolved.length,
    },
    changes: changeLog,
    unresolved,
    writeErrors,
  };

  const outDir = path.resolve(__dirname, '..', 'audit_logs');
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `integrity_backfill_${fileTimestamp()}.json`);
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf8');

  console.log(JSON.stringify({
    ok: writeErrors.length === 0,
    reportPath: outPath,
    mode: report.meta.mode,
    summary: report.summary,
  }, null, 2));
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        mode: APPLY_WRITES ? 'confirm-write' : 'dry-run',
        error: err?.message || String(err),
        stack: err?.stack || null,
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
