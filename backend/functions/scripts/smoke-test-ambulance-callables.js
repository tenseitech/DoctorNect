/**
 * Isolated smoke tests for submitAmbulanceRating + resyncAmbulanceAuthUid.
 * Uses ONLY smoke-test-* documents — never touches live driver/booking data.
 *
 * Prerequisites:
 *   1. gcloud auth application-default login   (or GOOGLE_APPLICATION_CREDENTIALS)
 *   2. Functions deployed to medibond-45fad (Step 1 complete)
 *   3. Firebase Auth → Anonymous sign-in enabled (already used by ambulance app)
 *
 * Usage (from functions/ directory):
 *   node scripts/smoke-test-ambulance-callables.js --setup
 *   node scripts/smoke-test-ambulance-callables.js --test-resync
 *   node scripts/smoke-test-ambulance-callables.js --test-rating
 *   node scripts/smoke-test-ambulance-callables.js --cleanup
 *
 * Optional env:
 *   FIREBASE_WEB_API_KEY  (defaults to project web key from firebase_options.dart)
 */
const crypto = require('crypto');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = 'medibond-45fad';
const REGION = 'us-central1';
const WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY;

const TEST = {
  driverDocId: 'smoke-test-amb-driver',
  driverUsername: 'smoketest01',
  driverPin: '654321',
  staleAuthUid: 'smoke-test-stale-auth-uid',
  patientProfileId: 'smoke-test-patient-profile',
  broadcastId: 'smoke-test-broadcast-001',
  requestId: 'smoke-test-request-001',
};

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

function hashPin(pin) {
  return crypto.createHash('sha256').update(String(pin).trim()).digest('hex');
}

/** Real anonymous Firebase Auth session — same path the ambulance app uses. */
async function signInAnonymously() {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_API_KEY}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(
      `Anonymous sign-in failed: ${JSON.stringify(body)}. `
      + 'Enable Anonymous auth in Firebase Console → Authentication → Sign-in method.',
    );
  }
  return { idToken: body.idToken, uid: body.localId };
}

async function callCallable(functionName, idToken, data) {
  const url = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${functionName}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ data }),
  });

  const body = await response.json();
  return { status: response.status, body };
}

