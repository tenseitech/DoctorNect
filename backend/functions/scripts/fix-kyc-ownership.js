/**
 * Backfills missing users/{uid} docs for provider KYC ownership.
 *
 * Default is dry-run. Pass --apply to write changes.
 *
 * Usage (from functions/):
 *   set GOOGLE_APPLICATION_CREDENTIALS=...
 *   node scripts/fix-kyc-ownership.js
 *   node scripts/fix-kyc-ownership.js --apply
 *
 * Optional env:
 *   FIREBASE_PROJECT_ID (default: medibond-45fad)
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'medibond-45fad';
const APPLY = process.argv.includes('--apply');

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();
const auth = getAuth();

const ROLE_CONFIGS = [
  {
    collection: 'doctors',
    role: 'doctor',
    displayNameFields: ['name'],
  },
  {
    collection: 'medical_stores',
    role: 'medicalStore',
    displayNameFields: ['storeName', 'name'],
  },
  {
    collection: 'labs',
    role: 'lab',
    displayNameFields: ['labName', 'name'],
  },
];

function pickDisplayName(data, fields) {
  for (const field of fields) {
    const value = String(data[field] || '').trim();
    if (value) return value;
  }
  return null;
}

function pickMobile(data) {
  return String(data.mobile || data.phone || data.phoneNumber || '').trim() || null;
}

function pickEmail(roleData, authUser) {
  const fromRole = String(roleData.email || '').trim();
  if (fromRole) return fromRole.toLowerCase();
  const fromAuth = String(authUser?.email || '').trim();
  if (fromAuth) return fromAuth.toLowerCase();
  return null;
}

async function buildUsersBackfill({ profileId, ownerUid, role, displayNameFields, roleData }) {
  let authUser = null;
  try {
    authUser = await auth.getUser(ownerUid);
  } catch (err) {
    return {
      ok: false,
      reason: `Auth user missing (${err.code || err.message})`,
    };
  }

  const payload = {
    role,
    profileId,
    displayName: pickDisplayName(roleData, displayNameFields)
      || authUser.displayName
      || role,
    email: pickEmail(roleData, authUser),
    verified: roleData.verified === true,
    updatedAt: FieldValue.serverTimestamp(),
  };

  const mobile = pickMobile(roleData) || String(authUser.phoneNumber || '').trim() || null;
  if (mobile) payload.mobile = mobile;
  if (roleData.verified === true) {
    payload.status = roleData.status || 'active';
  }

  return { ok: true, payload, authEmail: authUser.email || null };
}

async function scanCollection(config) {
  const snap = await db.collection(config.collection).get();
  const actions = [];
  const manual = [];

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const ownerUid = String(data.ownerUid || '').trim();
    const profileId = doc.id;

    if (!ownerUid) {
      manual.push({
        collection: config.collection,
        profileId,
        issue: 'missing ownerUid on role doc',
        verified: data.verified ?? null,
        email: data.email ?? null,
      });
      continue;
    }

    const userSnap = await db.collection('users').doc(ownerUid).get();
    if (userSnap.exists) {
      const profileIdOnUser = String(userSnap.data()?.profileId || '').trim();
      if (profileIdOnUser && profileIdOnUser !== profileId) {
        manual.push({
          collection: config.collection,
          profileId,
          ownerUid,
          issue: `users/${ownerUid}.profileId=${profileIdOnUser} != ${profileId}`,
        });
      }
      continue;
    }

    const backfill = await buildUsersBackfill({
      profileId,
      ownerUid,
      role: config.role,
      displayNameFields: config.displayNameFields,
      roleData: data,
    });

    if (!backfill.ok) {
      manual.push({
        collection: config.collection,
        profileId,
        ownerUid,
        issue: backfill.reason,
      });
      continue;
    }

    actions.push({
      collection: config.collection,
      profileId,
      ownerUid,
      usersPath: `users/${ownerUid}`,
      payload: backfill.payload,
      authEmail: backfill.authEmail,
    });
  }

  return { ...config, actions, manual };
}

async function main() {
  console.log(`KYC ownership fix — project ${PROJECT_ID}`);
  console.log(`Mode: ${APPLY ? 'APPLY (writes enabled)' : 'DRY-RUN (pass --apply to write)'}\n`);

  const reports = [];
  for (const config of ROLE_CONFIGS) {
    reports.push(await scanCollection(config));
  }

  let backfillCount = 0;
  let manualCount = 0;

  for (const report of reports) {
    console.log(`=== ${report.collection} ===`);
    console.log(`Backfill candidates: ${report.actions.length}`);
    console.log(`Manual review: ${report.manual.length}`);

    for (const action of report.actions) {
      backfillCount += 1;
      console.log(`\n  [backfill] ${report.collection}/${action.profileId}`);
      console.log(`    -> ${action.usersPath}`);
      console.log(`    auth email: ${action.authEmail ?? '(none)'}`);
      const printable = { ...action.payload, updatedAt: '<serverTimestamp>' };
      console.log(`    payload: ${JSON.stringify(printable, null, 2).split('\n').join('\n    ')}`);

      if (APPLY) {
        await db.collection('users').doc(action.ownerUid).set(action.payload, { merge: true });
        console.log('    status: WRITTEN');
      } else {
        console.log('    status: dry-run (no write)');
      }
    }

    for (const item of report.manual) {
      manualCount += 1;
      console.log(`\n  [manual] ${item.collection}/${item.profileId}: ${item.issue}`);
      if (item.ownerUid) console.log(`    ownerUid: ${item.ownerUid}`);
      if (item.email != null) console.log(`    email: ${item.email ?? '(none)'}`);
      if (item.verified != null) console.log(`    verified: ${item.verified}`);
    }

    console.log('');
  }

  console.log('---');
  console.log(`Backfills: ${backfillCount}${APPLY ? ' written' : ' planned'}`);
  console.log(`Manual review items: ${manualCount}`);
  console.log('Ambulances: skipped (authUid-only ownership; users doc not required).');

  if (manualCount > 0) {
    console.log('\nResolve manual items before tightening pharmacy/lab storage rules.');
    if (!APPLY && backfillCount > 0) {
      console.log('Re-run with --apply after reviewing the planned backfills above.');
    }
    process.exitCode = manualCount > 0 ? 2 : 0;
    return;
  }

  if (backfillCount > 0 && !APPLY) {
    console.log('\nRe-run with --apply to write backfills, then audit again:');
    console.log('  node scripts/fix-kyc-ownership.js --apply');
    console.log('  node scripts/audit-kyc-owneruid.js');
    process.exitCode = 0;
    return;
  }

  console.log('\nDone. Re-run audit: node scripts/audit-kyc-owneruid.js');
}

main().catch((err) => {
  console.error('Fix script failed:', err.message || err);
  process.exitCode = 1;
});
