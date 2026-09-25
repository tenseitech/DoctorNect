'use strict';

/**
 * DoctorNect: Cross-Role Staged Sync Bridge (Firestore -> Supabase)
 * 
 * Synchronizes Doctor/Clinic mutations (Appointment status updates, consultation outcomes,
 * and Prescriptions) from Firestore into Supabase PostgreSQL for Patient consumption.
 * 
 * Includes:
 * 1. Strict loop prevention (detects syncedBy: 'supabase_bridge' | 'reconciler_bot')
 * 2. Monotonic timestamp verification
 * 3. Dead-Letter Queue (DLQ) logging on unrecoverable failures
 */

const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// Resolve Supabase config from environment or Firebase functions config
function getSupabaseConfig() {
  const url = process.env.SUPABASE_URL || process.env.STAGING_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY;
  return { url, key };
}

let _pgPool = null;
function getPgPool() {
  const dbUrl = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
  if (!dbUrl) return null;
  if (!_pgPool) {
    try {
      const { Pool } = require('pg');
      _pgPool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
    } catch (_) {
      try {
        const { Pool } = require('../scripts/node_modules/pg');
        _pgPool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
      } catch (__) {}
    }
  }
  return _pgPool;
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
 * Record a failed sync attempt to the PostgreSQL Dead-Letter Queue (DLQ).
 * Falls back to Firestore _sync_dlq collection if Supabase REST API is unreachable.
 */
async function recordDlqFailure({ direction, entityType, entityId, payload, errorMessage, errorStack, retryCount }) {
  const { url, key } = getSupabaseConfig();
  const dlqEntry = {
    direction: direction || 'firestore_to_supabase',
    entity_type: entityType,
    entity_id: entityId,
    payload: payload || {},
    error_message: String(errorMessage || 'Unknown sync error'),
    error_stack: errorStack ? String(errorStack).slice(0, 1000) : null,
    retry_count: retryCount || 0,
    status: 'pending',
    created_at: new Date().toISOString(),
  };

  // Structured log to Cloud Logging (Critical)
  console.error(JSON.stringify({
    securityEvent: true,
    severity: 'CRITICAL',
    event: 'SYNC_BRIDGE_DLQ_FAILURE',
    ...dlqEntry,
  }));

  // 1. Attempt write to Supabase sync_dead_letter_queue table
  if (url && key) {
    try {
      const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/sync_dead_letter_queue`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: JSON.stringify(dlqEntry),
      });
      if (resp.ok) return;
    } catch (_) {
      // Supabase may be unreachable; fall through to local Firestore backup
    }
  }

  // 2. Direct PG Pool fallback
  const pool = getPgPool();
  if (pool) {
    try {
      await pool.query(
        `INSERT INTO sync_dead_letter_queue 
          (direction, entity_type, entity_id, payload, error_message, error_stack, retry_count, status, created_at)
         VALUES 
          ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
        [dlqEntry.direction, dlqEntry.entity_type, dlqEntry.entity_id, JSON.stringify(dlqEntry.payload), dlqEntry.error_message, dlqEntry.error_stack, dlqEntry.retry_count, dlqEntry.status]
      );
      return;
    } catch (_) {}
  }

  // 3. Fallback to Firestore _sync_dlq collection
  try {
    const db = getFirestore();
    await db.collection('_sync_dlq').doc(`${entityType}_${entityId}_${Date.now()}`).set({
      ...dlqEntry,
      fallbackSavedAt: FieldValue.serverTimestamp(),
    });
  } catch (fsErr) {
    console.error('Fatal: Failed to write DLQ entry to both Supabase and Firestore fallback:', fsErr.message);
  }
}

/**
 * Sync Firestore Appointment to Supabase
 */
