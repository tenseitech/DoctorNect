/**
 * DoctorNect: Cross-System Parity Auditor & Reconciler
 * 
 * Verifies and ensures data consistency between Supabase PostgreSQL
 * and Firebase Firestore during the staged transition window.
 * 
 * Usage:
 *   node scripts/check_sync_parity.js --audit
 *   node scripts/check_sync_parity.js --reconcile
 *   node scripts/check_sync_parity.js --audit --collection-prefix="test_rollback_"
 */

require('./load_env').loadEnv();

const admin = require('firebase-admin');
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const IS_RECONCILE = args.includes('--reconcile');
const prefixArg = args.find(a => a.startsWith('--collection-prefix='));
const PREFIX = prefixArg ? prefixArg.split('=')[1] : '';

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  const saCandidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(process.cwd(), 'service-account.json'),
  ];
  const saPath = saCandidates.find(p => p && fs.existsSync(p));
  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad',
    });
  } else {
    admin.initializeApp({ projectId: 'medibond-45fad' });
  }
}
const firestore = admin.firestore();

const connectionString = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL;
if (!connectionString) {
  console.error('ERROR: Database connection string not found.');
  process.exit(1);
}

const pgClient = new Client({
  connectionString,
  ssl: { rejectUnauthorized: false },
});

