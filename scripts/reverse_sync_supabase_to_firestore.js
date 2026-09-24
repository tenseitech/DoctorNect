/**
 * DoctorNect: Emergency Reverse-Sync Script (Supabase → Firestore)
 * 
 * Safety Tool for Phase 7 Rollback:
 * If an emergency rollback is triggered after cutover, this script copies any
 * new appointments, prescriptions, reviews, and user profile updates created
 * in Supabase during the live window back into Firestore before re-enabling
 * legacy client writes.
 * 
 * Usage:
 *   node scripts/reverse_sync_supabase_to_firestore.js --dry-run --since="2026-09-23T00:00:00Z"
 *   node scripts/reverse_sync_supabase_to_firestore.js --live --since="2026-09-23T00:00:00Z"
 *   node scripts/reverse_sync_supabase_to_firestore.js --live --collection-prefix="test_rollback_"
 */

require('./load_env').loadEnv();

const admin = require('firebase-admin');
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const IS_DRY_RUN = !args.includes('--live');
const sinceArg = args.find(a => a.startsWith('--since='));
const SINCE_TIMESTAMP = sinceArg 
  ? new Date(sinceArg.split('=')[1]).toISOString()
  : new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

// Prefix for test collections during rollback dry-runs (keeps live collections completely untouched)
const prefixArg = args.find(a => a.startsWith('--collection-prefix='));
const COLLECTION_PREFIX = prefixArg 
  ? prefixArg.split('=')[1]
  : (process.env.FIRESTORE_TEST_COLLECTION_PREFIX || '');

function col(name) {
  return `${COLLECTION_PREFIX}${name}`;
}

console.log('================================================================');
console.log('DOCTORNECT EMERGENCY REVERSE-SYNC: SUPABASE -> FIRESTORE');
console.log(`MODE: ${IS_DRY_RUN ? 'DRY-RUN (Simulation only)' : '*** LIVE REVERSE SYNC ***'}`);
console.log(`FILTER: Records created/updated since ${SINCE_TIMESTAMP}`);
if (COLLECTION_PREFIX) {
  console.log(`SAFETY PREFIX: Target collections prefixed with "${COLLECTION_PREFIX}"`);
}
console.log('================================================================\n');

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  const candidateSaPaths = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(__dirname, 'serviceAccountKey.json'),
    path.join(process.cwd(), 'service-account.json'),
    path.join(process.cwd(), 'scripts', 'service-account.json'),
  ];
  const saPath = candidateSaPaths.find(p => p && fs.existsSync(p));
  if (saPath) {
    const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
    });
  } else {
    admin.initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
    });
  }
}
const firestore = admin.firestore();

// Supabase PostgreSQL Client
const connectionString = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
if (!connectionString) {
  console.error('FATAL: Database connection string not found.');
  console.error('Please configure STAGING_SUPABASE_DB_URL in .env.migration (recommended) or set DATABASE_URL.');
  process.exit(1);
}

const pgClient = new Client({
  connectionString,
  ssl: { rejectUnauthorized: false },
});

