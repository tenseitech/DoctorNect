/**
 * Prints full fields for docs flagged by audit-kyc-owneruid.js
 *
 * Usage:
 *   set GOOGLE_APPLICATION_CREDENTIALS=...
 *   node scripts/inspect-kyc-ownership-issues.js
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'medibond-45fad';

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();

const TARGETS = [
  { collection: 'doctors', id: 'd1783603413832', ownerField: 'ownerUid' },
  { collection: 'doctors', id: 'd1784184964835', ownerField: 'ownerUid' },
  { collection: 'medical_stores', id: 'ms1784803179652', ownerField: 'ownerUid' },
  { collection: 'labs', id: 'l1784186386697', ownerField: 'ownerUid' },
];

async function findUsersByProfileId(profileId) {
  const snap = await db.collection('users').where('profileId', '==', profileId).limit(5).get();
  return snap.docs.map((doc) => ({ uid: doc.id, ...doc.data() }));
}

async function inspectTarget({ collection, id, ownerField }) {
  const snap = await db.collection(collection).doc(id).get();
  console.log(`\n=== ${collection}/${id} ===`);
  if (!snap.exists) {
    console.log('Document missing.');
    return;
  }

  const data = snap.data() || {};
  const ownerValue = String(data[ownerField] || '').trim();
  console.log(JSON.stringify({
    ownerField,
    ownerValue: ownerValue || null,
    email: data.email ?? null,
    mobile: data.mobile ?? data.phone ?? data.phoneNumber ?? null,
    verified: data.verified ?? null,
    name: data.name ?? data.storeName ?? data.labName ?? data.serviceName ?? null,
    authUid: data.authUid ?? null,
  }, null, 2));

  if (ownerValue) {
    const userSnap = await db.collection('users').doc(ownerValue).get();
    console.log(`users/${ownerValue} exists: ${userSnap.exists}`);
    if (userSnap.exists) {
      console.log('users doc:', JSON.stringify(userSnap.data(), null, 2));
    }
  }

  const linkedUsers = await findUsersByProfileId(id);
  console.log(`users where profileId == ${id}: ${linkedUsers.length}`);
  for (const user of linkedUsers) {
    console.log(JSON.stringify({
      uid: user.uid,
      role: user.role ?? null,
      email: user.email ?? null,
      mobile: user.mobile ?? null,
      profileId: user.profileId ?? null,
    }, null, 2));
  }
}

async function main() {
  for (const target of TARGETS) {
    await inspectTarget(target);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