async function setupFixtures() {
  const db = getFirestore();
  const pinHash = hashPin(TEST.driverPin);

  console.log('Creating smoke-test fixtures (safe to delete later with --cleanup)...');

  await db.collection('ambulances').doc(TEST.driverDocId).set({
    serviceName: 'Smoke Test Ambulance',
    driverName: 'Smoke Test Driver',
    ownerName: 'Smoke Test Owner',
    phone: '9999999999',
    vehicleNumber: 'SMOKE-001',
    ambulanceType: 'bls',
    username: TEST.driverUsername,
    city: 'Smoke City',
    isAvailable: true,
    ratingCount: 0,
    totalRating: 0,
    authUid: TEST.staleAuthUid,
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.collection('ambulances').doc(TEST.driverDocId)
    .collection('private').doc('settings').set({ pin: pinHash });

  await db.collection('ambulance_broadcasts').doc(TEST.broadcastId).set({
    broadcastId: TEST.broadcastId,
    patientId: TEST.patientProfileId,
    pickupLocation: 'Smoke Test Pickup',
    dropLocation: 'Smoke Test Drop',
    pickupArea: 'smoke test pickup',
    status: 'completed',
    acceptedDriverId: TEST.driverDocId,
    completedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.collection('ambulance_requests').doc(TEST.requestId).set({
    broadcastId: TEST.broadcastId,
    driverId: TEST.driverDocId,
    patientId: TEST.patientProfileId,
    pickupLocation: 'Smoke Test Pickup',
    dropLocation: 'Smoke Test Drop',
    status: 'completed',
    completedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  });

  console.log('Setup complete.');
  console.log(`  ambulances/${TEST.driverDocId}`);
  console.log(`  ambulance_broadcasts/${TEST.broadcastId}`);
}

async function testResync() {
  const db = getFirestore();

  console.log('\n=== resyncAmbulanceAuthUid ===');
  const { idToken, uid } = await signInAnonymously();
  console.log('Anonymous test uid:', uid);

  const { status, body } = await callCallable('resyncAmbulanceAuthUid', idToken, {
    username: TEST.driverUsername,
    pin: TEST.driverPin,
  });

  console.log('HTTP status:', status);
  console.log('Response:', JSON.stringify(body, null, 2));

  const snap = await db.collection('ambulances').doc(TEST.driverDocId).get();
  console.log('Firestore authUid now:', snap.data()?.authUid);
  console.log('Expected authUid:   ', uid);
}

async function ensureSmokeTestBookerProfile(db, uid) {
  await db.collection('users').doc(uid).set({
    role: 'patient',
    profileId: TEST.patientProfileId,
    displayName: 'Smoke Test Patient',
    email: 'smoke-test@example.com',
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function testRating() {
  const db = getFirestore();

  console.log('\n=== submitAmbulanceRating ===');
  const { idToken, uid } = await signInAnonymously();
  console.log('Anonymous booker uid:', uid);
  await ensureSmokeTestBookerProfile(db, uid);

  const { status, body } = await callCallable('submitAmbulanceRating', idToken, {
    broadcastId: TEST.broadcastId,
    ambulanceId: TEST.driverDocId,
    stars: 5,
    review: 'Smoke test rating',
  });

  console.log('HTTP status:', status);
  console.log('Response:', JSON.stringify(body, null, 2));

  const ambSnap = await db.collection('ambulances').doc(TEST.driverDocId).get();
  const broadcastSnap = await db.collection('ambulance_broadcasts').doc(TEST.broadcastId).get();
  const requestSnap = await db.collection('ambulance_requests').doc(TEST.requestId).get();

  console.log('Ambulance aggregates:', {
    ratingCount: ambSnap.data()?.ratingCount,
    totalRating: ambSnap.data()?.totalRating,
  });
  console.log('Broadcast rating:', {
    rating: broadcastSnap.data()?.rating,
    review: broadcastSnap.data()?.review,
    ratedAt: broadcastSnap.data()?.ratedAt,
  });
  console.log('Request rating:', {
    rating: requestSnap.data()?.rating,
    review: requestSnap.data()?.review,
  });

  return idToken;
}

async function testRatingDuplicate(idToken) {
  console.log('\n=== submitAmbulanceRating (duplicate check) ===');
  const { status, body } = await callCallable('submitAmbulanceRating', idToken, {
    broadcastId: TEST.broadcastId,
    ambulanceId: TEST.driverDocId,
    stars: 4,
  });
  console.log('HTTP status:', status);
  console.log('Response:', JSON.stringify(body, null, 2));
}

async function cleanupFixtures() {
  const db = getFirestore();

  console.log('Deleting smoke-test fixtures...');
  await db.recursiveDelete(db.collection('ambulances').doc(TEST.driverDocId));
  await db.collection('ambulance_broadcasts').doc(TEST.broadcastId).delete();
  await db.collection('ambulance_requests').doc(TEST.requestId).delete();

  const usersSnap = await db.collection('users')
    .where('profileId', '==', TEST.patientProfileId)
    .get();
  for (const doc of usersSnap.docs) {
    await doc.ref.delete();
  }

  console.log('Cleanup complete.');
}

async function main() {
  const args = new Set(process.argv.slice(2));
  if (args.size === 0) {
    console.log('Pass --setup, --test-resync, --test-rating, and/or --cleanup');
    process.exit(1);
  }

  if (args.has('--setup')) await setupFixtures();
  if (args.has('--test-resync')) await testResync();
  if (args.has('--test-rating')) {
    const idToken = await testRating();
    await testRatingDuplicate(idToken);
  }
  if (args.has('--cleanup')) await cleanupFixtures();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