async function reverseSyncAppointments() {
  console.log(`\n[1/4] Checking newly created/updated appointments in Supabase (target: ${col('appointments')})...`);
  const res = await pgClient.query(
    `SELECT * FROM appointments WHERE created_at >= $1 OR updated_at >= $1`,
    [SINCE_TIMESTAMP]
  );

  console.log(`Found ${res.rows.length} appointments to reverse-sync.`);
  let synced = 0;

  for (const row of res.rows) {
    const docRef = firestore.collection(col('appointments')).doc(row.appointment_id);
    const firestoreData = {
      appointmentId: row.appointment_id,
      patientId: row.patient_id,
      patientName: row.patient_name,
      patientAge: row.patient_age,
      patientGender: row.patient_gender,
      contactNumber: row.contact_number,
      doctorId: row.doctor_id,
      doctorName: row.doctor_name,
      doctorSpecialization: row.specialization,
      clinicName: row.clinic_name || null,
      clinicAddress: row.clinic_address || null,
      dateTime: row.date_time ? admin.firestore.Timestamp.fromDate(new Date(row.date_time)) : null,
      slotLabel: row.slot_label,
      tokenNumber: row.token_number || 0,
      visitType: row.visit_type,
      patientStatus: row.patient_status,
      doctorStatus: row.doctor_status,
      diagnosis: row.diagnosis || null,
      hasPrescription: Boolean(row.has_prescription),
      hasReport: Boolean(row.has_report),
      hasReview: Boolean(row.has_review),
      chiefComplaints: row.chief_complaints || [],
      symptoms: row.symptoms || [],
      clinicalNotes: row.clinical_notes || null,
      source: row.source || 'app',
      createdAt: row.created_at ? admin.firestore.Timestamp.fromDate(new Date(row.created_at)) : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
    };

    if (IS_DRY_RUN) {
      console.log(`  [DRY-RUN] Would sync appointment ${row.appointment_id} (${row.patient_name} -> Dr. ${row.doctor_name})`);
    } else {
      await docRef.set(firestoreData, { merge: true });
      synced++;
    }
  }

  console.log(`Finished appointments sync: ${IS_DRY_RUN ? 'Simulated' : synced + ' synced'}.`);
  return res.rows.length;
}

async function reverseSyncPrescriptions() {
  console.log(`\n[2/4] Checking newly created/updated prescriptions in Supabase (target: ${col('prescriptions')})...`);
  const res = await pgClient.query(
    `SELECT * FROM prescriptions WHERE created_at >= $1 OR updated_at >= $1`,
    [SINCE_TIMESTAMP]
  );

  console.log(`Found ${res.rows.length} prescriptions to reverse-sync.`);
  let synced = 0;

  for (const row of res.rows) {
    const medRes = await pgClient.query(
      `SELECT * FROM prescription_medicines WHERE prescription_id = $1 ORDER BY id ASC`,
      [row.prescription_id]
    );

    const medicines = medRes.rows.map(m => ({
      entryIndex: m.medicine_entry_id,
      name: m.name,
      dosage: m.dosage,
      form: m.form,
      frequency: m.frequency,
      quantity: m.quantity,
      duration: m.duration,
      instructions: m.instructions || '',
      specialInstructions: m.special_instructions || '',
      isSos: Boolean(m.is_sos),
      substituteAllowed: Boolean(m.substitute_allowed),
    }));

    const docRef = firestore.collection(col('prescriptions')).doc(row.prescription_id);
    const firestoreData = {
      prescriptionId: row.prescription_id,
      appointmentId: row.appointment_id || null,
      patientId: row.patient_id,
      doctorId: row.doctor_id,
      doctorName: row.doctor_name,
      patientName: row.patient_name,
      patientAge: row.patient_age,
      patientGender: row.patient_gender,
      primaryDiagnosis: row.primary_diagnosis || '',
      secondaryDiagnosis: row.secondary_diagnosis || '',
      chiefComplaint: row.chief_complaint || '',
      symptoms: row.symptoms || '',
      medicines: medicines,
      dietAdvice: row.diet_advice || '',
      generalAdvice: row.general_advice || '',
      followUpNote: row.follow_up_note || '',
      nextVisit: row.next_visit ? admin.firestore.Timestamp.fromDate(new Date(row.next_visit)) : null,
      createdAt: row.created_at ? admin.firestore.Timestamp.fromDate(new Date(row.created_at)) : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
    };

    if (IS_DRY_RUN) {
      console.log(`  [DRY-RUN] Would sync prescription ${row.prescription_id} with ${medicines.length} medicines`);
    } else {
      await docRef.set(firestoreData, { merge: true });
      synced++;
    }
  }

  console.log(`Finished prescriptions sync: ${IS_DRY_RUN ? 'Simulated' : synced + ' synced'}.`);
  return res.rows.length;
}

