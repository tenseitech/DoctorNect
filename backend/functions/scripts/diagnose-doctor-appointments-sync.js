/**
 * Diagnose doctor appointment listener/fetch path (hypotheses #2 and #3).
 *
 * Runs the SAME Firestore query as AppointmentRepository._doctorAppointmentsQuery
 * using a real doctor Firebase Auth session (respects security rules).
 *
 * Usage (from functions/):
 *   set DOCTOR_EMAIL=you@example.com
 *   set DOCTOR_PASSWORD=yourpassword
 *   node scripts/diagnose-doctor-appointments-sync.js
 *
 * Optional:
 *   DOCTOR_ID=d123...           — override profileId (default: users/{uid}.profileId)
 *   FIREBASE_WEB_API_KEY=...    — defaults to project web key
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const PROJECT_ID = 'medibond-45fad';
const WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY;
const DOCTOR_EMAIL = process.env.DOCTOR_EMAIL || '';
const DOCTOR_PASSWORD = process.env.DOCTOR_PASSWORD || '';
const DOCTOR_ID_OVERRIDE = process.env.DOCTOR_ID || '';

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });

async function signInWithPassword(email, password) {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`Doctor sign-in failed: ${JSON.stringify(body)}`);
  }
  return { idToken: body.idToken, uid: body.localId, email: body.email };
}

async function runStructuredQuery(idToken, doctorId) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 365);

  const structuredQuery = {
    structuredQuery: {
      from: [{ collectionId: 'appointments' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            {
              fieldFilter: {
                field: { fieldPath: 'doctorId' },
                op: 'EQUAL',
                value: { stringValue: doctorId },
              },
            },
            {
              fieldFilter: {
                field: { fieldPath: 'dateTime' },
                op: 'GREATER_THAN_OR_EQUAL',
                value: { timestampValue: cutoff.toISOString() },
              },
            },
          ],
        },
      },
      orderBy: [{ field: { fieldPath: 'dateTime' }, direction: 'DESCENDING' }],
      limit: 200,
    },
  };

  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(structuredQuery),
  });

  const body = await response.json();
  return { status: response.status, body };
}

async function adminProbeLatestAppointment() {
  const db = getFirestore();
  const snap = await db.collection('appointments').orderBy('dateTime', 'desc').limit(3).get();
  console.log('\n[Admin probe] Latest appointment docs (no auth rules):');
  if (snap.empty) {
    console.log('  (no appointments in collection)');
    return null;
  }
  for (const doc of snap.docs) {
    const d = doc.data();
    console.log(`  ${doc.id}: doctorId=${d.doctorId} dateTime=${d.dateTime?.toDate?.() ?? d.dateTime}`);
  }
  return snap.docs[0].data().doctorId;
}

async function adminRunSameQuery(doctorId) {
  const db = getFirestore();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 365);
  try {
    const snap = await db.collection('appointments')
      .where('doctorId', '==', doctorId)
      .where('dateTime', '>=', Timestamp.fromDate(cutoff))
      .orderBy('dateTime', 'desc')
      .limit(200)
      .get();
    console.log(`\n[Admin query] doctorId=${doctorId} → ${snap.size} doc(s) (index OK at admin level)`);
    return snap.size;
  } catch (e) {
    console.error(`\n[Admin query] FAILED for doctorId=${doctorId}:`, e.message || e);
    if (String(e.message || e).includes('index')) {
      console.error('  ^^^ INDEX ERROR — this would break both listener and fetch');
    }
    return -1;
  }
}

async function main() {
  console.log('=== Doctor appointment sync diagnostic ===');
  console.log(`Project: ${PROJECT_ID}`);

  const latestDoctorId = await adminProbeLatestAppointment();
  if (latestDoctorId) {
    await adminRunSameQuery(latestDoctorId);
  }

  if (!DOCTOR_EMAIL || !DOCTOR_PASSWORD) {
    console.log('\n[Client auth test] SKIPPED — set DOCTOR_EMAIL and DOCTOR_PASSWORD env vars');
    console.log('  Example: DOCTOR_EMAIL=doc@test.com DOCTOR_PASSWORD=secret node scripts/diagnose-doctor-appointments-sync.js');
    return;
  }

  console.log('\n[Client auth test] Signing in as doctor...');
  const auth = await signInWithPassword(DOCTOR_EMAIL, DOCTOR_PASSWORD);
  console.log(`  uid=${auth.uid} email=${auth.email}`);

  const db = getFirestore();
  const userDoc = await db.collection('users').doc(auth.uid).get();
  const profileId = DOCTOR_ID_OVERRIDE || userDoc.data()?.profileId || '';
  console.log(`  users/${auth.uid}.profileId = ${profileId}`);
  console.log(`  (DoctorSession.loggedInDoctorId would be: ${profileId})`);

  console.log('\n[Client query] Running structured query with doctor idToken (respects rules)...');
  const result = await runStructuredQuery(auth.idToken, profileId);
  console.log(`  HTTP ${result.status}`);

  if (Array.isArray(result.body)) {
    const docs = result.body.filter((row) => row.document);
    console.log(`  Documents returned: ${docs.length}`);
    for (const row of docs.slice(0, 5)) {
      const name = row.document.name.split('/').pop();
      const fields = row.document.fields || {};
      const docDoctorId = fields.doctorId?.stringValue ?? '?';
      const docDate = fields.dateTime?.timestampValue ?? '?';
      console.log(`    ${name}: doctorId=${docDoctorId} dateTime=${docDate}`);
    }
    if (docs.length > 5) console.log(`    ... and ${docs.length - 5} more`);
  } else {
    console.log('  Response:', JSON.stringify(result.body, null, 2));
    const err = result.body?.error;
    if (err) {
      console.error(`\n  ERROR code=${err.status} message=${err.message}`);
      if (err.message?.includes('index') || err.status === 'FAILED_PRECONDITION') {
        console.error('  ^^^ INDEX / failed-precondition — explains Test 1 + Test 2 failure');
      }
      if (err.message?.includes('PERMISSION_DENIED') || err.status === 'PERMISSION_DENIED') {
        console.error('  ^^^ PERMISSION_DENIED — rules blocking doctor read');
      }
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