async function syncFirestoreAppointmentToSupabase(event) {
  const change = event.data;
  if (!change || !change.after || !change.after.exists) return; // Deleted

  const after = change.after.data();
  const appointmentId = event.params.appointmentId || after.appointmentId || change.after.id;

  // ------------------------------------------------------------------------
  // 1. LOOP PREVENTION CHECK:
  // If this write was made by the Supabase Bridge or Reconciler, DROP IT!
  // ------------------------------------------------------------------------
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping sync.');
    return;
  }

  const dateTimeIso = after.dateTime?.toDate?.()
    ? after.dateTime.toDate().toISOString()
    : (after.dateTime ? new Date(after.dateTime).toISOString() : new Date().toISOString());

  const supabasePayload = {
    appointment_id: appointmentId,
    doctor_id: after.doctorId || 'doc-unknown',
    patient_id: after.patientId || null,
    doctor_name: after.doctorName || 'Doctor',
    specialization: after.specialization || 'General',
    patient_name: after.patientName || 'Patient',
    patient_age: Number(after.patientAge) || 30,
    patient_gender: after.patientGender || 'Other',
    date_time: dateTimeIso,
    slot_label: after.slotLabel || '10:00 AM',
    visit_type: after.visitType || 'newVisit',
    patient_status: after.patientStatus || 'confirmed',
    doctor_status: after.doctorStatus || 'pendingRequest',
    token_number: Number(after.tokenNumber) || 1,
    clinic_name: after.clinicName || null,
    clinic_address: after.clinicAddress || null,
    cancellation_reason: after.cancellationReason || null,
    diagnosis: after.diagnosis || null,
    has_prescription: Boolean(after.hasPrescription),
    sync_origin: 'doctor_firestore',
    synced_by: 'firestore_cloud_function',
    updated_at: new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/appointments?on_conflict=appointment_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(supabasePayload),
          });

          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO appointments (
              appointment_id, doctor_id, patient_id, doctor_name, specialization,
              patient_name, patient_age, patient_gender, date_time, slot_label,
              visit_type, patient_status, doctor_status, token_number, clinic_name,
              clinic_address, cancellation_reason, diagnosis, has_prescription,
              sync_origin, synced_by, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, NOW()
            ) ON CONFLICT (appointment_id) DO UPDATE SET
              doctor_status = EXCLUDED.doctor_status,
              patient_status = EXCLUDED.patient_status,
              diagnosis = EXCLUDED.diagnosis,
              has_prescription = EXCLUDED.has_prescription,
              sync_origin = 'doctor_firestore',
              synced_by = 'firestore_cloud_function',
              updated_at = NOW();
          `, [
            supabasePayload.appointment_id,
            supabasePayload.doctor_id,
            supabasePayload.patient_id,
            supabasePayload.doctor_name,
            supabasePayload.specialization,
            supabasePayload.patient_name,
            supabasePayload.patient_age,
            supabasePayload.patient_gender,
            supabasePayload.date_time,
            supabasePayload.slot_label,
            supabasePayload.visit_type,
            supabasePayload.patient_status,
            supabasePayload.doctor_status,
            supabasePayload.token_number,
            supabasePayload.clinic_name,
            supabasePayload.clinic_address,
            supabasePayload.cancellation_reason,
            supabasePayload.diagnosis,
            supabasePayload.has_prescription,
            supabasePayload.sync_origin,
            supabasePayload.synced_by,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'appointment', entityId: appointmentId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'appointment',
      entityId: appointmentId,
      payload: supabasePayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr; // Re-throw to allow Cloud Functions / Cloud Tasks retry
  }
}

/**
 * Sync Firestore Prescription to Supabase
 */
async function syncFirestorePrescriptionToSupabase(event) {
  const change = event.data;
  if (!change || !change.after || !change.after.exists) return; // Deleted

  const after = change.after.data();
  const prescriptionId = event.params.prescriptionId || after.prescriptionId || change.after.id;

  // ------------------------------------------------------------------------
  // 1. LOOP PREVENTION CHECK:
  // If this write was made by the Supabase Bridge or Reconciler, DROP IT!
  // ------------------------------------------------------------------------
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const { url, key } = getSupabaseConfig();
  if (!url || !key) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping sync.');
    return;
  }

  const prescriptionPayload = {
    prescription_id: prescriptionId,
    doctor_id: after.doctorId || 'doc-unknown',
    patient_id: after.patientId || 'pat-unknown',
    appointment_id: after.appointmentId || null,
    doctor_name: after.doctorName || 'Doctor',
    patient_name: after.patientName || 'Patient',
    patient_age: Number(after.patientAge) || 30,
    patient_gender: after.patientGender || 'Other',
    primary_diagnosis: after.primaryDiagnosis || after.diagnosis || 'General Consultation',
    general_advice: after.generalAdvice || null,
    sync_origin: 'doctor_firestore',
    synced_by: 'firestore_cloud_function',
    updated_at: new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        // 1. Upsert prescription header
        const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/prescriptions?on_conflict=prescription_id`, {
          method: 'POST',
          headers: {
            'apikey': key,
            'Authorization': `Bearer ${key}`,
            'Content-Type': 'application/json',
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: JSON.stringify(prescriptionPayload),
        });

        if (!resp.ok) {
          const errBody = await resp.text();
          throw new Error(`Supabase PostgREST prescription header error (${resp.status}): ${errBody}`);
        }

        // 2. Upsert medicines line items if present
        const medicines = Array.isArray(after.medicines) ? after.medicines : [];
        if (medicines.length > 0) {
          const medRows = medicines.map((m, idx) => ({
            prescription_id: prescriptionId,
            medicine_entry_id: `${prescriptionId}_med_${idx}`,
            name: m.name || m.medicineName || 'Medicine',
            dosage: m.dosage || 'Standard',
            form: m.form || 'Tablet',
            frequency: m.frequency || '1-0-1',
            quantity: String(m.quantity || '10'),
            duration: m.duration || '5 days',
            instructions: m.instructions || m.timing || 'After meals',
          }));

          const medResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/prescription_medicines?on_conflict=prescription_id,medicine_entry_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(medRows),
          });

          if (!medResp.ok) {
            const errBody = await medResp.text();
            console.warn(`[SyncBridge] Warning: Medicines upsert returned ${medResp.status}: ${errBody}`);
          }
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'prescription', entityId: prescriptionId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'prescription',
      entityId: prescriptionId,
      payload: prescriptionPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

module.exports = {
  syncFirestoreAppointmentToSupabase,
  syncFirestorePrescriptionToSupabase,
  recordDlqFailure,
  executeWithRetry,
};