async function auditAppointments() {
  console.log(`\n--- [1/3] Auditing Appointments Parity (Firestore: ${PREFIX}appointments vs Postgres: appointments) ---`);
  const pgRes = await pgClient.query(`SELECT appointment_id, doctor_id, patient_id, doctor_status, patient_status, updated_at FROM appointments;`);
  const pgMap = new Map();
  for (const r of pgRes.rows) {
    pgMap.set(r.appointment_id, r);
  }

  const fsSnap = await firestore.collection(`${PREFIX}appointments`).get();
  const fsMap = new Map();
  for (const doc of fsSnap.docs) {
    fsMap.set(doc.id, doc.data());
  }

  const inPgNotFs = [];
  const inFsNotPg = [];
  const mismatched = [];

  for (const [id, pgRow] of pgMap.entries()) {
    if (!fsMap.has(id)) {
      inPgNotFs.push(id);
    } else {
      const fsDoc = fsMap.get(id);
      if (fsDoc.doctorStatus !== pgRow.doctor_status || fsDoc.patientStatus !== pgRow.patient_status) {
        mismatched.push({
          id,
          pgDoctorStatus: pgRow.doctor_status,
          fsDoctorStatus: fsDoc.doctorStatus,
          pgPatientStatus: pgRow.patient_status,
          fsPatientStatus: fsDoc.patientStatus,
        });
      }
    }
  }

  for (const [id] of fsMap.entries()) {
    if (!pgMap.has(id)) {
      inFsNotPg.push(id);
    }
  }

  console.log(`Total Postgres Rows: ${pgMap.size} | Total Firestore Docs: ${fsMap.size}`);
  console.log(`Missing in Firestore: ${inPgNotFs.length} | Missing in Postgres: ${inFsNotPg.length} | Status Mismatches: ${mismatched.length}`);

  if (IS_RECONCILE) {
    console.log('-> Executing Automated Reconciliation for Appointments...');
    // A. Reconcile records missing in Firestore (Patient booking is SoR in Postgres)
    for (const id of inPgNotFs) {
      const row = pgMap.get(id);
      await firestore.collection(`${PREFIX}appointments`).doc(id).set({
        appointmentId: id,
        doctorId: row.doctor_id,
        patientId: row.patient_id,
        doctorStatus: row.doctor_status,
        patientStatus: row.patient_status,
        syncedBy: 'reconciler_bot', // Loop prevention
        reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      console.log(`  [Reconciled -> Firestore] appointment ${id}`);
    }

    // B. Reconcile records missing in Postgres (Doctor appointment is SoR in Firestore)
    for (const id of inFsNotPg) {
      const doc = fsMap.get(id);
      await pgClient.query(`
        INSERT INTO appointments (
          appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name,
          patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status,
          sync_origin, synced_by, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, 30, 'Other', NOW(), '10:00 AM', 'newVisit', $7, $8,
          'reconciler_bot', 'reconciler_bot', NOW()
        ) ON CONFLICT (appointment_id) DO UPDATE SET doctor_status = EXCLUDED.doctor_status;
      `, [id, doc.doctorId || 'doc-unknown', doc.patientId || null, doc.doctorName || 'Doctor', doc.specialization || 'General', doc.patientName || 'Patient', doc.patientStatus || 'confirmed', doc.doctorStatus || 'pendingRequest']);
      console.log(`  [Reconciled -> Postgres] appointment ${id}`);
    }
  }

  return { pgCount: pgMap.size, fsCount: fsMap.size, inPgNotFs: inPgNotFs.length, inFsNotPg: inFsNotPg.length, mismatched: mismatched.length };
}

async function auditPrescriptions() {
  console.log(`\n--- [2/3] Auditing Prescriptions Parity (Firestore: ${PREFIX}prescriptions vs Postgres: prescriptions) ---`);
  const pgRes = await pgClient.query(`SELECT prescription_id, doctor_id, patient_id, appointment_id FROM prescriptions;`);
  const pgMap = new Map();
  for (const r of pgRes.rows) {
    pgMap.set(r.prescription_id, r);
  }

  const fsSnap = await firestore.collection(`${PREFIX}prescriptions`).get();
  const fsMap = new Map();
  for (const doc of fsSnap.docs) {
    fsMap.set(doc.id, doc.data());
  }

  const inFsNotPg = [];
  for (const [id] of fsMap.entries()) {
    if (!pgMap.has(id)) inFsNotPg.push(id);
  }

  console.log(`Total Postgres Rows: ${pgMap.size} | Total Firestore Docs: ${fsMap.size}`);
  console.log(`Prescriptions in Firestore missing in Postgres: ${inFsNotPg.length}`);

  if (IS_RECONCILE && inFsNotPg.length > 0) {
    console.log('-> Executing Automated Reconciliation for Prescriptions (Firestore is SoR for Prescriptions)...');
    for (const id of inFsNotPg) {
      const doc = fsMap.get(id);
      await pgClient.query(`
        INSERT INTO prescriptions (
          prescription_id, doctor_id, patient_id, appointment_id, doctor_name, patient_name,
          patient_age, patient_gender, primary_diagnosis, sync_origin, synced_by, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, 30, 'Other', $7, 'reconciler_bot', 'reconciler_bot', NOW()
        ) ON CONFLICT (prescription_id) DO NOTHING;
      `, [id, doc.doctorId || 'doc-unknown', doc.patientId || 'pat-unknown', doc.appointmentId || null, doc.doctorName || 'Doctor', doc.patientName || 'Patient', doc.primaryDiagnosis || 'Consultation']);
      console.log(`  [Reconciled -> Postgres] prescription ${id}`);
    }
  }

  return { pgCount: pgMap.size, fsCount: fsMap.size, inFsNotPg: inFsNotPg.length };
}

async function checkDlqHealth() {
  console.log(`\n--- [3/3] Checking Dead-Letter Queue (DLQ) Health ---`);
  const dlqRes = await pgClient.query(`
    SELECT status, count(*) AS count 
    FROM sync_dead_letter_queue 
    GROUP BY status;
  `);

  console.log('Dead-Letter Queue status breakdown:');
  if (dlqRes.rows.length === 0) {
    console.log('  PASS: DLQ is completely empty (0 failures recorded).');
  } else {
    console.table(dlqRes.rows);
  }
}

async function main() {
  console.log('================================================================');
  console.log(`DOCTORNECT CROSS-SYSTEM PARITY AUDITOR & RECONCILER`);
  console.log(`MODE: ${IS_RECONCILE ? '*** AUTOMATED RECONCILIATION ***' : 'AUDIT ONLY (Read-Only Parity Check)'}`);
  if (PREFIX) console.log(`FIRESTORE PREFIX: ${PREFIX}`);
  console.log('================================================================');

  try {
    await pgClient.connect();
    const aptResult = await auditAppointments();
    const rxResult = await auditPrescriptions();
    await checkDlqHealth();

    console.log('\n================================================================');
    console.log('AUDIT SUMMARY');
    console.log('================================================================');
    console.table([
      { Entity: 'Appointments', PostgresCount: aptResult.pgCount, FirestoreCount: aptResult.fsCount, Divergence: aptResult.inPgNotFs + aptResult.inFsNotPg + aptResult.mismatched },
      { Entity: 'Prescriptions', PostgresCount: rxResult.pgCount, FirestoreCount: rxResult.fsCount, Divergence: rxResult.inFsNotPg },
    ]);
  } catch (err) {
    console.error('Parity auditor failed:', err);
    process.exit(1);
  } finally {
    await pgClient.end().catch(() => {});
  }
}

main();
