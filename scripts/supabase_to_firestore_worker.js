/**
 * DoctorNect: Supabase -> Firestore Sync Bridge Worker
 * 
 * Synchronizes Patient-authored records (Appointments, Patients, Reviews)
 * from Supabase PostgreSQL to Firestore so that Doctors and Clinics
 * (who remain on Firebase) can see them in real time (< 1.5s).
 * 
 * Features:
 * - Loop prevention: Ignores records with sync_origin = 'doctor_firestore' or 'reconciler_bot'
 * - Dead-Letter Queue (DLQ): Logs exhausted failures to sync_dead_letter_queue
 * - Can run as a webhook handler or a polling daemon during the staged cutover window
 */

require('./load_env').loadEnv();

const admin = require('firebase-admin');
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

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

let pgConnected = false;
let pgConnecting = null;
async function ensurePgConnected() {
  if (pgConnected) return;
  if (!pgConnecting) {
    pgConnecting = pgClient.connect().then(() => {
      pgConnected = true;
      pgConnecting = null;
    }).catch(err => {
      pgConnecting = null;
      throw err;
    });
  }
  await pgConnecting;
}

/**
 * Execute an async operation with exponential backoff retry
 */
async function executeWithRetry(operationFn, { maxRetries = 3, baseDelayMs = 200, context = {} } = {}) {
  let attempt = 0;
  while (true) {
    try {
      return await operationFn(attempt);
    } catch (err) {
      attempt++;
      if (attempt > maxRetries) {
        console.error(`[RetryExhausted] Failed after ${maxRetries} retries for ${context.entityType || 'entity'} ID: ${context.entityId || 'unknown'}: ${err.message}`);
        const exhaustedErr = new Error(`Exhausted ${maxRetries} retries: ${err.message}`);
        exhaustedErr.originalError = err;
        exhaustedErr.retryCount = maxRetries;
        throw exhaustedErr;
      }
      const delayMs = baseDelayMs * Math.pow(2, attempt - 1);
      console.warn(`[SyncRetry] Attempt ${attempt}/${maxRetries} failed: ${err.message}. Retrying in ${delayMs}ms...`);
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

/**
 * Record failure to sync_dead_letter_queue
 */
async function recordDlqFailure({ entityType, entityId, payload, errorMessage, errorStack, retryCount = 0 }) {
  try {
    await ensurePgConnected();
    await pgClient.query(
      `INSERT INTO sync_dead_letter_queue 
        (direction, entity_type, entity_id, payload, error_message, error_stack, retry_count, status, created_at)
       VALUES 
        ('supabase_to_firestore', $1, $2, $3, $4, $5, $6, 'pending', NOW())`,
      [entityType, entityId, JSON.stringify(payload), String(errorMessage), errorStack ? String(errorStack).slice(0, 1000) : null, retryCount]
    );
    console.error(`[DLQ] Logged failure for ${entityType} ID: ${entityId} (retries: ${retryCount}) to sync_dead_letter_queue`);
  } catch (dlqErr) {
    console.error('[DLQ] Failed to write to sync_dead_letter_queue:', dlqErr.message);
  }
}

/**
 * Sync an individual Supabase appointment to Firestore
 */
async function syncAppointmentToFirestore(row, collectionPrefix = '') {
  // Loop prevention
  if (row.sync_origin === 'doctor_firestore' || row.sync_origin === 'reconciler_bot' || row.synced_by === 'firestore_cloud_function') {
    return { skipped: true, reason: 'loop_prevented' };
  }

  const firestoreData = {
    id: row.appointment_id,
    appointmentId: row.appointment_id,
    doctorId: row.doctor_id,
    patientId: row.patient_id,
    doctorName: row.doctor_name,
    specialization: row.specialization,
    patientName: row.patient_name,
    patientAge: row.patient_age,
    patientGender: row.patient_gender,
    dateTime: row.date_time ? admin.firestore.Timestamp.fromDate(new Date(row.date_time)) : admin.firestore.FieldValue.serverTimestamp(),
    slotLabel: row.slot_label,
    tokenNumber: row.token_number,
    visitType: row.visit_type,
    patientStatus: row.patient_status,
    doctorStatus: row.doctor_status,
    clinicName: row.clinic_name,
    clinicAddress: row.clinic_address,
    cancellationReason: row.cancellation_reason,
    diagnosis: row.diagnosis,
    hasPrescription: Boolean(row.has_prescription),
    // CRITICAL MARKER for Firestore triggers to prevent echo loop:
    syncedBy: 'supabase_bridge',
    syncOrigin: 'patient_supabase',
    lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
  };

  const targetCollection = `${collectionPrefix}appointments`;
  try {
    await executeWithRetry(
      async () => {
        await firestore.collection(targetCollection).doc(row.appointment_id).set(firestoreData, { merge: true });
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'appointment', entityId: row.appointment_id } }
    );
    return { success: true };
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      entityType: 'appointment',
      entityId: row.appointment_id,
      payload: firestoreData,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Sync an individual Supabase review to Firestore
 */
async function syncReviewToFirestore(row, collectionPrefix = '') {
  if (row.sync_origin === 'reconciler_bot') {
    return { skipped: true, reason: 'loop_prevented' };
  }

  const firestoreData = {
    id: row.review_id,
    reviewId: row.review_id,
    patientId: row.patient_id,
    doctorId: row.doctor_id,
    appointmentId: row.appointment_id,
    patientName: row.patient_name,
    rating: row.rating,
    comment: row.comment,
    syncedBy: 'supabase_bridge',
    syncOrigin: 'patient_supabase',
    lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: row.created_at ? admin.firestore.Timestamp.fromDate(new Date(row.created_at)) : admin.firestore.FieldValue.serverTimestamp(),
  };

  const targetCollection = `${collectionPrefix}reviews`;
  try {
    await executeWithRetry(
      async () => {
        await firestore.collection(targetCollection).doc(row.review_id).set(firestoreData, { merge: true });
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'review', entityId: row.review_id } }
    );
    return { success: true };
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      entityType: 'review',
      entityId: row.review_id,
      payload: firestoreData,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Process a batch of recently modified Supabase records
 */
async function processDeltaSync({ since, collectionPrefix = '' } = {}) {
  const cutoff = since || new Date(Date.now() - 5 * 60 * 1000).toISOString();
  
  // 1. Fetch appointments created/updated by patients
  const apts = await pgClient.query(`
    SELECT * FROM appointments 
    WHERE updated_at >= $1 
      AND (sync_origin IS NULL OR sync_origin = 'patient_supabase')
      AND (synced_by IS NULL OR synced_by != 'firestore_cloud_function');
  `, [cutoff]);

  let aptSynced = 0;
  for (const row of apts.rows) {
    const res = await syncAppointmentToFirestore(row, collectionPrefix);
    if (res.success) aptSynced++;
  }

  // 2. Fetch reviews
  const revs = await pgClient.query(`
    SELECT * FROM reviews 
    WHERE updated_at >= $1 
      AND (sync_origin IS NULL OR sync_origin = 'patient_supabase');
  `, [cutoff]);

  let revSynced = 0;
  for (const row of revs.rows) {
    const res = await syncReviewToFirestore(row, collectionPrefix);
    if (res.success) revSynced++;
  }

  // 3. Fetch patients
  const pats = await pgClient.query(`
    SELECT * FROM patients 
    WHERE updated_at >= $1 
      AND (sync_origin IS NULL OR sync_origin = 'patient_supabase')
      AND (synced_by IS NULL OR synced_by != 'firestore_cloud_function');
  `, [cutoff]);

  let patSynced = 0;
  for (const row of pats.rows) {
    const res = await syncPatientToFirestore(row, collectionPrefix);
    if (res.success) patSynced++;
  }

  return { aptSynced, revSynced, patSynced };
}

/**
 * Sync an individual Supabase patient to Firestore
 */
async function syncPatientToFirestore(row, collectionPrefix = '') {
  if (row.sync_origin === 'reconciler_bot' || row.synced_by === 'firestore_cloud_function') {
    return { skipped: true, reason: 'loop_prevented' };
  }

  const firestoreData = {
    id: row.patient_id,
    patientId: row.patient_id,
    name: row.name,
    email: row.email,
    mobile: row.mobile,
    age: row.age,
    gender: row.gender,
    bloodGroup: row.blood_group,
    height: row.height ? Number(row.height) || 0 : 0,
    weight: row.weight ? Number(row.weight) || 0 : 0,
    photoUrl: row.photo_url,
    photoURL: row.photo_url,
    address: row.address,
    addressLine1: row.address,
    city: row.city,
    state: row.state,
    pincode: row.pincode,
    country: row.country || 'India',
    conditions: row.conditions || [],
    allergies: row.allergies || [],
    shareRecordsWithDoctors: Boolean(row.share_records_with_doctors),
    syncedBy: 'supabase_bridge',
    syncOrigin: 'patient_supabase',
    lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: row.updated_at ? admin.firestore.Timestamp.fromDate(new Date(row.updated_at)) : admin.firestore.FieldValue.serverTimestamp(),
  };

  const targetCollection = (!collectionPrefix || collectionPrefix === 'patients') ? 'patients' : `${collectionPrefix}patients`;
  try {
    await executeWithRetry(
      async () => {
        await firestore.collection(targetCollection).doc(row.patient_id).set(firestoreData, { merge: true });
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'patient', entityId: row.patient_id } }
    );
    return { success: true };
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      entityType: 'patient',
      entityId: row.patient_id,
      payload: firestoreData,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

module.exports = {
  syncAppointmentToFirestore,
  syncReviewToFirestore,
  syncPatientToFirestore,
  processDeltaSync,
  recordDlqFailure,
  pgClient,
};

if (require.main === module) {
  (async () => {
    await pgClient.connect();
    console.log('Connected to Staging Postgres for sync bridge worker.');
    const result = await processDeltaSync({ since: '2000-01-01T00:00:00Z', collectionPrefix: 'test_rollback_' });
    console.log('Worker cycle complete:', result);
    await pgClient.end();
  })().catch(err => {
    console.error('Worker failed:', err);
    process.exit(1);
  });
}
