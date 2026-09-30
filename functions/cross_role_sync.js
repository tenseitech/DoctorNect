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
const crypto = require('crypto');

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

/**
 * Helper: Convert list or string to array of clean strings
 */
function toStringArray(val, defaultArr = []) {
  if (Array.isArray(val)) {
    const cleaned = val.map(x => String(x || '').trim()).filter(Boolean);
    return cleaned.length > 0 ? cleaned : defaultArr;
  }
  if (typeof val === 'string' && val.trim().length > 0) {
    return [val.trim()];
  }
  return defaultArr;
}

/**
 * Helper: Convert Firestore Timestamp / Date / string / number to ISO string
 */
function toIsoTimestamp(val) {
  if (!val) return null;
  if (typeof val.toDate === 'function') {
    return val.toDate().toISOString();
  }
  if (val instanceof Date) {
    return isNaN(val.getTime()) ? null : val.toISOString();
  }
  if (typeof val === 'string' || typeof val === 'number') {
    const d = new Date(val);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

/**
 * Helper: Convert Timestamp / Date / string to YYYY-MM-DD date string
 */
function toDateString(val) {
  if (!val) return null;
  let d;
  if (typeof val.toDate === 'function') {
    d = val.toDate();
  } else if (typeof val === 'string') {
    const trimmed = val.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
    d = new Date(trimmed);
  } else if (val instanceof Date) {
    d = val;
  } else if (typeof val === 'number') {
    d = new Date(val);
  }
  if (!d || isNaN(d.getTime())) return null;
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Ensure parent doctor exists in Postgres before inserting child records
 * (avoids foreign key constraint violation on doctor_availability / doctor_blocked_dates / doctor_education)
 */
async function ensureDoctorExistsInPostgres(doctorId, { url, key, pool }) {
  if (!doctorId) return;

  // 1. Check if doctor already exists
  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctors?doctor_id=eq.${encodeURIComponent(doctorId)}&select=doctor_id`, {
        method: 'GET',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
        },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT doctor_id FROM doctors WHERE doctor_id = $1 LIMIT 1', [doctorId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  // 2. Doctor not in Postgres; check Firestore for existing doc data
  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('doctors').doc(doctorId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const placeholderDoctor = {
    doctor_id: doctorId,
    name: docData?.name || docData?.fullName || 'Doctor',
    email: (docData?.email || `${doctorId}@doctornect.com`).toLowerCase(),
    mobile: docData?.mobile || docData?.phone || '0000000000',
    specialization: docData?.specialization || 'General Physician',
    qualification: docData?.qualification || 'MBBS',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctors?on_conflict=doctor_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholderDoctor),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO doctors (doctor_id, name, email, mobile, specialization, qualification, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
        ON CONFLICT (doctor_id) DO NOTHING;
      `, [
        placeholderDoctor.doctor_id,
        placeholderDoctor.name,
        placeholderDoctor.email,
        placeholderDoctor.mobile,
        placeholderDoctor.specialization,
        placeholderDoctor.qualification,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent doctor ${doctorId} in Postgres: ${e.message}`);
  }
}

/**
 * Sync Doctor Education degrees to doctor_education table
 */
async function syncDoctorEducationToSupabase(doctorId, rawEducation, qualification, { url, key, pool } = {}, degrees) {
  const educationList = Array.isArray(rawEducation) ? rawEducation : [];
  let educationRows = educationList.map(item => ({
    doctor_id: doctorId,
    degree: String(item.degree || item.title || qualification || 'MBBS').slice(0, 128),
    college: item.college || item.university || item.institution || null,
    year: item.year ? parseInt(item.year, 10) || null : null,
  })).filter(e => e.degree);

  if (educationRows.length === 0 && Array.isArray(degrees) && degrees.length > 0) {
    educationRows = degrees.map(deg => ({
      doctor_id: doctorId,
      degree: String(deg).slice(0, 128),
      college: null,
      year: null,
    })).filter(e => e.degree);
  }

  if (educationRows.length === 0 && qualification) {
    educationRows = [{
      doctor_id: doctorId,
      degree: String(qualification).slice(0, 128),
      college: null,
      year: null,
    }];
  }

  if (url && key) {
    // 1. Delete existing education rows for this doctor
    await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_education?doctor_id=eq.${encodeURIComponent(doctorId)}`, {
      method: 'DELETE',
      headers: {
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        'Prefer': 'return=minimal',
      },
    });

    // 2. Insert new rows
    if (educationRows.length > 0) {
      const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_education`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: JSON.stringify(educationRows),
      });
      if (!resp.ok) {
        const errBody = await resp.text();
        console.warn(`[SyncBridge] Warning: doctor_education upsert returned ${resp.status}: ${errBody}`);
      }
    }
  } else if (pool) {
    await pool.query('DELETE FROM doctor_education WHERE doctor_id = $1', [doctorId]);
    for (const row of educationRows) {
      await pool.query(
        'INSERT INTO doctor_education (doctor_id, degree, college, year) VALUES ($1, $2, $3, $4)',
        [row.doctor_id, row.degree, row.college, row.year]
      );
    }
  }
}

/**
 * Sync Doctor Blocked Dates to doctor_blocked_dates table
 */
async function syncDoctorBlockedDatesToSupabase(doctorId, rawDates, { url, key, pool }) {
  const dateStrings = (rawDates || []).map(toDateString).filter(Boolean);
  const uniqueDates = Array.from(new Set(dateStrings));

  if (url && key) {
    // 1. Delete existing blocked dates for doctor
    await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_blocked_dates?doctor_id=eq.${encodeURIComponent(doctorId)}`, {
      method: 'DELETE',
      headers: {
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        'Prefer': 'return=minimal',
      },
    });

    // 2. Insert new blocked dates
    if (uniqueDates.length > 0) {
      const rows = uniqueDates.map(d => ({ doctor_id: doctorId, blocked_date: d }));
      const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_blocked_dates?on_conflict=doctor_id,blocked_date`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(rows),
      });
      if (!resp.ok) {
        const errBody = await resp.text();
        console.warn(`[SyncBridge] Warning: doctor_blocked_dates upsert returned ${resp.status}: ${errBody}`);
      }
    }
  } else if (pool) {
    await pool.query('DELETE FROM doctor_blocked_dates WHERE doctor_id = $1', [doctorId]);
    for (const d of uniqueDates) {
      await pool.query(
        'INSERT INTO doctor_blocked_dates (doctor_id, blocked_date) VALUES ($1, $2) ON CONFLICT (doctor_id, blocked_date) DO NOTHING',
        [doctorId, d]
      );
    }
  }
}

/**
 * Sync Firestore Doctor profile & credentials to Supabase
 */
async function syncFirestoreDoctorToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const doctorId = event.params?.doctorId || change.after?.id || change.before?.id;
  if (!doctorId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping doctor sync.');
    return;
  }

  // ------------------------------------------------------------------------
  // 1. HANDLE DOCUMENT DELETION (Soft-delete in Postgres)
  // ------------------------------------------------------------------------
  if (!change.after || !change.after.exists) {
    const nowIso = new Date().toISOString();
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctors?doctor_id=eq.${encodeURIComponent(doctorId)}`, {
              method: 'PATCH',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                deactivated: true,
                deactivated_at: nowIso,
                updated_at: nowIso,
              }),
            });
            if (!resp.ok && resp.status !== 404) {
              const errBody = await resp.text();
              throw new Error(`Supabase PostgREST doctor soft-delete error (${resp.status}): ${errBody}`);
            }
          } else if (pool) {
            await pool.query(
              `UPDATE doctors SET deactivated = true, deactivated_at = NOW(), updated_at = NOW() WHERE doctor_id = $1`,
              [doctorId]
            );
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor', entityId: doctorId, action: 'soft_delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'doctor',
        entityId: doctorId,
        payload: { doctor_id: doctorId, action: 'soft_delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // ------------------------------------------------------------------------
  // 2. LOOP PREVENTION CHECK:
  // If this write was made by the Supabase Bridge or Reconciler, DROP IT!
  // ------------------------------------------------------------------------
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorPayload = {
    doctor_id: doctorId,
    name: after.name || after.fullName || 'Doctor',
    email: (after.email || `${doctorId}@doctornect.com`).toLowerCase(),
    mobile: after.mobile || after.phone || '0000000000',
    specialization: after.specialization || (Array.isArray(after.specializations) && after.specializations.length > 0 ? after.specializations[0] : 'General Physician'),
    super_specialization: after.superSpecialization || null,
    qualification: after.qualification || (Array.isArray(after.degrees) && after.degrees.length > 0 ? after.degrees.join(', ') : 'MBBS'),
    experience_years: parseInt(after.experienceYears ?? after.yearsExperience ?? 1, 10) || 1,
    consultation_fee: parseFloat(after.consultationFee ?? 0.0) || 0.0,
    clinic_name: after.clinicName || null,
    area: after.area || null,
    city: after.city || 'Mumbai',
    state: after.state || 'Maharashtra',
    country: after.country || 'India',
    pincode: after.pincode || null,
    address_line1: after.addressLine1 || null,
    address_line2: after.addressLine2 || null,
    state_council: after.stateCouncil || null,
    council_number: after.councilNumber || null,
    certifications: toStringArray(after.certifications, []),
    past_workplaces: toStringArray(after.pastWorkplaces, []),
    memberships: toStringArray(after.memberships, []),
    awards: toStringArray(after.awards, []),
    publications: toStringArray(after.publications, []),
    about: after.about || null,
    languages: toStringArray(after.languages, ['English', 'Hindi']),
    photo_url: after.photoUrl || after.photoURL || null,
    maps_link: after.mapsLink || after.mapsUrl || null,
    landmark: after.landmark || null,
    rating: parseFloat(after.rating ?? 0.0) || 0.0,
    review_count: parseInt(after.reviewCount ?? 0, 10) || 0,
    profile_completed: Boolean(after.profileCompleted),
    verified: Boolean(after.verified),
    verified_at: toIsoTimestamp(after.verifiedAt),
    deactivated: Boolean(after.deactivated),
    deactivated_at: toIsoTimestamp(after.deactivatedAt),
    reactivate_before: toIsoTimestamp(after.reactivateBefore),
    reactivated_at: toIsoTimestamp(after.reactivatedAt),
    fcm_token: after.fcmToken || null,
    fcm_token_updated_at: toIsoTimestamp(after.fcmTokenUpdatedAt),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        // 1. Upsert Doctor Master record
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctors?on_conflict=doctor_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(doctorPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST doctor error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO doctors (
              doctor_id, name, email, mobile, specialization, super_specialization,
              qualification, experience_years, consultation_fee, clinic_name,
              area, city, state, country, pincode, address_line1, address_line2,
              state_council, council_number, certifications, past_workplaces,
              memberships, awards, publications, about, languages, photo_url,
              maps_link, landmark, rating, review_count, profile_completed,
              verified, verified_at, deactivated, deactivated_at, reactivate_before,
              reactivated_at, fcm_token, fcm_token_updated_at, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
              $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28,
              $29, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $40, $41, $42
            ) ON CONFLICT (doctor_id) DO UPDATE SET
              name = EXCLUDED.name,
              email = EXCLUDED.email,
              mobile = EXCLUDED.mobile,
              specialization = EXCLUDED.specialization,
              super_specialization = EXCLUDED.super_specialization,
              qualification = EXCLUDED.qualification,
              experience_years = EXCLUDED.experience_years,
              consultation_fee = EXCLUDED.consultation_fee,
              clinic_name = EXCLUDED.clinic_name,
              area = EXCLUDED.area,
              city = EXCLUDED.city,
              state = EXCLUDED.state,
              country = EXCLUDED.country,
              pincode = EXCLUDED.pincode,
              address_line1 = EXCLUDED.address_line1,
              address_line2 = EXCLUDED.address_line2,
              state_council = EXCLUDED.state_council,
              council_number = EXCLUDED.council_number,
              certifications = EXCLUDED.certifications,
              past_workplaces = EXCLUDED.past_workplaces,
              memberships = EXCLUDED.memberships,
              awards = EXCLUDED.awards,
              publications = EXCLUDED.publications,
              about = EXCLUDED.about,
              languages = EXCLUDED.languages,
              photo_url = EXCLUDED.photo_url,
              maps_link = EXCLUDED.maps_link,
              landmark = EXCLUDED.landmark,
              rating = EXCLUDED.rating,
              review_count = EXCLUDED.review_count,
              profile_completed = EXCLUDED.profile_completed,
              verified = EXCLUDED.verified,
              verified_at = EXCLUDED.verified_at,
              deactivated = EXCLUDED.deactivated,
              deactivated_at = EXCLUDED.deactivated_at,
              reactivate_before = EXCLUDED.reactivate_before,
              reactivated_at = EXCLUDED.reactivated_at,
              fcm_token = EXCLUDED.fcm_token,
              fcm_token_updated_at = EXCLUDED.fcm_token_updated_at,
              updated_at = NOW();
          `, [
            doctorPayload.doctor_id, doctorPayload.name, doctorPayload.email, doctorPayload.mobile,
            doctorPayload.specialization, doctorPayload.super_specialization, doctorPayload.qualification,
            doctorPayload.experience_years, doctorPayload.consultation_fee, doctorPayload.clinic_name,
            doctorPayload.area, doctorPayload.city, doctorPayload.state, doctorPayload.country,
            doctorPayload.pincode, doctorPayload.address_line1, doctorPayload.address_line2,
            doctorPayload.state_council, doctorPayload.council_number, doctorPayload.certifications,
            doctorPayload.past_workplaces, doctorPayload.memberships, doctorPayload.awards,
            doctorPayload.publications, doctorPayload.about, doctorPayload.languages,
            doctorPayload.photo_url, doctorPayload.maps_link, doctorPayload.landmark,
            doctorPayload.rating, doctorPayload.review_count, doctorPayload.profile_completed,
            doctorPayload.verified, doctorPayload.verified_at, doctorPayload.deactivated,
            doctorPayload.deactivated_at, doctorPayload.reactivate_before, doctorPayload.reactivated_at,
            doctorPayload.fcm_token, doctorPayload.fcm_token_updated_at, doctorPayload.created_at,
            doctorPayload.updated_at
          ]);
        }

        // 2. Sync Doctor Education
        await syncDoctorEducationToSupabase(doctorId, after.education, after.qualification, { url, key, pool }, after.degrees);
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor', entityId: doctorId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'doctor',
      entityId: doctorId,
      payload: doctorPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Sync Firestore Doctor Availability to Supabase
 */
async function syncFirestoreDoctorAvailabilityToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const doctorId = event.params?.doctorId || change.after?.id || change.before?.id;
  if (!doctorId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping doctor availability sync.');
    return;
  }

  // Handle deletion of availability doc
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_availability?doctor_id=eq.${encodeURIComponent(doctorId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_blocked_dates?doctor_id=eq.${encodeURIComponent(doctorId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM doctor_availability WHERE doctor_id = $1', [doctorId]);
            await pool.query('DELETE FROM doctor_blocked_dates WHERE doctor_id = $1', [doctorId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor_availability', entityId: doctorId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'doctor_availability',
        entityId: doctorId,
        payload: { doctor_id: doctorId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // ------------------------------------------------------------------------
  // LOOP PREVENTION CHECK:
  // ------------------------------------------------------------------------
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  // Ensure parent doctor exists to satisfy foreign key constraint
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });

  const availabilityPayload = {
    doctor_id: doctorId,
    working_days: toStringArray(after.workingDays, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']),
    morning_start: after.morningStart || '09:00 AM',
    morning_end: after.morningEnd || '01:00 PM',
    evening_enabled: after.eveningEnabled !== false,
    evening_start: after.eveningStart || '04:00 PM',
    evening_end: after.eveningEnd || '08:00 PM',
    slot_duration_mins: parseInt(after.slotDurationMins || 15, 10),
    max_patients_per_day: parseInt(after.maxPatientsPerDay || 20, 10),
    break_enabled: Boolean(after.breakEnabled),
    break_start: after.breakStart || '01:00 PM',
    break_end: after.breakEnd || '02:00 PM',
    leave_start: toIsoTimestamp(after.leaveStart),
    leave_end: toIsoTimestamp(after.leaveEnd),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_availability?on_conflict=doctor_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(availabilityPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST doctor_availability error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO doctor_availability (
              doctor_id, working_days, morning_start, morning_end, evening_enabled,
              evening_start, evening_end, slot_duration_mins, max_patients_per_day,
              break_enabled, break_start, break_end, leave_start, leave_end, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
            ) ON CONFLICT (doctor_id) DO UPDATE SET
              working_days = EXCLUDED.working_days,
              morning_start = EXCLUDED.morning_start,
              morning_end = EXCLUDED.morning_end,
              evening_enabled = EXCLUDED.evening_enabled,
              evening_start = EXCLUDED.evening_start,
              evening_end = EXCLUDED.evening_end,
              slot_duration_mins = EXCLUDED.slot_duration_mins,
              max_patients_per_day = EXCLUDED.max_patients_per_day,
              break_enabled = EXCLUDED.break_enabled,
              break_start = EXCLUDED.break_start,
              break_end = EXCLUDED.break_end,
              leave_start = EXCLUDED.leave_start,
              leave_end = EXCLUDED.leave_end,
              updated_at = EXCLUDED.updated_at;
          `, [
            availabilityPayload.doctor_id,
            availabilityPayload.working_days,
            availabilityPayload.morning_start,
            availabilityPayload.morning_end,
            availabilityPayload.evening_enabled,
            availabilityPayload.evening_start,
            availabilityPayload.evening_end,
            availabilityPayload.slot_duration_mins,
            availabilityPayload.max_patients_per_day,
            availabilityPayload.break_enabled,
            availabilityPayload.break_start,
            availabilityPayload.break_end,
            availabilityPayload.leave_start,
            availabilityPayload.leave_end,
            availabilityPayload.updated_at,
          ]);
        }

        // Sync blocked dates embedded in availability if present
        if (Array.isArray(after.blockedDates)) {
          await syncDoctorBlockedDatesToSupabase(doctorId, after.blockedDates, { url, key, pool });
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor_availability', entityId: doctorId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'doctor_availability',
      entityId: doctorId,
      payload: availabilityPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Sync Firestore Doctor Blocked Dates (standalone collection) to Supabase
 */
async function syncFirestoreDoctorBlockedDatesToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const docId = event.params?.docId || event.params?.doctorId || change.after?.id || change.before?.id;
  if (!docId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping doctor blocked dates sync.');
    return;
  }

  // Deletion of docId
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_blocked_dates?doctor_id=eq.${encodeURIComponent(docId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM doctor_blocked_dates WHERE doctor_id = $1', [docId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor_blocked_dates', entityId: docId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'doctor_blocked_dates',
        entityId: docId,
        payload: { doc_id: docId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // ------------------------------------------------------------------------
  // LOOP PREVENTION CHECK:
  // ------------------------------------------------------------------------
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorId = after.doctorId || docId;
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });

  try {
    await executeWithRetry(
      async () => {
        if (Array.isArray(after.blockedDates)) {
          await syncDoctorBlockedDatesToSupabase(doctorId, after.blockedDates, { url, key, pool });
        } else if (after.blockedDate || after.blocked_date || after.date) {
          const dateStr = toDateString(after.blockedDate || after.blocked_date || after.date);
          if (dateStr) {
            if (url && key) {
              const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/doctor_blocked_dates?on_conflict=doctor_id,blocked_date`, {
                method: 'POST',
                headers: {
                  'apikey': key,
                  'Authorization': `Bearer ${key}`,
                  'Content-Type': 'application/json',
                  'Prefer': 'resolution=merge-duplicates,return=minimal',
                },
                body: JSON.stringify([{ doctor_id: doctorId, blocked_date: dateStr }]),
              });
              if (!resp.ok) {
                const errBody = await resp.text();
                throw new Error(`Supabase PostgREST doctor_blocked_dates single date error (${resp.status}): ${errBody}`);
              }
            } else if (pool) {
              await pool.query(
                'INSERT INTO doctor_blocked_dates (doctor_id, blocked_date) VALUES ($1, $2) ON CONFLICT (doctor_id, blocked_date) DO NOTHING',
                [doctorId, dateStr]
              );
            }
          }
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'doctor_blocked_dates', entityId: doctorId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'doctor_blocked_dates',
      entityId: doctorId,
      payload: after,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Helper: Validate standard UUID string format (RFC 4122) for Postgres UUID columns.
 */
function toValidUuid(val) {
  if (typeof val !== 'string') return null;
  const trimmed = val.trim();
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(trimmed) ? trimmed : null;
}

/**
 * Ensure parent medical store exists in Postgres before inserting child records
 */
async function ensureMedicalStoreExistsInPostgres(storeId, fallbackData = {}, { url, key, pool }) {
  if (!storeId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/medical_stores?store_id=eq.${encodeURIComponent(storeId)}&select=store_id`, {
        method: 'GET',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
        },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT store_id FROM medical_stores WHERE store_id = $1 LIMIT 1', [storeId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('medical_stores').doc(storeId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const placeholderStore = {
    store_id: storeId,
    store_name: docData?.storeName || fallbackData.storeName || 'Medical Store',
    owner_name: docData?.ownerName || 'Owner',
    drug_license_number: docData?.drugLicenseNumber || docData?.licenseNumber || 'PENDING',
    phone: docData?.phone || '0000000000',
    email: (docData?.email || `${storeId}@doctornect.com`).toLowerCase(),
    city: docData?.city || 'Mumbai',
    state: docData?.state || 'Maharashtra',
    country: docData?.country || 'India',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/medical_stores?on_conflict=store_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholderStore),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO medical_stores (store_id, store_name, owner_name, drug_license_number, phone, email, city, state, country, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
        ON CONFLICT (store_id) DO NOTHING;
      `, [
        placeholderStore.store_id,
        placeholderStore.store_name,
        placeholderStore.owner_name,
        placeholderStore.drug_license_number,
        placeholderStore.phone,
        placeholderStore.email,
        placeholderStore.city,
        placeholderStore.state,
        placeholderStore.country,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent medical_store ${storeId} in Postgres: ${e.message}`);
  }
}

/**
 * Ensure parent lab exists in Postgres before inserting child records
 */
async function ensureLabExistsInPostgres(labId, fallbackData = {}, { url, key, pool }) {
  if (!labId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/labs?lab_id=eq.${encodeURIComponent(labId)}&select=lab_id`, {
        method: 'GET',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
        },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT lab_id FROM labs WHERE lab_id = $1 LIMIT 1', [labId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('labs').doc(labId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const placeholderLab = {
    lab_id: labId,
    lab_name: docData?.labName || fallbackData.labName || 'Diagnostic Lab',
    license_number: docData?.licenseNumber || 'PENDING',
    phone: docData?.phone || '0000000000',
    email: (docData?.email || `${labId}@doctornect.com`).toLowerCase(),
    city: docData?.city || 'Mumbai',
    state: docData?.state || 'Maharashtra',
    country: docData?.country || 'India',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/labs?on_conflict=lab_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholderLab),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO labs (lab_id, lab_name, license_number, phone, email, city, state, country, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
        ON CONFLICT (lab_id) DO NOTHING;
      `, [
        placeholderLab.lab_id,
        placeholderLab.lab_name,
        placeholderLab.license_number,
        placeholderLab.phone,
        placeholderLab.email,
        placeholderLab.city,
        placeholderLab.state,
        placeholderLab.country,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent lab ${labId} in Postgres: ${e.message}`);
  }
}

/**
 * Ensure parent patient exists in Postgres before inserting child records
 */
async function ensurePatientExistsInPostgres(patientId, fallbackData = {}, { url, key, pool }) {
  if (!patientId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/patients?patient_id=eq.${encodeURIComponent(patientId)}&select=patient_id`, {
        method: 'GET',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
        },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT patient_id FROM patients WHERE patient_id = $1 LIMIT 1', [patientId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('patients').doc(patientId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const genderVal = docData?.gender || fallbackData.patientGender;
  const validGender = ['Male', 'Female', 'Other'].includes(genderVal) ? genderVal : 'Other';

  const placeholderPatient = {
    patient_id: patientId,
    name: docData?.name || fallbackData.patientName || 'Patient',
    mobile: docData?.mobile || '0000000000',
    age: parseInt(docData?.age || fallbackData.patientAge || 30, 10) || 30,
    gender: validGender,
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/patients?on_conflict=patient_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholderPatient),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO patients (patient_id, name, mobile, age, gender, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
        ON CONFLICT (patient_id) DO NOTHING;
      `, [
        placeholderPatient.patient_id,
        placeholderPatient.name,
        placeholderPatient.mobile,
        placeholderPatient.age,
        placeholderPatient.gender,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent patient ${patientId} in Postgres: ${e.message}`);
  }
}

/**
 * Ensure parent prescription exists in Postgres before inserting delivery records
 */
async function ensurePrescriptionExistsInPostgres(prescriptionId, fallbackData = {}, { url, key, pool }) {
  if (!prescriptionId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/prescriptions?prescription_id=eq.${encodeURIComponent(prescriptionId)}&select=prescription_id`, {
        method: 'GET',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
        },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT prescription_id FROM prescriptions WHERE prescription_id = $1 LIMIT 1', [prescriptionId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('prescriptions').doc(prescriptionId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const doctorId = docData?.doctorId || fallbackData.doctorId || 'doc-unknown';
  const patientId = docData?.patientId || fallbackData.patientId || 'pat-unknown';

  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensurePatientExistsInPostgres(patientId, fallbackData, { url, key, pool });

  const placeholderPrescription = {
    prescription_id: prescriptionId,
    doctor_id: doctorId,
    patient_id: patientId,
    doctor_name: docData?.doctorName || fallbackData.doctorName || 'Doctor',
    patient_name: docData?.patientName || fallbackData.patientName || 'Patient',
    primary_diagnosis: docData?.primaryDiagnosis || 'General Consultation',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/prescriptions?on_conflict=prescription_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholderPrescription),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, doctor_name, patient_name, primary_diagnosis, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
        ON CONFLICT (prescription_id) DO NOTHING;
      `, [
        placeholderPrescription.prescription_id,
        placeholderPrescription.doctor_id,
        placeholderPrescription.patient_id,
        placeholderPrescription.doctor_name,
        placeholderPrescription.patient_name,
        placeholderPrescription.primary_diagnosis,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent prescription ${prescriptionId} in Postgres: ${e.message}`);
  }
}

/**
 * Sync Pharmacy Delivery child medicine items
 */
async function syncPharmacyDeliveryMedicinesToSupabase(deliveryId, rawMedicines, { url, key, pool }) {
  const medList = Array.isArray(rawMedicines) ? rawMedicines : [];
  const medicineRows = medList.map((m, idx) => ({
    delivery_id: deliveryId,
    medicine_entry_id: String(m.medicineEntryId || m.id || `${deliveryId}_med_${idx}`),
    availability: ['pending', 'available', 'outOfStock', 'substituted'].includes(m.availability) ? m.availability : 'pending',
    substitute_name: m.substituteName || null,
  }));

  if (url && key) {
    // 1. Delete existing delivery medicines
    await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_delivery_medicines?delivery_id=eq.${encodeURIComponent(deliveryId)}`, {
      method: 'DELETE',
      headers: {
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        'Prefer': 'return=minimal',
      },
    });

    // 2. Insert new delivery medicines
    if (medicineRows.length > 0) {
      const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_delivery_medicines`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: JSON.stringify(medicineRows),
      });
      if (!resp.ok) {
        const errBody = await resp.text();
        console.warn(`[SyncBridge] Warning: pharmacy_delivery_medicines insert returned ${resp.status}: ${errBody}`);
      }
    }
  } else if (pool) {
    await pool.query('DELETE FROM pharmacy_delivery_medicines WHERE delivery_id = $1', [deliveryId]);
    for (const row of medicineRows) {
      await pool.query(
        'INSERT INTO pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability, substitute_name) VALUES ($1, $2, $3, $4)',
        [row.delivery_id, row.medicine_entry_id, row.availability, row.substitute_name]
      );
    }
  }
}

/**
 * 1. Sync Firestore Medical Store to Supabase
 */
async function syncFirestoreMedicalStoreToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const storeId = event.params?.storeId || change.after?.id || change.before?.id;
  if (!storeId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping medical store sync.');
    return;
  }

  // Handle document deletion (Soft-delete in Postgres)
  if (!change.after || !change.after.exists) {
    const nowIso = new Date().toISOString();
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/medical_stores?store_id=eq.${encodeURIComponent(storeId)}`, {
              method: 'PATCH',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                deactivated: true,
                updated_at: nowIso,
              }),
            });
            if (!resp.ok && resp.status !== 404) {
              const errBody = await resp.text();
              throw new Error(`Supabase PostgREST medical store soft-delete error (${resp.status}): ${errBody}`);
            }
          } else if (pool) {
            await pool.query('UPDATE medical_stores SET deactivated = true, updated_at = NOW() WHERE store_id = $1', [storeId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'medical_store', entityId: storeId, action: 'soft_delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'medical_store',
        entityId: storeId,
        payload: { store_id: storeId, action: 'soft_delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  let addressLine1 = null;
  let addressLine2 = null;
  let city = 'Mumbai';
  let state = 'Maharashtra';
  let country = 'India';
  let pincode = null;

  if (after.address && typeof after.address === 'object') {
    addressLine1 = after.address.addressLine1 || after.addressLine1 || null;
    addressLine2 = after.address.addressLine2 || after.addressLine2 || null;
    city = after.address.city || after.city || 'Mumbai';
    state = after.address.state || after.state || 'Maharashtra';
    country = after.address.country || after.country || 'India';
    pincode = after.address.pinCode || after.address.pincode || after.pincode || null;
  } else {
    addressLine1 = after.addressLine1 || (typeof after.address === 'string' ? after.address : null);
    addressLine2 = after.addressLine2 || null;
    city = after.city || 'Mumbai';
    state = after.state || 'Maharashtra';
    country = after.country || 'India';
    pincode = after.pincode || null;
  }

  const storePayload = {
    store_id: storeId,
    owner_uid: toValidUuid(after.ownerUid),
    store_name: after.storeName || 'Medical Store',
    owner_name: after.ownerName || 'Owner',
    drug_license_number: after.drugLicenseNumber || after.licenseNumber || 'PENDING',
    phone: after.phone || '0000000000',
    email: (after.email || `${storeId}@doctornect.com`).toLowerCase(),
    gst_number: after.gstNumber || null,
    address_line1: addressLine1,
    address_line2: addressLine2,
    city: city,
    state: state,
    country: country,
    pincode: pincode,
    profile_completed: Boolean(after.profileCompleted),
    verified: Boolean(after.verified),
    verified_at: toIsoTimestamp(after.verifiedAt),
    deactivated: Boolean(after.deactivated),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/medical_stores?on_conflict=store_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(storePayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST medical store error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO medical_stores (
              store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email,
              gst_number, address_line1, address_line2, city, state, country, pincode,
              profile_completed, verified, verified_at, deactivated, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20
            ) ON CONFLICT (store_id) DO UPDATE SET
              store_name = EXCLUDED.store_name,
              owner_name = EXCLUDED.owner_name,
              drug_license_number = EXCLUDED.drug_license_number,
              phone = EXCLUDED.phone,
              email = EXCLUDED.email,
              gst_number = EXCLUDED.gst_number,
              address_line1 = EXCLUDED.address_line1,
              address_line2 = EXCLUDED.address_line2,
              city = EXCLUDED.city,
              state = EXCLUDED.state,
              country = EXCLUDED.country,
              pincode = EXCLUDED.pincode,
              profile_completed = EXCLUDED.profile_completed,
              verified = EXCLUDED.verified,
              verified_at = EXCLUDED.verified_at,
              deactivated = EXCLUDED.deactivated,
              updated_at = NOW();
          `, [
            storePayload.store_id, storePayload.owner_uid, storePayload.store_name,
            storePayload.owner_name, storePayload.drug_license_number, storePayload.phone,
            storePayload.email, storePayload.gst_number, storePayload.address_line1,
            storePayload.address_line2, storePayload.city, storePayload.state,
            storePayload.country, storePayload.pincode, storePayload.profile_completed,
            storePayload.verified, storePayload.verified_at, storePayload.deactivated,
            storePayload.created_at, storePayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'medical_store', entityId: storeId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'medical_store',
      entityId: storeId,
      payload: storePayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 2. Sync Firestore Pharmacy Connection to Supabase
 */
async function syncFirestorePharmacyConnectionToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const connectionId = event.params?.connectionId || change.after?.id || change.before?.id;
  if (!connectionId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping pharmacy connection sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_connections?connection_id=eq.${encodeURIComponent(connectionId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM pharmacy_connections WHERE connection_id = $1', [connectionId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'pharmacy_connection', entityId: connectionId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'pharmacy_connection',
        entityId: connectionId,
        payload: { connection_id: connectionId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorId = after.doctorId;
  const storeId = after.medicalStoreId || after.storeId;

  // Self-healing foreign keys
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensureMedicalStoreExistsInPostgres(storeId, { storeName: after.storeName }, { url, key, pool });

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'active', 'rejected', 'removed'].includes(rawStatus) ? rawStatus : 'pending';
  const rawReqBy = after.requestedBy || 'doctor';
  const requestedBy = ['doctor', 'store'].includes(rawReqBy) ? rawReqBy : 'doctor';

  const connectionPayload = {
    connection_id: connectionId,
    doctor_id: doctorId,
    medical_store_id: storeId,
    doctor_name: after.doctorName || 'Doctor',
    store_name: after.storeName || 'Medical Store',
    status: status,
    requested_by: requestedBy,
    requested_at: toIsoTimestamp(after.requestedAt) || new Date().toISOString(),
    responded_at: toIsoTimestamp(after.respondedAt),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_connections?on_conflict=connection_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(connectionPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST pharmacy connection error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO pharmacy_connections (
              connection_id, doctor_id, medical_store_id, doctor_name, store_name,
              status, requested_by, requested_at, responded_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
            ) ON CONFLICT (connection_id) DO UPDATE SET
              status = EXCLUDED.status,
              requested_by = EXCLUDED.requested_by,
              responded_at = EXCLUDED.responded_at,
              updated_at = NOW();
          `, [
            connectionPayload.connection_id, connectionPayload.doctor_id, connectionPayload.medical_store_id,
            connectionPayload.doctor_name, connectionPayload.store_name, connectionPayload.status,
            connectionPayload.requested_by, connectionPayload.requested_at, connectionPayload.responded_at,
            connectionPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'pharmacy_connection', entityId: connectionId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'pharmacy_connection',
      entityId: connectionId,
      payload: connectionPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 3. Sync Firestore Pharmacy Delivery to Supabase
 */
async function syncFirestorePharmacyDeliveryToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const deliveryId = event.params?.deliveryId || change.after?.id || change.before?.id;
  if (!deliveryId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping pharmacy delivery sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_deliveries?delivery_id=eq.${encodeURIComponent(deliveryId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM pharmacy_deliveries WHERE delivery_id = $1', [deliveryId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'pharmacy_delivery', entityId: deliveryId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'pharmacy_delivery',
        entityId: deliveryId,
        payload: { delivery_id: deliveryId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const prescriptionId = after.prescriptionId;
  const doctorId = after.doctorId;
  const storeId = after.storeId || after.medicalStoreId;
  const patientId = after.patientId || (after.draft && after.draft.patientId);

  // Self-healing foreign keys
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensureMedicalStoreExistsInPostgres(storeId, { storeName: after.storeName }, { url, key, pool });
  await ensurePatientExistsInPostgres(patientId, { patientName: after.patientName }, { url, key, pool });
  await ensurePrescriptionExistsInPostgres(prescriptionId, {
    doctorId,
    patientId,
    doctorName: after.doctorName,
    patientName: after.patientName,
  }, { url, key, pool });

  const rawStatus = after.status || 'sent';
  const status = ['sent', 'viewed', 'partiallyDispensed', 'dispensed'].includes(rawStatus) ? rawStatus : 'sent';
  const medicineCount = parseInt(after.medicineCount ?? (Array.isArray(after.medicineLines) ? after.medicineLines.length : 0), 10) || 0;

  const deliveryPayload = {
    delivery_id: deliveryId,
    prescription_id: prescriptionId,
    doctor_id: doctorId,
    store_id: storeId,
    patient_id: patientId,
    doctor_name: after.doctorName || null,
    store_name: after.storeName || null,
    patient_name: after.patientName || null,
    status: status,
    sent_at: toIsoTimestamp(after.sentAt) || new Date().toISOString(),
    viewed_at: toIsoTimestamp(after.viewedAt),
    dispensed_at: toIsoTimestamp(after.dispensedAt),
    dispensing_notes: after.dispensingNotes || null,
    medicine_count: medicineCount,
    prescription_draft: after.draft || null,
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        // 1. Upsert header
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/pharmacy_deliveries?on_conflict=delivery_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(deliveryPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST pharmacy delivery error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO pharmacy_deliveries (
              delivery_id, prescription_id, doctor_id, store_id, patient_id,
              doctor_name, store_name, patient_name, status, sent_at, viewed_at,
              dispensed_at, dispensing_notes, medicine_count, prescription_draft, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16
            ) ON CONFLICT (delivery_id) DO UPDATE SET
              status = EXCLUDED.status,
              viewed_at = EXCLUDED.viewed_at,
              dispensed_at = EXCLUDED.dispensed_at,
              dispensing_notes = EXCLUDED.dispensing_notes,
              medicine_count = EXCLUDED.medicine_count,
              prescription_draft = EXCLUDED.prescription_draft,
              updated_at = NOW();
          `, [
            deliveryPayload.delivery_id, deliveryPayload.prescription_id, deliveryPayload.doctor_id,
            deliveryPayload.store_id, deliveryPayload.patient_id, deliveryPayload.doctor_name,
            deliveryPayload.store_name, deliveryPayload.patient_name, deliveryPayload.status,
            deliveryPayload.sent_at, deliveryPayload.viewed_at, deliveryPayload.dispensed_at,
            deliveryPayload.dispensing_notes, deliveryPayload.medicine_count,
            deliveryPayload.prescription_draft ? JSON.stringify(deliveryPayload.prescription_draft) : null,
            deliveryPayload.updated_at,
          ]);
        }

        // 2. Sync child medicines
        if (Array.isArray(after.medicineLines)) {
          await syncPharmacyDeliveryMedicinesToSupabase(deliveryId, after.medicineLines, { url, key, pool });
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'pharmacy_delivery', entityId: deliveryId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'pharmacy_delivery',
      entityId: deliveryId,
      payload: deliveryPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 4. Sync Firestore Lab to Supabase
 */
async function syncFirestoreLabToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const labId = event.params?.labId || change.after?.id || change.before?.id;
  if (!labId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping lab sync.');
    return;
  }

  // Handle document deletion (Soft-delete in Postgres)
  if (!change.after || !change.after.exists) {
    const nowIso = new Date().toISOString();
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/labs?lab_id=eq.${encodeURIComponent(labId)}`, {
              method: 'PATCH',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                deactivated: true,
                updated_at: nowIso,
              }),
            });
            if (!resp.ok && resp.status !== 404) {
              const errBody = await resp.text();
              throw new Error(`Supabase PostgREST lab soft-delete error (${resp.status}): ${errBody}`);
            }
          } else if (pool) {
            await pool.query('UPDATE labs SET deactivated = true, updated_at = NOW() WHERE lab_id = $1', [labId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab', entityId: labId, action: 'soft_delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'lab',
        entityId: labId,
        payload: { lab_id: labId, action: 'soft_delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  let addressLine1 = null;
  let addressLine2 = null;
  let city = 'Mumbai';
  let state = 'Maharashtra';
  let country = 'India';
  let pincode = null;
  const area = after.area || null;

  if (after.address && typeof after.address === 'object') {
    addressLine1 = after.address.addressLine1 || after.addressLine1 || null;
    addressLine2 = after.address.addressLine2 || after.addressLine2 || null;
    city = after.address.city || after.city || 'Mumbai';
    state = after.address.state || after.state || 'Maharashtra';
    country = after.address.country || after.country || 'India';
    pincode = after.address.pinCode || after.address.pincode || after.pincode || null;
  } else {
    addressLine1 = after.addressLine1 || (typeof after.address === 'string' ? after.address : null);
    addressLine2 = after.addressLine2 || null;
    city = after.city || 'Mumbai';
    state = after.state || 'Maharashtra';
    country = after.country || 'India';
    pincode = after.pincode || null;
  }

  const labPayload = {
    lab_id: labId,
    owner_uid: toValidUuid(after.ownerUid),
    lab_name: after.labName || 'Diagnostic Lab',
    license_number: after.licenseNumber || 'PENDING',
    phone: after.phone || '0000000000',
    email: (after.email || `${labId}@doctornect.com`).toLowerCase(),
    gst_number: after.gstNumber || null,
    rating: parseFloat(after.rating ?? 0.0) || 0.0,
    area: area,
    city: city,
    state: state,
    country: country,
    pincode: pincode,
    address_line1: addressLine1,
    address_line2: addressLine2,
    profile_completed: Boolean(after.profileCompleted),
    verified: Boolean(after.verified),
    verified_at: toIsoTimestamp(after.verifiedAt),
    deactivated: Boolean(after.deactivated),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/labs?on_conflict=lab_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(labPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST lab error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO labs (
              lab_id, owner_uid, lab_name, license_number, phone, email,
              gst_number, rating, area, city, state, country, pincode,
              address_line1, address_line2, profile_completed, verified,
              verified_at, deactivated, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21
            ) ON CONFLICT (lab_id) DO UPDATE SET
              lab_name = EXCLUDED.lab_name,
              license_number = EXCLUDED.license_number,
              phone = EXCLUDED.phone,
              email = EXCLUDED.email,
              gst_number = EXCLUDED.gst_number,
              rating = EXCLUDED.rating,
              area = EXCLUDED.area,
              city = EXCLUDED.city,
              state = EXCLUDED.state,
              country = EXCLUDED.country,
              pincode = EXCLUDED.pincode,
              address_line1 = EXCLUDED.address_line1,
              address_line2 = EXCLUDED.address_line2,
              profile_completed = EXCLUDED.profile_completed,
              verified = EXCLUDED.verified,
              verified_at = EXCLUDED.verified_at,
              deactivated = EXCLUDED.deactivated,
              updated_at = NOW();
          `, [
            labPayload.lab_id, labPayload.owner_uid, labPayload.lab_name,
            labPayload.license_number, labPayload.phone, labPayload.email,
            labPayload.gst_number, labPayload.rating, labPayload.area,
            labPayload.city, labPayload.state, labPayload.country,
            labPayload.pincode, labPayload.address_line1, labPayload.address_line2,
            labPayload.profile_completed, labPayload.verified, labPayload.verified_at,
            labPayload.deactivated, labPayload.created_at, labPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab', entityId: labId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab',
      entityId: labId,
      payload: labPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 5. Sync Firestore Lab Catalog Test(s) to Supabase
 */
async function syncFirestoreLabCatalogTestToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const testId = event.params?.testId || change.after?.id || change.before?.id;
  if (!testId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping lab catalog sync.');
    return;
  }

  // Deletion handling (Hard delete for single test doc)
  if (!change.after || !change.after.exists) {
    if (testId !== 'default') {
      try {
        await executeWithRetry(
          async () => {
            if (url && key) {
              await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_catalog_tests?test_id=eq.${encodeURIComponent(testId)}`, {
                method: 'DELETE',
                headers: {
                  'apikey': key,
                  'Authorization': `Bearer ${key}`,
                  'Prefer': 'return=minimal',
                },
              });
            } else if (pool) {
              await pool.query('DELETE FROM lab_catalog_tests WHERE test_id = $1', [testId]);
            }
          },
          { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_catalog_tests', entityId: testId, action: 'delete' } }
        );
      } catch (err) {
        await recordDlqFailure({
          direction: 'firestore_to_supabase',
          entityType: 'lab_catalog_tests',
          entityId: testId,
          payload: { test_id: testId, action: 'delete' },
          errorMessage: err.message,
          errorStack: err.stack,
          retryCount: err.retryCount || 3,
        });
        throw err;
      }
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  // Determine if this document is a catalog aggregate (with tests array) or a single test doc
  const rows = [];
  if (Array.isArray(after.tests)) {
    for (const t of after.tests) {
      const tid = t.id || t.testId;
      if (!tid) continue;
      const rawSample = t.sampleType || 'blood';
      const sampleType = ['blood', 'urine', 'swab', 'stool', 'other'].includes(rawSample) ? rawSample : 'blood';
      rows.push({
        test_id: tid,
        name: t.name || 'Lab Test',
        parameters: toStringArray(t.parameters, []),
        fasting_required: Boolean(t.fastingRequired),
        sample_type: sampleType,
        report_hours: parseInt(t.reportHours ?? 24, 10) || 24,
        popular: Boolean(t.popular),
        category: t.category || null,
      });
    }
  } else {
    const rawSample = after.sampleType || 'blood';
    const sampleType = ['blood', 'urine', 'swab', 'stool', 'other'].includes(rawSample) ? rawSample : 'blood';
    rows.push({
      test_id: testId,
      name: after.name || 'Lab Test',
      parameters: toStringArray(after.parameters, []),
      fasting_required: Boolean(after.fastingRequired),
      sample_type: sampleType,
      report_hours: parseInt(after.reportHours ?? 24, 10) || 24,
      popular: Boolean(after.popular),
      category: after.category || null,
    });
  }

  if (rows.length === 0) return;

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_catalog_tests?on_conflict=test_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(rows),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST lab catalog error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          for (const row of rows) {
            await pool.query(`
              INSERT INTO lab_catalog_tests (
                test_id, name, parameters, fasting_required, sample_type, report_hours, popular, category
              ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
              ON CONFLICT (test_id) DO UPDATE SET
                name = EXCLUDED.name,
                parameters = EXCLUDED.parameters,
                fasting_required = EXCLUDED.fasting_required,
                sample_type = EXCLUDED.sample_type,
                report_hours = EXCLUDED.report_hours,
                popular = EXCLUDED.popular,
                category = EXCLUDED.category;
            `, [
              row.test_id, row.name, row.parameters, row.fasting_required,
              row.sample_type, row.report_hours, row.popular, row.category,
            ]);
          }
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_catalog_tests', entityId: testId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_catalog_tests',
      entityId: testId,
      payload: rows,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 6. Sync Firestore Lab Booking to Supabase
 */
async function syncFirestoreLabBookingToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const bookingId = event.params?.bookingId || change.after?.id || change.before?.id;
  if (!bookingId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping lab booking sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_bookings?booking_id=eq.${encodeURIComponent(bookingId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM lab_bookings WHERE booking_id = $1', [bookingId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_booking', entityId: bookingId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'lab_booking',
        entityId: bookingId,
        payload: { booking_id: bookingId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const patientId = after.patientId || 'pat-unknown';

  // Self-healing foreign keys
  await ensurePatientExistsInPostgres(patientId, {
    patientName: after.patientName,
    patientAge: after.patientAge,
    patientGender: after.patientGender,
  }, { url, key, pool });

  if (after.labId) {
    await ensureLabExistsInPostgres(after.labId, { labName: after.partnerLab }, { url, key, pool });
  }

  const testNames = toStringArray(after.testNames, [after.testName || 'Lab Test']);
  const testIds = toStringArray(after.testIds, [after.testId || 'general_test']);
  const rawColl = after.collectionType || 'labVisit';
  const collectionType = ['homeCollection', 'labVisit', 'walkIn'].includes(rawColl) ? rawColl : 'labVisit';
  const rawStatus = after.status || 'confirmed';
  const status = ['confirmed', 'sampleCollected', 'inAnalysis', 'completed', 'cancelled'].includes(rawStatus) ? rawStatus : 'confirmed';
  const rawSource = after.source || 'app';
  const source = ['app', 'walkin'].includes(rawSource) ? rawSource : 'app';

  const bookingPayload = {
    booking_id: bookingId,
    patient_id: patientId,
    lab_id: after.labId || null,
    patient_name: after.patientName || 'Patient',
    patient_age: parseInt(after.patientAge || 30, 10) || 30,
    patient_gender: after.patientGender || null,
    contact_number: after.contactNumber || null,
    test_id: after.testId || (testIds[0] || 'general_test'),
    test_name: after.testName || (testNames[0] || 'Lab Test'),
    test_names: testNames,
    test_ids: testIds,
    booking_for_self: after.bookingForSelf !== false,
    family_member_id: after.familyMemberId || null,
    collection_type: collectionType,
    partner_lab: after.partnerLab || null,
    address: after.address || null,
    date_time: toIsoTimestamp(after.dateTime) || new Date().toISOString(),
    slot_label: after.slotLabel || 'Morning',
    status: status,
    source: source,
    report_file_name: after.reportFileName || null,
    report_storage_url: after.reportStorageUrl || null,
    report_booking_id: after.reportBookingId || null,
    report_submitted_at: toIsoTimestamp(after.reportSubmittedAt),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_bookings?on_conflict=booking_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(bookingPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST lab booking error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO lab_bookings (
              booking_id, patient_id, lab_id, patient_name, patient_age, patient_gender,
              contact_number, test_id, test_name, test_names, test_ids, booking_for_self,
              family_member_id, collection_type, partner_lab, address, date_time, slot_label,
              status, source, report_file_name, report_storage_url, report_booking_id,
              report_submitted_at, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26
            ) ON CONFLICT (booking_id) DO UPDATE SET
              status = EXCLUDED.status,
              report_file_name = EXCLUDED.report_file_name,
              report_storage_url = EXCLUDED.report_storage_url,
              report_booking_id = EXCLUDED.report_booking_id,
              report_submitted_at = EXCLUDED.report_submitted_at,
              updated_at = NOW();
          `, [
            bookingPayload.booking_id, bookingPayload.patient_id, bookingPayload.lab_id,
            bookingPayload.patient_name, bookingPayload.patient_age, bookingPayload.patient_gender,
            bookingPayload.contact_number, bookingPayload.test_id, bookingPayload.test_name,
            bookingPayload.test_names, bookingPayload.test_ids, bookingPayload.booking_for_self,
            bookingPayload.family_member_id, bookingPayload.collection_type, bookingPayload.partner_lab,
            bookingPayload.address, bookingPayload.date_time, bookingPayload.slot_label,
            bookingPayload.status, bookingPayload.source, bookingPayload.report_file_name,
            bookingPayload.report_storage_url, bookingPayload.report_booking_id,
            bookingPayload.report_submitted_at, bookingPayload.created_at, bookingPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_booking', entityId: bookingId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_booking',
      entityId: bookingId,
      payload: bookingPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 7. Sync Firestore Lab Order to Supabase
 */
async function syncFirestoreLabOrderToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const orderId = event.params?.orderId || change.after?.id || change.before?.id;
  if (!orderId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping lab order sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_orders?order_id=eq.${encodeURIComponent(orderId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM lab_orders WHERE order_id = $1', [orderId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_order', entityId: orderId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'lab_order',
        entityId: orderId,
        payload: { order_id: orderId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorId = after.doctorId || 'doc-unknown';
  const patientId = after.patientId || 'pat-unknown';

  // Self-healing foreign keys
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensurePatientExistsInPostgres(patientId, {
    patientName: after.patientName,
    patientAge: after.patientAge,
  }, { url, key, pool });

  if (after.labId) {
    await ensureLabExistsInPostgres(after.labId, { labName: after.labName }, { url, key, pool });
  }

  const testIds = toStringArray(after.testIds, []);
  const testNames = toStringArray(after.testNames, []);
  const rawUrgency = after.urgency || 'Routine';
  const urgency = ['Routine', 'Urgent', 'STAT'].includes(rawUrgency) ? rawUrgency : 'Routine';
  const rawStatus = after.status || 'ordered';
  const status = ['ordered', 'received', 'inProgress', 'completed', 'cancelled'].includes(rawStatus) ? rawStatus : 'ordered';

  const orderPayload = {
    order_id: orderId,
    doctor_id: doctorId,
    patient_id: patientId,
    lab_id: after.labId || null,
    appointment_id: after.appointmentId || null,
    facility_id: after.facilityId || null,
    admission_id: after.admissionId || null,
    doctor_name: after.doctorName || 'Doctor',
    patient_name: after.patientName || 'Patient',
    patient_age: parseInt(after.patientAge || 30, 10) || 30,
    lab_name: after.labName || null,
    test_ids: testIds,
    test_names: testNames,
    indication: after.indication || null,
    urgency: urgency,
    fasting_required: Boolean(after.fastingRequired),
    home_collection: Boolean(after.homeCollection),
    source: after.source || 'investigations',
    status: status,
    report_file_name: after.reportFileName || null,
    report_storage_url: after.reportStorageUrl || null,
    report_submitted_at: toIsoTimestamp(after.reportSubmittedAt),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_orders?on_conflict=order_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(orderPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST lab order error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO lab_orders (
              order_id, doctor_id, patient_id, lab_id, appointment_id, facility_id, admission_id,
              doctor_name, patient_name, patient_age, lab_name, test_ids, test_names, indication,
              urgency, fasting_required, home_collection, source, status, report_file_name,
              report_storage_url, report_submitted_at, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24
            ) ON CONFLICT (order_id) DO UPDATE SET
              status = EXCLUDED.status,
              report_file_name = EXCLUDED.report_file_name,
              report_storage_url = EXCLUDED.report_storage_url,
              report_submitted_at = EXCLUDED.report_submitted_at,
              updated_at = NOW();
          `, [
            orderPayload.order_id, orderPayload.doctor_id, orderPayload.patient_id,
            orderPayload.lab_id, orderPayload.appointment_id, orderPayload.facility_id,
            orderPayload.admission_id, orderPayload.doctor_name, orderPayload.patient_name,
            orderPayload.patient_age, orderPayload.lab_name, orderPayload.test_ids,
            orderPayload.test_names, orderPayload.indication, orderPayload.urgency,
            orderPayload.fasting_required, orderPayload.home_collection, orderPayload.source,
            orderPayload.status, orderPayload.report_file_name, orderPayload.report_storage_url,
            orderPayload.report_submitted_at, orderPayload.created_at, orderPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_order', entityId: orderId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_order',
      entityId: orderId,
      payload: orderPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 8. Sync Firestore Lab Connection to Supabase
 */
async function syncFirestoreLabConnectionToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const connectionId = event.params?.connectionId || change.after?.id || change.before?.id;
  if (!connectionId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping lab connection sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_connections?connection_id=eq.${encodeURIComponent(connectionId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM lab_connections WHERE connection_id = $1', [connectionId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_connection', entityId: connectionId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'lab_connection',
        entityId: connectionId,
        payload: { connection_id: connectionId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorId = after.doctorId;
  const labId = after.labId;

  // Self-healing foreign keys
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensureLabExistsInPostgres(labId, { labName: after.labName }, { url, key, pool });

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'active', 'rejected', 'removed'].includes(rawStatus) ? rawStatus : 'pending';
  const rawReqBy = after.requestedBy || 'doctor';
  const requestedBy = ['doctor', 'lab'].includes(rawReqBy) ? rawReqBy : 'doctor';

  const labConnectionPayload = {
    connection_id: connectionId,
    doctor_id: doctorId,
    lab_id: labId,
    doctor_name: after.doctorName || 'Doctor',
    lab_name: after.labName || 'Diagnostic Lab',
    status: status,
    requested_by: requestedBy,
    requested_at: toIsoTimestamp(after.requestedAt) || new Date().toISOString(),
    responded_at: toIsoTimestamp(after.respondedAt),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/lab_connections?on_conflict=connection_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(labConnectionPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST lab connection error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO lab_connections (
              connection_id, doctor_id, lab_id, doctor_name, lab_name,
              status, requested_by, requested_at, responded_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
            ) ON CONFLICT (connection_id) DO UPDATE SET
              status = EXCLUDED.status,
              requested_by = EXCLUDED.requested_by,
              responded_at = EXCLUDED.responded_at,
              updated_at = NOW();
          `, [
            labConnectionPayload.connection_id, labConnectionPayload.doctor_id,
            labConnectionPayload.lab_id, labConnectionPayload.doctor_name,
            labConnectionPayload.lab_name, labConnectionPayload.status,
            labConnectionPayload.requested_by, labConnectionPayload.requested_at,
            labConnectionPayload.responded_at, labConnectionPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'lab_connection', entityId: connectionId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_connection',
      entityId: connectionId,
      payload: labConnectionPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * Helper: Hash ambulance PIN using secure salted PBKDF2 (matching auth system)
 */
function hashAmbulancePin(pin) {
  const salt = crypto.randomBytes(16);
  const PBKDF2_ITERATIONS = 100000;
  const PBKDF2_KEYLEN = 64;
  const PBKDF2_DIGEST = 'sha256';
  const derived = crypto.pbkdf2Sync(
    String(pin || '').trim(),
    salt,
    PBKDF2_ITERATIONS,
    PBKDF2_KEYLEN,
    PBKDF2_DIGEST,
  );
  return `pbkdf2$sha256$${PBKDF2_ITERATIONS}$${salt.toString('hex')}$${derived.toString('hex')}`;
}

/**
 * Helper: Check if string is already a valid hashed PIN (PBKDF2 or SHA-256 hex)
 */
function isAmbulancePinHash(val) {
  const s = String(val || '').trim();
  if (s.startsWith('pbkdf2$')) return true;
  return s.length === 64 && /^[a-f0-9]{64}$/i.test(s);
}

/**
 * Ensure parent ambulance exists in Postgres before inserting child records
 */
async function ensureAmbulanceExistsInPostgres(ambulanceId, fallbackData = {}, { url, key, pool }) {
  if (!ambulanceId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulances?ambulance_id=eq.${encodeURIComponent(ambulanceId)}&select=ambulance_id`, {
        method: 'GET',
        headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT ambulance_id FROM ambulances WHERE ambulance_id = $1 LIMIT 1', [ambulanceId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('ambulances').doc(ambulanceId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const placeholder = {
    ambulance_id: ambulanceId,
    service_name: docData?.serviceName || fallbackData.serviceName || 'Ambulance Service',
    driver_name: docData?.driverName || fallbackData.driverName || 'Driver',
    phone: docData?.phone || fallbackData.phone || '0000000000',
    vehicle_number: docData?.vehicleNumber || fallbackData.vehicleNumber || 'MH-00-XX-0000',
    ambulance_type: ['bls', 'als', 'icu', 'patientTransport'].includes(docData?.ambulanceType) ? docData.ambulanceType : 'bls',
    city: (docData?.address && docData?.address.city) || docData?.city || 'Mumbai',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulances?on_conflict=ambulance_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholder),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO ambulances (ambulance_id, service_name, driver_name, phone, vehicle_number, ambulance_type, city, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        ON CONFLICT (ambulance_id) DO NOTHING;
      `, [
        placeholder.ambulance_id,
        placeholder.service_name,
        placeholder.driver_name,
        placeholder.phone,
        placeholder.vehicle_number,
        placeholder.ambulance_type,
        placeholder.city,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent ambulance ${ambulanceId} in Postgres: ${e.message}`);
  }
}

/**
 * Ensure parent ambulance broadcast exists in Postgres before inserting request records
 */
async function ensureAmbulanceBroadcastExistsInPostgres(broadcastId, fallbackData = {}, { url, key, pool }) {
  if (!broadcastId) return;

  try {
    if (url && key) {
      const checkResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_broadcasts?broadcast_id=eq.${encodeURIComponent(broadcastId)}&select=broadcast_id`, {
        method: 'GET',
        headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
      });
      if (checkResp.ok) {
        const rows = await checkResp.json();
        if (Array.isArray(rows) && rows.length > 0) return;
      }
    } else if (pool) {
      const res = await pool.query('SELECT broadcast_id FROM ambulance_broadcasts WHERE broadcast_id = $1 LIMIT 1', [broadcastId]);
      if (res.rows && res.rows.length > 0) return;
    }
  } catch (_) {}

  let docData = null;
  try {
    const db = getFirestore();
    const snap = await db.collection('ambulance_broadcasts').doc(broadcastId).get();
    if (snap.exists) docData = snap.data();
  } catch (_) {}

  const placeholder = {
    broadcast_id: broadcastId,
    patient_id: docData?.patientId || fallbackData.patientId || 'pat-unknown',
    patient_name: docData?.patientName || fallbackData.patientName || 'Patient',
    pickup_location: docData?.pickupLocation || fallbackData.pickupLocation || 'Pickup location',
    drop_location: docData?.dropLocation || fallbackData.dropLocation || 'Drop location',
    contact_phone: docData?.contactPhone || fallbackData.contactPhone || '0000000000',
    status: ['pending', 'accepted', 'completed', 'cancelled'].includes(docData?.status) ? docData.status : 'pending',
    created_at: toIsoTimestamp(docData?.createdAt) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    if (url && key) {
      await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_broadcasts?on_conflict=broadcast_id`, {
        method: 'POST',
        headers: {
          'apikey': key,
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(placeholder),
      });
    } else if (pool) {
      await pool.query(`
        INSERT INTO ambulance_broadcasts (broadcast_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        ON CONFLICT (broadcast_id) DO NOTHING;
      `, [
        placeholder.broadcast_id,
        placeholder.patient_id,
        placeholder.patient_name,
        placeholder.pickup_location,
        placeholder.drop_location,
        placeholder.contact_phone,
        placeholder.status,
      ]);
    }
  } catch (e) {
    console.warn(`[SyncBridge] Warning: unable to ensure parent ambulance_broadcast ${broadcastId} in Postgres: ${e.message}`);
  }
}

/**
 * 1. Sync Firestore Ambulance to Supabase
 */
async function syncFirestoreAmbulanceToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const ambulanceId = event.params?.ambulanceId || change.after?.id || change.before?.id;
  if (!ambulanceId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping ambulance sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulances?ambulance_id=eq.${encodeURIComponent(ambulanceId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM ambulances WHERE ambulance_id = $1', [ambulanceId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance', entityId: ambulanceId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'ambulance',
        entityId: ambulanceId,
        payload: { ambulance_id: ambulanceId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  let addressLine1 = null;
  let addressLine2 = null;
  let state = 'Maharashtra';
  let country = 'India';
  let pincode = null;
  let city = 'Mumbai';

  if (after.address && typeof after.address === 'object') {
    addressLine1 = after.address.addressLine1 || after.addressLine1 || null;
    addressLine2 = after.address.addressLine2 || after.addressLine2 || null;
    city = after.address.city || after.city || 'Mumbai';
    state = after.address.state || after.state || 'Maharashtra';
    country = after.address.country || after.country || 'India';
    pincode = after.address.pinCode || after.address.pincode || after.pincode || null;
  } else {
    addressLine1 = after.addressLine1 || (typeof after.address === 'string' ? after.address : null);
    addressLine2 = after.addressLine2 || null;
    city = after.city || 'Mumbai';
    state = after.state || 'Maharashtra';
    country = after.country || 'India';
    pincode = after.pincode || null;
  }

  const ambulancePayload = {
    ambulance_id: ambulanceId,
    auth_uid: toValidUuid(after.authUid),
    service_name: after.serviceName || 'Ambulance Service',
    owner_name: after.ownerName || null,
    driver_name: after.driverName || 'Driver',
    phone: after.phone || '0000000000',
    vehicle_number: after.vehicleNumber || 'MH-00-XX-0000',
    ambulance_type: ['bls', 'als', 'icu', 'patientTransport'].includes(after.ambulanceType) ? after.ambulanceType : 'bls',
    username: after.username ? String(after.username).trim().toLowerCase() : null,
    city: city,
    base_address: after.baseAddress || null,
    license_number: after.licenseNumber || null,
    insurance_number: after.insuranceNumber || null,
    has_oxygen: Boolean(after.hasOxygen),
    has_ventilator: Boolean(after.hasVentilator),
    has_stretcher: after.hasStretcher !== false,
    is_24x7: Boolean(after.is24x7),
    rate_per_km: after.ratePerKm != null ? parseFloat(after.ratePerKm) : null,
    total_rating: parseFloat(after.totalRating ?? 0.0) || 0.0,
    rating_count: parseInt(after.ratingCount ?? 0, 10) || 0,
    is_available: after.isAvailable !== false && after.available !== false,
    profile_completed: Boolean(after.profileCompleted),
    verified: Boolean(after.verified),
    address_line1: addressLine1,
    address_line2: addressLine2,
    state: state,
    country: country,
    pincode: pincode,
    service_areas: toStringArray(after.serviceAreas, []),
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulances?on_conflict=ambulance_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(ambulancePayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST ambulance error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO ambulances (
              ambulance_id, auth_uid, service_name, owner_name, driver_name, phone,
              vehicle_number, ambulance_type, username, city, base_address, license_number,
              insurance_number, has_oxygen, has_ventilator, has_stretcher, is_24x7,
              rate_per_km, total_rating, rating_count, is_available, profile_completed,
              verified, address_line1, address_line2, state, country, pincode, service_areas,
              created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17,
              $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31
            ) ON CONFLICT (ambulance_id) DO UPDATE SET
              auth_uid = EXCLUDED.auth_uid,
              service_name = EXCLUDED.service_name,
              owner_name = EXCLUDED.owner_name,
              driver_name = EXCLUDED.driver_name,
              phone = EXCLUDED.phone,
              vehicle_number = EXCLUDED.vehicle_number,
              ambulance_type = EXCLUDED.ambulance_type,
              username = EXCLUDED.username,
              city = EXCLUDED.city,
              base_address = EXCLUDED.base_address,
              license_number = EXCLUDED.license_number,
              insurance_number = EXCLUDED.insurance_number,
              has_oxygen = EXCLUDED.has_oxygen,
              has_ventilator = EXCLUDED.has_ventilator,
              has_stretcher = EXCLUDED.has_stretcher,
              is_24x7 = EXCLUDED.is_24x7,
              rate_per_km = EXCLUDED.rate_per_km,
              total_rating = EXCLUDED.total_rating,
              rating_count = EXCLUDED.rating_count,
              is_available = EXCLUDED.is_available,
              profile_completed = EXCLUDED.profile_completed,
              verified = EXCLUDED.verified,
              address_line1 = EXCLUDED.address_line1,
              address_line2 = EXCLUDED.address_line2,
              state = EXCLUDED.state,
              country = EXCLUDED.country,
              pincode = EXCLUDED.pincode,
              service_areas = EXCLUDED.service_areas,
              updated_at = NOW();
          `, [
            ambulancePayload.ambulance_id, ambulancePayload.auth_uid, ambulancePayload.service_name,
            ambulancePayload.owner_name, ambulancePayload.driver_name, ambulancePayload.phone,
            ambulancePayload.vehicle_number, ambulancePayload.ambulance_type, ambulancePayload.username,
            ambulancePayload.city, ambulancePayload.base_address, ambulancePayload.license_number,
            ambulancePayload.insurance_number, ambulancePayload.has_oxygen, ambulancePayload.has_ventilator,
            ambulancePayload.has_stretcher, ambulancePayload.is_24x7, ambulancePayload.rate_per_km,
            ambulancePayload.total_rating, ambulancePayload.rating_count, ambulancePayload.is_available,
            ambulancePayload.profile_completed, ambulancePayload.verified, ambulancePayload.address_line1,
            ambulancePayload.address_line2, ambulancePayload.state, ambulancePayload.country,
            ambulancePayload.pincode, ambulancePayload.service_areas, ambulancePayload.created_at,
            ambulancePayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance', entityId: ambulanceId } }
    );

    // If ambulance document includes inline PIN / pinHash, also sync ambulance_private_settings
    if (after.pinHash || after.pin || after.pin_hash) {
      try {
        await syncFirestoreAmbulancePrivateSettingsToSupabase(event);
      } catch (inlinePinErr) {
        console.warn(`[SyncBridge] Warning: unable to sync inline PIN settings for ambulance ${ambulanceId}: ${inlinePinErr.message}`);
      }
    }
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance',
      entityId: ambulanceId,
      payload: ambulancePayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 2. Sync Firestore Ambulance Private Settings to Supabase
 * Handles sensitive driver credentials: raw PINs are NEVER stored;
 * hashes (PBKDF2/SHA-256) are validated and synced to satisfy Postgres NOT NULL constraint.
 */
async function syncFirestoreAmbulancePrivateSettingsToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const ambulanceId = event.params?.ambulanceId || change.after?.id || change.before?.id;
  if (!ambulanceId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping ambulance private settings sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_private_settings?ambulance_id=eq.${encodeURIComponent(ambulanceId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM ambulance_private_settings WHERE ambulance_id = $1', [ambulanceId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_private_settings', entityId: ambulanceId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'ambulance_private_settings',
        entityId: ambulanceId,
        payload: { ambulance_id: ambulanceId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  // Self-healing parent ambulance foreign key
  await ensureAmbulanceExistsInPostgres(ambulanceId, {}, { url, key, pool });

  let pinHash = null;
  const rawPin = after.pinHash || after.pin || after.pin_hash;
  if (isAmbulancePinHash(rawPin)) {
    pinHash = String(rawPin).trim();
  } else if (rawPin && String(rawPin).trim().length > 0) {
    // If raw plaintext PIN is passed, hash it immediately via PBKDF2 before syncing
    pinHash = hashAmbulancePin(rawPin);
  }

  // If no PIN provided in this event (e.g. only FCM token update), preserve existing Postgres pin_hash
  if (!pinHash) {
    try {
      if (url && key) {
        const existingResp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_private_settings?ambulance_id=eq.${encodeURIComponent(ambulanceId)}&select=pin_hash`, {
          headers: { 'apikey': key, 'Authorization': `Bearer ${key}` },
        });
        if (existingResp.ok) {
          const rows = await existingResp.json();
          if (rows?.[0]?.pin_hash) pinHash = rows[0].pin_hash;
        }
      } else if (pool) {
        const res = await pool.query('SELECT pin_hash FROM ambulance_private_settings WHERE ambulance_id = $1 LIMIT 1', [ambulanceId]);
        if (res.rows?.[0]?.pin_hash) pinHash = res.rows[0].pin_hash;
      }
    } catch (_) {}
  }

  // Fallback check from Firestore ambulances/{ambulanceId}/private/settings if still missing
  if (!pinHash) {
    try {
      const db = getFirestore();
      const privSnap = await db.collection('ambulances').doc(ambulanceId).collection('private').doc('settings').get();
      const privPin = privSnap.data()?.pin || privSnap.data()?.pinHash;
      if (isAmbulancePinHash(privPin)) pinHash = String(privPin).trim();
      else if (privPin) pinHash = hashAmbulancePin(privPin);
    } catch (_) {}
  }

  if (!pinHash) {
    console.warn(`[SyncBridge] Warning: skipping ambulance_private_settings for ${ambulanceId} because pin_hash is required and absent.`);
    return;
  }

  const settingsPayload = {
    ambulance_id: ambulanceId,
    pin_hash: pinHash,
    fcm_token: after.fcmToken || null,
    fcm_token_updated_at: toIsoTimestamp(after.fcmTokenUpdatedAt),
    updated_at: toIsoTimestamp(after.updatedAt || after.pinUpdatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_private_settings?on_conflict=ambulance_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(settingsPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST ambulance_private_settings error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO ambulance_private_settings (
              ambulance_id, pin_hash, fcm_token, fcm_token_updated_at, updated_at
            ) VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (ambulance_id) DO UPDATE SET
              pin_hash = EXCLUDED.pin_hash,
              fcm_token = EXCLUDED.fcm_token,
              fcm_token_updated_at = EXCLUDED.fcm_token_updated_at,
              updated_at = NOW();
          `, [
            settingsPayload.ambulance_id,
            settingsPayload.pin_hash,
            settingsPayload.fcm_token,
            settingsPayload.fcm_token_updated_at,
            settingsPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_private_settings', entityId: ambulanceId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_private_settings',
      entityId: ambulanceId,
      payload: settingsPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 3. Sync Firestore Ambulance Broadcast to Supabase
 * Handles dispatch status transitions and propagates sibling cancellations in Postgres.
 */
async function syncFirestoreAmbulanceBroadcastToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const broadcastId = event.params?.broadcastId || change.after?.id || change.before?.id;
  if (!broadcastId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping ambulance broadcast sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_broadcasts?broadcast_id=eq.${encodeURIComponent(broadcastId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM ambulance_broadcasts WHERE broadcast_id = $1', [broadcastId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_broadcast', entityId: broadcastId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'ambulance_broadcast',
        entityId: broadcastId,
        payload: { broadcast_id: broadcastId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  // Self-healing parent ambulance if acceptedDriverId is present
  if (after.acceptedDriverId) {
    await ensureAmbulanceExistsInPostgres(after.acceptedDriverId, {
      serviceName: after.acceptedDriverName || after.acceptedAmbulanceName,
      phone: after.acceptedDriverPhone,
      vehicleNumber: after.acceptedVehicleNumber,
      ambulanceType: after.acceptedAmbulanceType,
    }, { url, key, pool });
  }

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'accepted', 'completed', 'cancelled'].includes(rawStatus) ? rawStatus : 'pending';

  const broadcastPayload = {
    broadcast_id: broadcastId,
    patient_id: after.patientId || 'pat-unknown',
    patient_name: after.patientName || 'Patient',
    pickup_location: after.pickupLocation || 'Pickup location',
    drop_location: after.dropLocation || 'Drop location',
    contact_phone: after.contactPhone || '0000000000',
    notes: after.notes || null,
    status: status,
    accepted_driver_id: after.acceptedDriverId || null,
    accepted_driver_name: after.acceptedDriverName || after.acceptedAmbulanceName || null,
    accepted_driver_phone: after.acceptedDriverPhone || null,
    accepted_vehicle_number: after.acceptedVehicleNumber || null,
    accepted_ambulance_type: after.acceptedAmbulanceType || null,
    accepted_at: toIsoTimestamp(after.acceptedAt),
    rating: after.rating != null ? parseInt(after.rating, 10) : null,
    review: after.review || null,
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        // 1. Upsert broadcast
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_broadcasts?on_conflict=broadcast_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(broadcastPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST ambulance broadcast error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO ambulance_broadcasts (
              broadcast_id, patient_id, patient_name, pickup_location, drop_location,
              contact_phone, notes, status, accepted_driver_id, accepted_driver_name,
              accepted_driver_phone, accepted_vehicle_number, accepted_ambulance_type,
              accepted_at, rating, review, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18
            ) ON CONFLICT (broadcast_id) DO UPDATE SET
              status = EXCLUDED.status,
              accepted_driver_id = EXCLUDED.accepted_driver_id,
              accepted_driver_name = EXCLUDED.accepted_driver_name,
              accepted_driver_phone = EXCLUDED.accepted_driver_phone,
              accepted_vehicle_number = EXCLUDED.accepted_vehicle_number,
              accepted_ambulance_type = EXCLUDED.accepted_ambulance_type,
              accepted_at = EXCLUDED.accepted_at,
              rating = EXCLUDED.rating,
              review = EXCLUDED.review,
              updated_at = NOW();
          `, [
            broadcastPayload.broadcast_id, broadcastPayload.patient_id, broadcastPayload.patient_name,
            broadcastPayload.pickup_location, broadcastPayload.drop_location, broadcastPayload.contact_phone,
            broadcastPayload.notes, broadcastPayload.status, broadcastPayload.accepted_driver_id,
            broadcastPayload.accepted_driver_name, broadcastPayload.accepted_driver_phone,
            broadcastPayload.accepted_vehicle_number, broadcastPayload.accepted_ambulance_type,
            broadcastPayload.accepted_at, broadcastPayload.rating, broadcastPayload.review,
            broadcastPayload.created_at, broadcastPayload.updated_at,
          ]);
        }

        // 2. Reflect Sibling Cancellation / Taken status in Postgres
        if (status === 'accepted' && after.acceptedDriverId) {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_requests?broadcast_id=eq.${encodeURIComponent(broadcastId)}&driver_id=neq.${encodeURIComponent(after.acceptedDriverId)}&status=eq.pending`, {
              method: 'PATCH',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                status: 'taken',
                accepted_driver_id: after.acceptedDriverId,
                updated_at: new Date().toISOString(),
              }),
            });
          } else if (pool) {
            await pool.query(
              `UPDATE ambulance_requests SET status = 'taken', accepted_driver_id = $1, updated_at = NOW() WHERE broadcast_id = $2 AND driver_id != $1 AND status = 'pending'`,
              [after.acceptedDriverId, broadcastId]
            );
          }
        } else if (status === 'cancelled') {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_requests?broadcast_id=eq.${encodeURIComponent(broadcastId)}&status=eq.pending`, {
              method: 'PATCH',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: JSON.stringify({
                status: 'cancelled',
                updated_at: new Date().toISOString(),
              }),
            });
          } else if (pool) {
            await pool.query(
              `UPDATE ambulance_requests SET status = 'cancelled', updated_at = NOW() WHERE broadcast_id = $1 AND status = 'pending'`,
              [broadcastId]
            );
          }
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_broadcast', entityId: broadcastId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_broadcast',
      entityId: broadcastId,
      payload: broadcastPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 4. Sync Firestore Ambulance Request to Supabase
 * Accurately tracks per-driver request status (pending, taken, accepted, cancelled).
 */
async function syncFirestoreAmbulanceRequestToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const requestId = event.params?.requestId || change.after?.id || change.before?.id;
  if (!requestId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping ambulance request sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_requests?request_id=eq.${encodeURIComponent(requestId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM ambulance_requests WHERE request_id = $1', [requestId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_request', entityId: requestId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'ambulance_request',
        entityId: requestId,
        payload: { request_id: requestId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const broadcastId = after.broadcastId;
  const driverId = after.driverId;

  // Self-healing parent foreign keys
  await ensureAmbulanceBroadcastExistsInPostgres(broadcastId, after, { url, key, pool });
  await ensureAmbulanceExistsInPostgres(driverId, {}, { url, key, pool });

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'taken', 'accepted', 'cancelled'].includes(rawStatus) ? rawStatus : 'pending';

  const requestPayload = {
    request_id: requestId,
    broadcast_id: broadcastId,
    driver_id: driverId,
    patient_id: after.patientId || 'pat-unknown',
    patient_name: after.patientName || 'Patient',
    pickup_location: after.pickupLocation || 'Pickup location',
    drop_location: after.dropLocation || 'Drop location',
    contact_phone: after.contactPhone || '0000000000',
    status: status,
    accepted_driver_id: after.acceptedDriverId || null,
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    updated_at: toIsoTimestamp(after.updatedAt) || new Date().toISOString(),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_requests?on_conflict=request_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(requestPayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST ambulance request error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO ambulance_requests (
              request_id, broadcast_id, driver_id, patient_id, patient_name,
              pickup_location, drop_location, contact_phone, status,
              accepted_driver_id, created_at, updated_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12
            ) ON CONFLICT (request_id) DO UPDATE SET
              status = EXCLUDED.status,
              accepted_driver_id = EXCLUDED.accepted_driver_id,
              updated_at = NOW();
          `, [
            requestPayload.request_id, requestPayload.broadcast_id, requestPayload.driver_id,
            requestPayload.patient_id, requestPayload.patient_name, requestPayload.pickup_location,
            requestPayload.drop_location, requestPayload.contact_phone, requestPayload.status,
            requestPayload.accepted_driver_id, requestPayload.created_at, requestPayload.updated_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_request', entityId: requestId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_request',
      entityId: requestId,
      payload: requestPayload,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount: retryCount,
    });
    throw actualErr;
  }
}

/**
 * 5. Sync Firestore Ambulance Invite to Supabase
 */
async function syncFirestoreAmbulanceInviteToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const inviteId = event.params?.inviteId || change.after?.id || change.before?.id;
  if (!inviteId) return;

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping ambulance invite sync.');
    return;
  }

  // Deletion handling: Hard delete
  if (!change.after || !change.after.exists) {
    try {
      await executeWithRetry(
        async () => {
          if (url && key) {
            await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_invites?invite_id=eq.${encodeURIComponent(inviteId)}`, {
              method: 'DELETE',
              headers: {
                'apikey': key,
                'Authorization': `Bearer ${key}`,
                'Prefer': 'return=minimal',
              },
            });
          } else if (pool) {
            await pool.query('DELETE FROM ambulance_invites WHERE invite_id = $1', [inviteId]);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_invite', entityId: inviteId, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'ambulance_invite',
        entityId: inviteId,
        payload: { invite_id: inviteId, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  const after = change.after.data();

  // Loop prevention check
  if (after.syncedBy === 'supabase_bridge' || after.syncedBy === 'reconciler_bot') {
    return;
  }

  const doctorId = after.doctorId;

  // Self-healing parent doctor foreign key
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'completed', 'cancelled'].includes(rawStatus)
    ? rawStatus
    : (rawStatus === 'expired' ? 'cancelled' : 'pending');

  const invitePayload = {
    invite_id: inviteId,
    token: after.token || inviteId,
    doctor_id: doctorId,
    ambulance_id: after.ambulanceId || 'amb-unknown',
    service_name: after.serviceName || 'Ambulance Service',
    driver_name: after.driverName || 'Driver',
    phone: after.phone || '0000000000',
    status: status,
    username: after.username || null,
    created_at: toIsoTimestamp(after.createdAt) || new Date().toISOString(),
    completed_at: toIsoTimestamp(after.completedAt),
  };

  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const resp = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/ambulance_invites?on_conflict=invite_id`, {
            method: 'POST',
            headers: {
              'apikey': key,
              'Authorization': `Bearer ${key}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(invitePayload),
          });
          if (!resp.ok) {
            const errBody = await resp.text();
            throw new Error(`Supabase PostgREST ambulance invite error (${resp.status}): ${errBody}`);
          }
        } else if (pool) {
          await pool.query(`
            INSERT INTO ambulance_invites (
              invite_id, token, doctor_id, ambulance_id, service_name, driver_name,
              phone, status, username, created_at, completed_at
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
            ) ON CONFLICT (invite_id) DO UPDATE SET
              status = EXCLUDED.status,
              username = EXCLUDED.username,
              completed_at = EXCLUDED.completed_at;
          `, [
            invitePayload.invite_id, invitePayload.token, invitePayload.doctor_id,
            invitePayload.ambulance_id, invitePayload.service_name, invitePayload.driver_name,
            invitePayload.phone, invitePayload.status, invitePayload.username,
            invitePayload.created_at, invitePayload.completed_at,
          ]);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'ambulance_invite', entityId: inviteId } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_invite',
      entityId: inviteId,
      payload: invitePayload,
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
  syncFirestoreDoctorToSupabase,
  syncFirestoreDoctorAvailabilityToSupabase,
  syncFirestoreDoctorBlockedDatesToSupabase,
  syncDoctorEducationToSupabase,
  syncDoctorBlockedDatesToSupabase,
  syncFirestoreMedicalStoreToSupabase,
  syncFirestorePharmacyConnectionToSupabase,
  syncFirestorePharmacyDeliveryToSupabase,
  syncPharmacyDeliveryMedicinesToSupabase,
  syncFirestoreLabToSupabase,
  syncFirestoreLabCatalogTestToSupabase,
  syncFirestoreLabBookingToSupabase,
  syncFirestoreLabOrderToSupabase,
  syncFirestoreLabConnectionToSupabase,
  syncFirestoreAmbulanceToSupabase,
  syncFirestoreAmbulancePrivateSettingsToSupabase,
  syncFirestoreAmbulanceBroadcastToSupabase,
  syncFirestoreAmbulanceRequestToSupabase,
  syncFirestoreAmbulanceInviteToSupabase,
  ensureDoctorExistsInPostgres,
  ensureMedicalStoreExistsInPostgres,
  ensureLabExistsInPostgres,
  ensurePatientExistsInPostgres,
  ensurePrescriptionExistsInPostgres,
  ensureAmbulanceExistsInPostgres,
  ensureAmbulanceBroadcastExistsInPostgres,
  hashAmbulancePin,
  isAmbulancePinHash,
  recordDlqFailure,
  executeWithRetry,
  toStringArray,
  toIsoTimestamp,
  toDateString,
  toValidUuid,
};