async function reverseSyncReviews() {
  console.log(`\n[3/4] Checking newly created reviews in Supabase (target: ${col('reviews')})...`);
  const res = await pgClient.query(
    `SELECT * FROM reviews WHERE created_at >= $1 OR updated_at >= $1`,
    [SINCE_TIMESTAMP]
  );

  console.log(`Found ${res.rows.length} reviews to reverse-sync.`);
  let synced = 0;

  for (const row of res.rows) {
    const docRef = firestore.collection(col('reviews')).doc(row.review_id);
    const firestoreData = {
      reviewId: row.review_id,
      doctorId: row.doctor_id,
      patientId: row.patient_id,
      appointmentId: row.appointment_id || null,
      patientName: row.patient_name,
      rating: Number(row.rating),
      comment: row.comment,
      doctorReply: row.doctor_reply || null,
      helpfulCount: Number(row.helpful_count || 0),
      createdAt: row.created_at ? admin.firestore.Timestamp.fromDate(new Date(row.created_at)) : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
    };

    if (IS_DRY_RUN) {
      console.log(`  [DRY-RUN] Would sync review ${row.review_id} (Rating: ${row.rating})`);
    } else {
      await docRef.set(firestoreData, { merge: true });
      synced++;
    }
  }

  console.log(`Finished reviews sync: ${IS_DRY_RUN ? 'Simulated' : synced + ' synced'}.`);
  return res.rows.length;
}

async function reverseSyncUsers() {
  console.log(`\n[4/4] Checking newly created/updated users and role profiles in Supabase...`);
  const res = await pgClient.query(
    `SELECT * FROM users WHERE created_at >= $1 OR updated_at >= $1`,
    [SINCE_TIMESTAMP]
  );

  console.log(`Found ${res.rows.length} users to reverse-sync.`);
  let synced = 0;

  for (const row of res.rows) {
    const firestoreUid = row.uid || row.id;
    const docRef = firestore.collection(col('users')).doc(firestoreUid);
    const firestoreData = {
      uid: firestoreUid,
      role: row.role,
      profileId: row.profile_id,
      displayName: row.display_name,
      email: row.email,
      mobile: row.mobile,
      verified: Boolean(row.verified),
      profileCompleted: Boolean(row.profile_completed),
      status: row.status,
      createdAt: row.created_at ? admin.firestore.Timestamp.fromDate(new Date(row.created_at)) : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
    };

    if (IS_DRY_RUN) {
      console.log(`  [DRY-RUN] Would sync user ${firestoreUid} (${row.display_name}, Role: ${row.role})`);
    } else {
      await docRef.set(firestoreData, { merge: true });
      synced++;
    }
  }

  console.log(`Finished users sync: ${IS_DRY_RUN ? 'Simulated' : synced + ' synced'}.`);
  return res.rows.length;
}

async function runReverseSync() {
  const startTime = Date.now();
  try {
    await pgClient.connect();
    console.log('Connected to Supabase PostgreSQL database successfully.');

    const aptCount = await reverseSyncAppointments();
    const rxCount = await reverseSyncPrescriptions();
    const revCount = await reverseSyncReviews();
    const usrCount = await reverseSyncUsers();

    const elapsedSec = ((Date.now() - startTime) / 1000).toFixed(2);

    console.log('\n================================================================');
    console.log(`REVERSE SYNC SUMMARY: Completed in ${elapsedSec}s.`);
    console.log(`Total Records: ${aptCount} appointments, ${rxCount} prescriptions, ${revCount} reviews, ${usrCount} users.`);
    if (IS_DRY_RUN) {
      console.log('DRY-RUN simulation finished. Pass --live to write to Firestore.');
    } else {
      console.log(`LIVE sync successfully written to Firestore collections (Prefix: "${COLLECTION_PREFIX || '(none)'}").`);
    }
    console.log('================================================================');
  } catch (err) {
    console.error('Fatal error during reverse sync:', err);
    process.exit(1);
  } finally {
    await pgClient.end().catch(() => {});
  }
}

runReverseSync();
