'use strict';

/**
 * DoctorNect: Cross-Role Staged Sync Bridge (Firestore -> Supabase)
 * 
 * Synchronizes Doctor/Clinic mutations (Appointment status updates, consultation outcomes,
 * and Prescriptions) from Firestore into Supabase PostgreSQL for Patient consumption.
 * 
 * Includes:
 * 1. Strict loop prevention (detects syncedBy: 'supabase_bridge' | 'reconciler_bot')
 * 2. Monotonic compare-and-skip: an appointment upsert runs only when Firestore
 *    updatedAt is strictly newer than the Postgres row's updated_at. A missing
 *    updatedAt never overwrites an existing row. A first insert (no Postgres row)
 *    is allowed. Stale snapshots are skipped, not applied.
 * 3. Dead-Letter Queue (DLQ) logging on unrecoverable failures and when the
 *    writer origin cannot be determined (those rows are not guessed).
 */

const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');

// Resolve Supabase config from environment or Firebase functions config
function getSupabaseConfig() {
  const url = process.env.SUPABASE_URL || process.env.STAGING_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SECRET_KEY;
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

const APPOINTMENT_SYNC_ORIGINS = new Set([
  'patient_supabase',
  'patient_firestore',
  'doctor_firestore',
]);

/**
 * doctors.experience_years is NOT NULL DEFAULT 1. A missing Firestore value is
 * omitted so insert uses that default and update does not overwrite a real value.
 */
function experienceYearsFromDoctorDoc(after) {
  const n = optionalFiniteNumber(after?.experienceYears ?? after?.yearsExperience);
  if (n === undefined) return undefined;
  return Math.trunc(n);
}

/**
 * patients.age is nullable. patients.mobile is NOT NULL with no default.
 * Missing mobile must not be invented; the caller dead-letters and skips the insert.
 */
function firstText(...values) {
  for (const value of values) {
    if (value == null) continue;
    const text = String(value).trim();
    if (text) return text;
  }
  return undefined;
}

function putText(target, key, ...values) {
  const text = firstText(...values);
  if (text !== undefined) target[key] = text;
}

function putBooleanIfPresent(target, key, value) {
  if (typeof value === 'boolean') target[key] = value;
}

function placeholderPatientPayload(patientId, docData, fallbackData = {}) {
  const rawMobile = docData?.mobile || fallbackData.mobile || fallbackData.patientMobile || '';
  const mobile = String(rawMobile).replace(/\D/g, '');
  if (!mobile) {
    return { skip: true, reason: 'patient_mobile_missing' };
  }
  // patients.name is NOT NULL with no default. Do not invent a name.
  const name = firstText(docData?.name, fallbackData.patientName);
  if (!name) {
    return { skip: true, reason: 'patient_name_missing' };
  }
  const patient = {
    patient_id: patientId,
    name,
    mobile,
  };
  // patients.gender is nullable. Omit it unless it is already a legal value.
  const genderVal = firstText(docData?.gender, fallbackData.patientGender);
  if (genderVal && ['Male', 'Female', 'Other'].includes(genderVal)) {
    patient.gender = genderVal;
  }
  const createdAt = toIsoTimestamp(docData?.createdAt);
  if (createdAt) patient.created_at = createdAt;
  const age = optionalFiniteNumber(docData?.age ?? fallbackData.patientAge);
  if (age !== undefined) patient.age = Math.trunc(age);
  return { skip: false, patient };
}

/**
 * doctors.name/email/mobile/specialization/qualification are NOT NULL with no
 * default. Missing ones skip the sync. Columns with defaults are omitted.
 */
function buildDoctorSupabasePayload(doctorId, after) {
  const doc = after || {};
  const name = firstText(doc.name, doc.fullName);
  const email = firstText(doc.email);
  const mobile = firstText(doc.mobile, doc.phone);
  const specialization = firstText(
    doc.specialization,
    Array.isArray(doc.specializations) ? doc.specializations[0] : undefined,
  );
  const qualification = firstText(
    doc.qualification,
    Array.isArray(doc.degrees) && doc.degrees.length > 0 ? doc.degrees.join(', ') : undefined,
  );
  const missing = [];
  if (!name) missing.push('name');
  if (!email) missing.push('email');
  if (!mobile) missing.push('mobile');
  if (!specialization) missing.push('specialization');
  if (!qualification) missing.push('qualification');
  if (missing.length > 0) {
    return { skip: true, reason: `doctor_required_missing:${missing.join(',')}` };
  }
  const doctor = {
    doctor_id: doctorId,
    name,
    email: email.toLowerCase(),
    mobile,
    specialization,
    qualification,
  };
  putText(doctor, 'super_specialization', doc.superSpecialization);
  const fee = optionalFiniteNumber(doc.consultationFee);
  if (fee !== undefined) doctor.consultation_fee = fee;
  putText(doctor, 'clinic_name', doc.clinicName);
  putText(doctor, 'area', doc.area);
  putText(doctor, 'city', doc.city);
  putText(doctor, 'state', doc.state);
  putText(doctor, 'country', doc.country);
  putText(doctor, 'pincode', doc.pincode);
  putText(doctor, 'address_line1', doc.addressLine1);
  putText(doctor, 'address_line2', doc.addressLine2);
  putText(doctor, 'state_council', doc.stateCouncil);
  putText(doctor, 'council_number', doc.councilNumber);
  if (Array.isArray(doc.certifications)) doctor.certifications = toStringArray(doc.certifications, []);
  if (Array.isArray(doc.pastWorkplaces)) doctor.past_workplaces = toStringArray(doc.pastWorkplaces, []);
  if (Array.isArray(doc.memberships)) doctor.memberships = toStringArray(doc.memberships, []);
  if (Array.isArray(doc.awards)) doctor.awards = toStringArray(doc.awards, []);
  if (Array.isArray(doc.publications)) doctor.publications = toStringArray(doc.publications, []);
  putText(doctor, 'about', doc.about);
  if (Array.isArray(doc.languages)) doctor.languages = toStringArray(doc.languages, []);
  putText(doctor, 'photo_url', doc.photoUrl, doc.photoURL);
  putText(doctor, 'maps_link', doc.mapsLink, doc.mapsUrl);
  putText(doctor, 'landmark', doc.landmark);
  const rating = optionalFiniteNumber(doc.rating);
  if (rating !== undefined) doctor.rating = rating;
  const reviewCount = optionalFiniteNumber(doc.reviewCount);
  if (reviewCount !== undefined) doctor.review_count = Math.trunc(reviewCount);
  putBooleanIfPresent(doctor, 'profile_completed', doc.profileCompleted);
  putBooleanIfPresent(doctor, 'verified', doc.verified);
  const verifiedAt = toIsoTimestamp(doc.verifiedAt);
  if (verifiedAt) doctor.verified_at = verifiedAt;
  putBooleanIfPresent(doctor, 'deactivated', doc.deactivated);
  const deactivatedAt = toIsoTimestamp(doc.deactivatedAt);
  if (deactivatedAt) doctor.deactivated_at = deactivatedAt;
  const reactivateBefore = toIsoTimestamp(doc.reactivateBefore);
  if (reactivateBefore) doctor.reactivate_before = reactivateBefore;
  const reactivatedAt = toIsoTimestamp(doc.reactivatedAt);
  if (reactivatedAt) doctor.reactivated_at = reactivatedAt;
  putText(doctor, 'fcm_token', doc.fcmToken);
  const fcmUpdated = toIsoTimestamp(doc.fcmTokenUpdatedAt);
  if (fcmUpdated) doctor.fcm_token_updated_at = fcmUpdated;
  const createdAt = toIsoTimestamp(doc.createdAt);
  if (createdAt) doctor.created_at = createdAt;
  const updatedAt = toIsoTimestamp(doc.updatedAt);
  if (updatedAt) doctor.updated_at = updatedAt;
  return { skip: false, doctor };
}

function buildMedicalStoreSupabasePayload(storeId, docData, fallbackData = {}) {
  const doc = docData || {};
  const storeName = firstText(doc.storeName, fallbackData.storeName);
  const ownerName = firstText(doc.ownerName, fallbackData.ownerName);
  const license = firstText(doc.drugLicenseNumber, doc.licenseNumber, fallbackData.drugLicenseNumber);
  const phone = firstText(doc.phone, fallbackData.phone);
  const email = firstText(doc.email, fallbackData.email);
  const missing = [];
  if (!storeName) missing.push('store_name');
  if (!ownerName) missing.push('owner_name');
  if (!license) missing.push('drug_license_number');
  if (!phone) missing.push('phone');
  if (!email) missing.push('email');
  if (missing.length > 0) {
    return { skip: true, reason: `medical_store_required_missing:${missing.join(',')}` };
  }
  const store = {
    store_id: storeId,
    store_name: storeName,
    owner_name: ownerName,
    drug_license_number: license,
    phone,
    email: email.toLowerCase(),
  };
  putText(store, 'city', doc.city, doc.address && doc.address.city);
  putText(store, 'state', doc.state, doc.address && doc.address.state);
  putText(store, 'country', doc.country, doc.address && doc.address.country);
  putText(store, 'gst_number', doc.gstNumber);
  putText(store, 'address_line1', doc.addressLine1, doc.address && doc.address.addressLine1);
  putText(store, 'address_line2', doc.addressLine2, doc.address && doc.address.addressLine2);
  putText(store, 'pincode', doc.pincode, doc.address && (doc.address.pinCode || doc.address.pincode));
  const ownerUid = toValidUuid(doc.ownerUid);
  if (ownerUid) store.owner_uid = ownerUid;
  putBooleanIfPresent(store, 'profile_completed', doc.profileCompleted);
  putBooleanIfPresent(store, 'verified', doc.verified);
  putBooleanIfPresent(store, 'deactivated', doc.deactivated);
  const verifiedAt = toIsoTimestamp(doc.verifiedAt);
  if (verifiedAt) store.verified_at = verifiedAt;
  const createdAt = toIsoTimestamp(doc.createdAt);
  if (createdAt) store.created_at = createdAt;
  const updatedAt = toIsoTimestamp(doc.updatedAt);
  if (updatedAt) store.updated_at = updatedAt;
  return { skip: false, store };
}

function buildLabSupabasePayload(labId, docData, fallbackData = {}) {
  const doc = docData || {};
  const labName = firstText(doc.labName, fallbackData.labName);
  const license = firstText(doc.licenseNumber, fallbackData.licenseNumber);
  const phone = firstText(doc.phone, fallbackData.phone);
  const email = firstText(doc.email, fallbackData.email);
  const missing = [];
  if (!labName) missing.push('lab_name');
  if (!license) missing.push('license_number');
  if (!phone) missing.push('phone');
  if (!email) missing.push('email');
  if (missing.length > 0) {
    return { skip: true, reason: `lab_required_missing:${missing.join(',')}` };
  }
  const lab = {
    lab_id: labId,
    lab_name: labName,
    license_number: license,
    phone,
    email: email.toLowerCase(),
  };
  putText(lab, 'city', doc.city);
  putText(lab, 'state', doc.state);
  putText(lab, 'country', doc.country);
  const rating = optionalFiniteNumber(doc.rating);
  if (rating !== undefined) lab.rating = rating;
  const createdAt = toIsoTimestamp(doc.createdAt);
  if (createdAt) lab.created_at = createdAt;
  const updatedAt = toIsoTimestamp(doc.updatedAt);
  if (updatedAt) lab.updated_at = updatedAt;
  return { skip: false, lab };
}

function buildAmbulanceSupabasePayload(ambulanceId, docData, fallbackData = {}) {
  const doc = docData || {};
  const fallback = fallbackData || {};
  const serviceName = firstText(doc.serviceName, fallback.serviceName);
  const driverName = firstText(doc.driverName, fallback.driverName);
  const phone = firstText(doc.phone, fallback.phone);
  const vehicleNumber = firstText(doc.vehicleNumber, fallback.vehicleNumber);
  const city = firstText(doc.city, doc.address && doc.address.city, fallback.city);
  const ambulanceType = firstText(doc.ambulanceType, fallback.ambulanceType);
  const legalType = ['bls', 'als', 'icu', 'patientTransport'].includes(ambulanceType) ? ambulanceType : undefined;
  const missing = [];
  if (!serviceName) missing.push('service_name');
  if (!driverName) missing.push('driver_name');
  if (!phone) missing.push('phone');
  if (!vehicleNumber) missing.push('vehicle_number');
  if (!legalType) missing.push('ambulance_type');
  if (!city) missing.push('city');
  if (missing.length > 0) {
    return { skip: true, reason: `ambulance_required_missing:${missing.join(',')}` };
  }
  const ambulance = {
    ambulance_id: ambulanceId,
    service_name: serviceName,
    driver_name: driverName,
    phone,
    vehicle_number: vehicleNumber,
    ambulance_type: legalType,
    city,
  };
  putText(ambulance, 'owner_name', doc.ownerName);
  putText(ambulance, 'username', doc.username);
  if (ambulance.username) ambulance.username = ambulance.username.toLowerCase();
  putText(ambulance, 'base_address', doc.baseAddress);
  putText(ambulance, 'state', doc.state, doc.address && doc.address.state);
  putText(ambulance, 'country', doc.country, doc.address && doc.address.country);
  putBooleanIfPresent(ambulance, 'has_oxygen', doc.hasOxygen);
  putBooleanIfPresent(ambulance, 'has_ventilator', doc.hasVentilator);
  putBooleanIfPresent(ambulance, 'has_stretcher', doc.hasStretcher);
  putBooleanIfPresent(ambulance, 'is_24x7', doc.is24x7);
  putBooleanIfPresent(ambulance, 'is_available', doc.isAvailable);
  putBooleanIfPresent(ambulance, 'verified', doc.verified);
  const createdAt = toIsoTimestamp(doc.createdAt);
  if (createdAt) ambulance.created_at = createdAt;
  const updatedAt = toIsoTimestamp(doc.updatedAt);
  if (updatedAt) ambulance.updated_at = updatedAt;
  const authUid = toValidUuid(doc.authUid);
  if (authUid) ambulance.auth_uid = authUid;
  return { skip: false, ambulance };
}

// New broadcasts are written with status 'pending'.
// frontend/lib/core/firebase/repositories/ambulance_repository.dart:501
function ambulanceBroadcastStatus(raw) {
  const value = firstText(raw) || 'pending';
  return ['pending', 'accepted', 'completed', 'cancelled'].includes(value) ? value : 'pending';
}

// New driver requests are written with status 'pending'.
// frontend/lib/core/firebase/repositories/ambulance_repository.dart:523
function ambulanceRequestStatus(raw) {
  const value = firstText(raw) || 'pending';
  return ['pending', 'taken', 'accepted', 'cancelled'].includes(value) ? value : 'pending';
}

// New invites are written with status pending.
// frontend/lib/core/invite/ambulance_invite_service.dart:68
function ambulanceInviteStatus(raw) {
  const value = firstText(raw) || 'pending';
  if (value === 'expired') return 'cancelled';
  return ['pending', 'completed', 'cancelled'].includes(value) ? value : 'pending';
}

function buildAmbulanceBroadcastSupabasePayload(broadcastId, docData, fallbackData = {}) {
  const doc = docData || {};
  const fallback = fallbackData || {};
  const patientId = firstText(doc.patientId, fallback.patientId);
  const patientName = firstText(doc.patientName, fallback.patientName);
  const pickup = firstText(doc.pickupLocation, fallback.pickupLocation);
  const drop = firstText(doc.dropLocation, fallback.dropLocation);
  const phone = firstText(doc.contactPhone, fallback.contactPhone);
  const missing = [];
  if (!patientId) missing.push('patient_id');
  if (!patientName) missing.push('patient_name');
  if (!pickup) missing.push('pickup_location');
  if (!drop) missing.push('drop_location');
  if (!phone) missing.push('contact_phone');
  if (missing.length > 0) {
    return { skip: true, reason: `ambulance_broadcast_required_missing:${missing.join(',')}` };
  }
  return {
    skip: false,
    row: {
      broadcast_id: broadcastId,
      patient_id: patientId,
      patient_name: patientName,
      pickup_location: pickup,
      drop_location: drop,
      contact_phone: phone,
      status: ambulanceBroadcastStatus(doc.status || fallback.status),
    },
  };
}

function buildAmbulanceRequestSupabasePayload(requestId, docData) {
  const doc = docData || {};
  const broadcastId = firstText(doc.broadcastId);
  const driverId = firstText(doc.driverId);
  const patientId = firstText(doc.patientId);
  const patientName = firstText(doc.patientName);
  const pickup = firstText(doc.pickupLocation);
  const drop = firstText(doc.dropLocation);
  const phone = firstText(doc.contactPhone);
  const missing = [];
  if (!broadcastId) missing.push('broadcast_id');
  if (!driverId) missing.push('driver_id');
  if (!patientId) missing.push('patient_id');
  if (!patientName) missing.push('patient_name');
  if (!pickup) missing.push('pickup_location');
  if (!drop) missing.push('drop_location');
  if (!phone) missing.push('contact_phone');
  if (missing.length > 0) {
    return { skip: true, reason: `ambulance_request_required_missing:${missing.join(',')}` };
  }
  return {
    skip: false,
    row: {
      request_id: requestId,
      broadcast_id: broadcastId,
      driver_id: driverId,
      patient_id: patientId,
      patient_name: patientName,
      pickup_location: pickup,
      drop_location: drop,
      contact_phone: phone,
      status: ambulanceRequestStatus(doc.status),
    },
  };
}

function buildAmbulanceInviteSupabasePayload(inviteId, docData) {
  const doc = docData || {};
  const doctorId = firstText(doc.doctorId);
  const ambulanceId = firstText(doc.ambulanceId);
  const serviceName = firstText(doc.serviceName);
  const driverName = firstText(doc.driverName);
  const phone = firstText(doc.phone);
  const token = firstText(doc.token);
  const missing = [];
  if (!doctorId) missing.push('doctor_id');
  if (!ambulanceId) missing.push('ambulance_id');
  if (!serviceName) missing.push('service_name');
  if (!driverName) missing.push('driver_name');
  if (!phone) missing.push('phone');
  if (!token) missing.push('token');
  if (missing.length > 0) {
    return { skip: true, reason: `ambulance_invite_required_missing:${missing.join(',')}` };
  }
  return {
    skip: false,
    row: {
      invite_id: inviteId,
      token,
      doctor_id: doctorId,
      ambulance_id: ambulanceId,
      service_name: serviceName,
      driver_name: driverName,
      phone,
      status: ambulanceInviteStatus(doc.status),
    },
  };
}

function buildAvailabilitySupabasePayload(doctorId, after) {
  const doc = after || {};
  const payload = { doctor_id: doctorId };
  if (Array.isArray(doc.workingDays)) payload.working_days = toStringArray(doc.workingDays, []);
  putText(payload, 'morning_start', doc.morningStart);
  putText(payload, 'morning_end', doc.morningEnd);
  putBooleanIfPresent(payload, 'evening_enabled', doc.eveningEnabled);
  putText(payload, 'evening_start', doc.eveningStart);
  putText(payload, 'evening_end', doc.eveningEnd);
  const slot = optionalFiniteNumber(doc.slotDurationMins);
  if (slot !== undefined) payload.slot_duration_mins = Math.trunc(slot);
  const maxPatients = optionalFiniteNumber(doc.maxPatientsPerDay);
  if (maxPatients !== undefined) payload.max_patients_per_day = Math.trunc(maxPatients);
  putBooleanIfPresent(payload, 'break_enabled', doc.breakEnabled);
  putText(payload, 'break_start', doc.breakStart);
  putText(payload, 'break_end', doc.breakEnd);
  const leaveStart = toIsoTimestamp(doc.leaveStart);
  if (leaveStart) payload.leave_start = leaveStart;
  const leaveEnd = toIsoTimestamp(doc.leaveEnd);
  if (leaveEnd) payload.leave_end = leaveEnd;
  const updatedAt = toIsoTimestamp(doc.updatedAt);
  if (updatedAt) payload.updated_at = updatedAt;
  return payload;
}

async function pgMergeUpsert(pool, table, payload, conflictColumn) {
  const entries = Object.entries(payload).filter(([, value]) => value !== undefined);
  if (entries.length === 0) return;
  const cols = entries.map(([key]) => key);
  const values = entries.map(([, value]) => value);
  const placeholders = cols.map((_, index) => `$${index + 1}`).join(', ');
  const updates = cols
    .filter((col) => col !== conflictColumn && col !== 'created_at')
    .map((col) => `${col} = EXCLUDED.${col}`);
  const action = updates.length > 0 ? `DO UPDATE SET ${updates.join(', ')}` : 'DO NOTHING';
  await pool.query(
    `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${placeholders}) ON CONFLICT (${conflictColumn}) ${action}`,
    values,
  );
}

/** Finite number, or undefined when the Firestore field is absent. Zero is kept. */
function optionalFiniteNumber(value) {
  if (value === undefined || value === null || value === '') return undefined;
  const n = typeof value === 'number' ? value : Number(String(value).trim());
  if (!Number.isFinite(n)) return undefined;
  return n;
}

function firestoreTimestampMs(value) {
  if (value == null || value === '') return null;
  if (typeof value.toDate === 'function') {
    const ms = value.toDate().getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === 'object' && Number.isFinite(value._seconds)) {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

/**
 * Writer origin already stored on the Firestore document.
 * Returns null when the document does not say who wrote it — callers must skip.
 */
function resolveWriterSyncOrigin(doc) {
  if (!doc || typeof doc !== 'object') return null;
  const explicit = String(doc.syncOrigin || doc.sync_origin || '').trim();
  if (APPOINTMENT_SYNC_ORIGINS.has(explicit)) return explicit;

  const syncedBy = String(doc.syncedBy || '').trim().toLowerCase();
  if (syncedBy === 'patient' || syncedBy === 'patient_client') return 'patient_firestore';
  if (syncedBy === 'doctor' || syncedBy === 'doctor_client') return 'doctor_firestore';

  const createdBy = String(doc.createdBy || doc.writerRole || doc.bookedByRole || '').trim().toLowerCase();
  if (createdBy === 'patient') return 'patient_firestore';
  if (createdBy === 'doctor') return 'doctor_firestore';

  const source = String(doc.source || '').trim().toLowerCase();
  if (source === 'walkin') return 'doctor_firestore';
  if (source === 'patient' || source === 'patient_app') return 'patient_firestore';
  return null;
}

function buildAppointmentSupabasePayload(after, appointmentId, syncOrigin) {
  const doctorName = firstText(after.doctorName);
  const patientName = firstText(after.patientName);
  if (!doctorName || !patientName) {
    const missing = [];
    if (!doctorName) missing.push('doctor_name');
    if (!patientName) missing.push('patient_name');
    console.warn(JSON.stringify({
      severity: 'WARNING',
      event: 'SYNC_BRIDGE_PAYLOAD_VALIDATION_FAILED',
      entityType: 'appointment',
      entityId: appointmentId,
      documentPath: `appointments/${appointmentId}`,
      missingFields: missing,
    }));
    return { skip: true, reason: `appointment_required_missing:${missing.join(',')}` };
  }

  const dateTimeRaw = after.dateTime;
  const dateTimeIso = dateTimeRaw?.toDate?.()
    ? dateTimeRaw.toDate().toISOString()
    : (dateTimeRaw ? toIsoTimestamp(dateTimeRaw) : undefined);

  const payload = {
    appointment_id: appointmentId,
    doctor_name: doctorName,
    patient_name: patientName,
    has_prescription: Boolean(after.hasPrescription),
    sync_origin: syncOrigin,
    synced_by: 'firestore_cloud_function',
  };

  putText(payload, 'doctor_id', after.doctorId);
  putText(payload, 'patient_id', after.patientId);
  putText(payload, 'specialization', after.specialization);
  putText(payload, 'patient_gender', after.patientGender);
  if (dateTimeIso) payload.date_time = dateTimeIso;
  putText(payload, 'visit_type', after.visitType);
  putText(payload, 'patient_status', after.patientStatus);
  putText(payload, 'doctor_status', after.doctorStatus);
  putText(payload, 'clinic_name', after.clinicName);
  putText(payload, 'clinic_address', after.clinicAddress);
  putText(payload, 'cancellation_reason', after.cancellationReason);
  putText(payload, 'diagnosis', after.diagnosis);

  const age = optionalFiniteNumber(after.patientAge);
  if (age !== undefined) payload.patient_age = age;
  const token = optionalFiniteNumber(after.tokenNumber);
  if (token !== undefined) payload.token_number = token;
  if (typeof after.slotLabel === 'string' && after.slotLabel.trim()) {
    payload.slot_label = after.slotLabel.trim();
  }
  const updatedMs = firestoreTimestampMs(after.updatedAt);
  if (updatedMs != null) payload.updated_at = new Date(updatedMs).toISOString();
  return payload;
}

async function readRemoteUpdatedAtMs({ url, key, pool, table, idColumn, id }) {
  if (!/^[a-z_]+$/.test(table) || !/^[a-z_]+$/.test(idColumn)) {
    throw new Error('Unsupported compare-and-skip target');
  }
  if (url && key) {
    const endpoint = `${url.replace(/\/+$/, '')}/rest/v1/${table}?${idColumn}=eq.${encodeURIComponent(id)}&select=updated_at&limit=1`;
    const resp = await fetch(endpoint, {
      method: 'GET',
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
    });
    if (!resp.ok) {
      throw new Error(`compare-and-skip read failed (${resp.status})`);
    }
    const rows = await resp.json();
    if (!Array.isArray(rows) || rows.length === 0 || rows[0].updated_at == null) return null;
    const ms = Date.parse(rows[0].updated_at);
    return Number.isNaN(ms) ? null : ms;
  }
  if (pool) {
    const result = await pool.query(
      `SELECT updated_at FROM ${table} WHERE ${idColumn} = $1 LIMIT 1`,
      [id],
    );
    if (!result.rows || result.rows.length === 0 || result.rows[0].updated_at == null) return null;
    const ms = new Date(result.rows[0].updated_at).getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

async function upsertMergeRow(pool, table, conflictColumn, payload) {
  if (!/^[a-z_]+$/.test(table) || !/^[a-z_]+$/.test(conflictColumn)) {
    throw new Error('Unsupported upsert target');
  }
  const cols = Object.keys(payload).filter((col) => /^[a-z_]+$/.test(col));
  if (!cols.includes(conflictColumn)) throw new Error('Upsert payload missing conflict column');
  const assignments = cols
    .filter((col) => col !== conflictColumn && col !== 'id' && col !== 'created_at')
    .map((col) => `${col} = EXCLUDED.${col}`);
  const action = assignments.length > 0 ? `DO UPDATE SET ${assignments.join(', ')}` : 'DO NOTHING';
  const sql = `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) ON CONFLICT (${conflictColumn}) ${action}`;
  await pool.query(sql, cols.map((col) => payload[col]));
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

  const syncOrigin = resolveWriterSyncOrigin(after);
  if (!syncOrigin) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'appointment',
      entityId: appointmentId,
      payload: { reason: 'origin_undetermined' },
      errorMessage: 'Skipped sync: appointment writer origin could not be determined from the document.',
    });
    return;
  }

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping sync.');
    return;
  }

  const localMs = firestoreTimestampMs(after.updatedAt);
  let remoteMs = null;
  try {
    remoteMs = await readRemoteUpdatedAtMs({
      url,
      key,
      pool,
      table: 'appointments',
      idColumn: 'appointment_id',
      id: appointmentId,
    });
  } catch (err) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'appointment',
      entityId: appointmentId,
      payload: { reason: 'compare_and_skip_read_failed' },
      errorMessage: err.message,
      errorStack: err.stack,
    });
    return;
  }
  if (remoteMs != null && (localMs == null || localMs <= remoteMs)) {
    console.info(`[SyncBridge] Skipping stale appointment snapshot ${appointmentId}`);
    return;
  }

  const supabasePayload = buildAppointmentSupabasePayload(after, appointmentId, syncOrigin);
  if (supabasePayload.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'appointment',
      entityId: appointmentId,
      payload: { reason: supabasePayload.reason },
      errorMessage: `Skipped appointment sync: ${supabasePayload.reason}`,
    });
    return;
  }
  if (!supabasePayload.updated_at && remoteMs == null) {
    supabasePayload.updated_at = new Date().toISOString();
  }

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
          await upsertMergeRow(pool, 'appointments', 'appointment_id', supabasePayload);
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

  const prescriptionDoctorId = firstText(after.doctorId);
  const prescriptionPatientId = firstText(after.patientId);
  const prescriptionPatientName = firstText(after.patientName);
  const prescriptionAge = optionalFiniteNumber(after.patientAge);
  if (!prescriptionDoctorId || !prescriptionPatientId || !prescriptionPatientName || prescriptionAge === undefined) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'prescription',
      entityId: prescriptionId,
      payload: { prescription_id: prescriptionId },
      errorMessage: 'Skipped prescription sync: doctor_id, patient_id, patient_name, and patient_age are required.',
      retryCount: 0,
    });
    return;
  }
  const prescriptionPayload = {
    prescription_id: prescriptionId,
    doctor_id: prescriptionDoctorId,
    patient_id: prescriptionPatientId,
    patient_name: prescriptionPatientName,
    patient_age: Math.trunc(prescriptionAge),
    // This trigger only runs for a Firestore prescription write from the doctor app.
    sync_origin: 'doctor_firestore',
    synced_by: 'firestore_cloud_function',
  };
  putText(prescriptionPayload, 'appointment_id', after.appointmentId);
  putText(prescriptionPayload, 'doctor_name', after.doctorName);
  const prescriptionGender = firstText(after.patientGender);
  if (prescriptionGender && ['Male', 'Female', 'Other'].includes(prescriptionGender)) {
    prescriptionPayload.patient_gender = prescriptionGender;
  }
  putText(prescriptionPayload, 'primary_diagnosis', after.primaryDiagnosis, after.diagnosis);
  putText(prescriptionPayload, 'general_advice', after.generalAdvice);
  const prescriptionUpdatedAt = toIsoTimestamp(after.updatedAt);
  if (prescriptionUpdatedAt) prescriptionPayload.updated_at = prescriptionUpdatedAt;

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
          const medRows = medicines.flatMap((m, idx) => {
            const name = firstText(m.name, m.medicineName);
            const dosage = firstText(m.dosage);
            const form = firstText(m.form);
            const frequency = firstText(m.frequency);
            const quantity = firstText(m.quantity);
            const duration = firstText(m.duration);
            if (!name || !dosage || !form || !frequency || !quantity || !duration) {
              return [];
            }
            const row = {
              prescription_id: prescriptionId,
              medicine_entry_id: `${prescriptionId}_med_${idx}`,
              name,
              dosage,
              form,
              frequency,
              quantity,
              duration,
            };
            putText(row, 'instructions', m.instructions, m.timing);
            return [row];
          });

          if (medRows.length === 0) return;
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

  const builtDoctor = buildDoctorSupabasePayload(doctorId, docData);
  if (builtDoctor.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'doctor',
      entityId: doctorId,
      payload: { doctor_id: doctorId },
      errorMessage: `Skipped doctor placeholder: ${builtDoctor.reason}`,
      retryCount: 0,
    });
    return;
  }
  const placeholderDoctor = builtDoctor.doctor;

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
      await pgMergeUpsert(pool, 'doctors', placeholderDoctor, 'doctor_id');
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
    degree: String(firstText(item.degree, item.title, qualification) || '').slice(0, 128),
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

  const builtDoctor = buildDoctorSupabasePayload(doctorId, after);
  if (builtDoctor.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'doctor',
      entityId: doctorId,
      payload: { doctor_id: doctorId },
      errorMessage: `Skipped doctor sync: ${builtDoctor.reason}`,
      retryCount: 0,
    });
    return;
  }
  const doctorPayload = builtDoctor.doctor;
  const experienceYears = experienceYearsFromDoctorDoc(after);
  if (experienceYears !== undefined) doctorPayload.experience_years = experienceYears;

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
          await pgMergeUpsert(pool, 'doctors', doctorPayload, 'doctor_id');
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

  const availabilityPayload = buildAvailabilitySupabasePayload(doctorId, after);

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
          await pgMergeUpsert(pool, 'doctor_availability', availabilityPayload, 'doctor_id');
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

  const builtStore = buildMedicalStoreSupabasePayload(storeId, docData, fallbackData);
  if (builtStore.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'medical_store',
      entityId: storeId,
      payload: { store_id: storeId },
      errorMessage: `Skipped medical store placeholder: ${builtStore.reason}`,
      retryCount: 0,
    });
    return;
  }
  const placeholderStore = builtStore.store;

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
      await pgMergeUpsert(pool, 'medical_stores', placeholderStore, 'store_id');
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

  const builtLab = buildLabSupabasePayload(labId, docData, fallbackData);
  if (builtLab.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab',
      entityId: labId,
      payload: { lab_id: labId },
      errorMessage: `Skipped lab placeholder: ${builtLab.reason}`,
      retryCount: 0,
    });
    return;
  }
  const placeholderLab = builtLab.lab;

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
      await pgMergeUpsert(pool, 'labs', placeholderLab, 'lab_id');
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

  const built = placeholderPatientPayload(patientId, docData, fallbackData);
  if (built.skip) {
    // patients.mobile is NOT NULL and has no default. Do not invent a number.
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'patient',
      entityId: patientId,
      payload: { reason: built.reason },
      errorMessage: `Skipped patient placeholder: ${built.reason}`,
    });
    return;
  }
  const placeholderPatient = built.patient;

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
        placeholderPatient.age ?? null,
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

  const doctorId = firstText(docData?.doctorId, fallbackData.doctorId);
  const patientId = firstText(docData?.patientId, fallbackData.patientId);
  const patientName = firstText(docData?.patientName, fallbackData.patientName);
  const patientAge = optionalFiniteNumber(docData?.patientAge ?? fallbackData.patientAge);
  if (!doctorId || !patientId || !patientName || patientAge === undefined) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'prescription',
      entityId: prescriptionId,
      payload: { prescription_id: prescriptionId },
      errorMessage: 'Skipped prescription placeholder: doctor_id, patient_id, patient_name, and patient_age are required.',
      retryCount: 0,
    });
    return;
  }

  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensurePatientExistsInPostgres(patientId, fallbackData, { url, key, pool });

  const placeholderPrescription = {
    prescription_id: prescriptionId,
    doctor_id: doctorId,
    patient_id: patientId,
    patient_name: patientName,
    patient_age: Math.trunc(patientAge),
  };
  putText(placeholderPrescription, 'doctor_name', docData?.doctorName, fallbackData.doctorName);
  putText(placeholderPrescription, 'primary_diagnosis', docData?.primaryDiagnosis, docData?.diagnosis);
  const prescriptionCreatedAt = toIsoTimestamp(docData?.createdAt);
  if (prescriptionCreatedAt) placeholderPrescription.created_at = prescriptionCreatedAt;

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
        INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (prescription_id) DO NOTHING;
      `, [
        placeholderPrescription.prescription_id,
        placeholderPrescription.doctor_id,
        placeholderPrescription.patient_id,
        placeholderPrescription.patient_name,
        placeholderPrescription.patient_age,
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
  const medicineRows = medList.flatMap((m) => {
    const entryId = firstText(m.medicineEntryId, m.id);
    if (!entryId) return [];
    const row = {
      delivery_id: deliveryId,
      medicine_entry_id: entryId,
    };
    // New dispense lines start as pending.
    // frontend/lib/features/pharmacy/models/pharmacy_models.dart:117
    const availability = firstText(m.availability) || 'pending';
    if (['pending', 'available', 'outOfStock', 'substituted'].includes(availability)) {
      row.availability = availability;
    }
    putText(row, 'substitute_name', m.substituteName);
    return [row];
  });

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

  const builtStore = buildMedicalStoreSupabasePayload(storeId, after);
  if (builtStore.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'medical_store',
      entityId: storeId,
      payload: { store_id: storeId },
      errorMessage: `Skipped medical store sync: ${builtStore.reason}`,
      retryCount: 0,
    });
    return;
  }
  const storePayload = builtStore.store;

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
          await pgMergeUpsert(pool, 'medical_stores', storePayload, 'store_id');
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
  const doctorName = firstText(after.doctorName);
  const storeName = firstText(after.storeName);

  if (!doctorId || !storeId || !doctorName || !storeName) {
    const missing = [];
    if (!doctorId) missing.push('doctor_id');
    if (!storeId) missing.push('medical_store_id');
    if (!doctorName) missing.push('doctor_name');
    if (!storeName) missing.push('store_name');
    console.warn(JSON.stringify({
      severity: 'WARNING',
      event: 'SYNC_BRIDGE_PAYLOAD_VALIDATION_FAILED',
      entityType: 'pharmacy_connection',
      entityId: connectionId,
      documentPath: `pharmacy_connections/${connectionId}`,
      missingFields: missing,
    }));
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'pharmacy_connection',
      entityId: connectionId,
      payload: { connection_id: connectionId },
      errorMessage: `Skipped pharmacy connection sync: ${missing.join(', ')} required.`,
      retryCount: 0,
    });
    return;
  }

  // Self-healing foreign keys
  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensureMedicalStoreExistsInPostgres(storeId, { storeName }, { url, key, pool });

  const rawStatus = after.status || 'pending';
  const status = ['pending', 'active', 'rejected', 'removed'].includes(rawStatus) ? rawStatus : 'pending';
  const rawReqBy = after.requestedBy || 'doctor';
  const requestedBy = ['doctor', 'store'].includes(rawReqBy) ? rawReqBy : 'doctor';

  const connectionPayload = {
    connection_id: connectionId,
    doctor_id: doctorId,
    medical_store_id: storeId,
    doctor_name: doctorName,
    store_name: storeName,
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

  const prescriptionId = firstText(after.prescriptionId);
  const doctorId = firstText(after.doctorId);
  const storeId = firstText(after.storeId, after.medicalStoreId);
  const patientId = firstText(after.patientId, after.draft && after.draft.patientId);
  const doctorName = firstText(after.doctorName);
  const storeName = firstText(after.storeName);
  const patientName = firstText(after.patientName);
  if (!prescriptionId || !doctorId || !storeId || !patientId || !doctorName || !storeName || !patientName) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'pharmacy_delivery',
      entityId: deliveryId,
      payload: { delivery_id: deliveryId },
      errorMessage: 'Skipped pharmacy delivery: prescription, doctor, store, patient, and their names are required.',
      retryCount: 0,
    });
    return;
  }

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

  // New deliveries are constructed with status sent.
  // frontend/lib/features/pharmacy/models/pharmacy_models.dart:143
  const rawStatus = firstText(after.status) || 'sent';
  const status = ['sent', 'viewed', 'partiallyDispensed', 'dispensed'].includes(rawStatus) ? rawStatus : 'sent';

  const deliveryPayload = {
    delivery_id: deliveryId,
    prescription_id: prescriptionId,
    doctor_id: doctorId,
    store_id: storeId,
    patient_id: patientId,
    doctor_name: doctorName,
    store_name: storeName,
    patient_name: patientName,
    status,
  };
  const sentAt = toIsoTimestamp(after.sentAt);
  if (sentAt) deliveryPayload.sent_at = sentAt;
  const viewedAt = toIsoTimestamp(after.viewedAt);
  if (viewedAt) deliveryPayload.viewed_at = viewedAt;
  const dispensedAt = toIsoTimestamp(after.dispensedAt);
  if (dispensedAt) deliveryPayload.dispensed_at = dispensedAt;
  putText(deliveryPayload, 'dispensing_notes', after.dispensingNotes);
  const medicineCount = optionalFiniteNumber(after.medicineCount);
  if (medicineCount !== undefined) {
    deliveryPayload.medicine_count = Math.trunc(medicineCount);
  } else if (Array.isArray(after.medicineLines)) {
    deliveryPayload.medicine_count = after.medicineLines.length;
  }
  if (after.draft) deliveryPayload.prescription_draft = after.draft;
  const deliveryUpdatedAt = toIsoTimestamp(after.updatedAt);
  if (deliveryUpdatedAt) deliveryPayload.updated_at = deliveryUpdatedAt;

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

  const builtLabSync = buildLabSupabasePayload(labId, after);
  if (builtLabSync.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab',
      entityId: labId,
      payload: { lab_id: labId },
      errorMessage: `Skipped lab sync: ${builtLabSync.reason}`,
      retryCount: 0,
    });
    return;
  }
  const labPayload = builtLabSync.lab;
  const labOwnerUid = toValidUuid(after.ownerUid);
  if (labOwnerUid) labPayload.owner_uid = labOwnerUid;
  putText(labPayload, 'gst_number', after.gstNumber);
  putText(labPayload, 'area', after.area);
  putText(labPayload, 'address_line1', after.addressLine1, after.address && after.address.addressLine1);
  putText(labPayload, 'address_line2', after.addressLine2, after.address && after.address.addressLine2);
  putText(labPayload, 'pincode', after.pincode, after.address && (after.address.pinCode || after.address.pincode));
  putBooleanIfPresent(labPayload, 'profile_completed', after.profileCompleted);
  putBooleanIfPresent(labPayload, 'verified', after.verified);
  putBooleanIfPresent(labPayload, 'deactivated', after.deactivated);
  const labVerifiedAt = toIsoTimestamp(after.verifiedAt);
  if (labVerifiedAt) labPayload.verified_at = labVerifiedAt;

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
          await pgMergeUpsert(pool, 'labs', labPayload, 'lab_id');
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
  const catalogSamples = ['blood', 'urine', 'swab', 'stool', 'other'];
  function catalogRow(id, doc) {
    const name = firstText(doc && doc.name);
    if (!id || !name) return { skip: true, reason: 'lab_catalog_name_missing' };
    const rawSample = firstText(doc.sampleType);
    if (rawSample && !catalogSamples.includes(rawSample)) {
      return { skip: true, reason: 'lab_catalog_sample_type_invalid' };
    }
    const row = { test_id: id, name };
    if (Array.isArray(doc.parameters)) {
      row.parameters = doc.parameters.map((item) => String(item || '').trim()).filter(Boolean);
    }
    if (typeof doc.fastingRequired === 'boolean') row.fasting_required = doc.fastingRequired;
    // Missing sampleType is omitted. lab_catalog_tests.sample_type defaults to blood,
    // matching the reader fallback in lab_catalog_repository.dart:179.
    if (rawSample) row.sample_type = rawSample;
    const hours = optionalFiniteNumber(doc.reportHours);
    if (hours !== undefined) row.report_hours = Math.trunc(hours);
    if (typeof doc.popular === 'boolean') row.popular = doc.popular;
    putText(row, 'category', doc.category);
    return { skip: false, row };
  }

  const rows = [];
  const skipped = [];
  if (Array.isArray(after.tests)) {
    for (const t of after.tests) {
      const built = catalogRow(firstText(t.id, t.testId), t);
      if (built.skip) skipped.push(built.reason);
      else rows.push(built.row);
    }
  } else {
    const built = catalogRow(testId, after);
    if (built.skip) skipped.push(built.reason);
    else rows.push(built.row);
  }

  if (skipped.length > 0) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_catalog_tests',
      entityId: testId,
      payload: { reason: skipped[0] },
      errorMessage: `Skipped lab catalog row: ${skipped[0]}`,
      retryCount: 0,
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
            await pgMergeUpsert(pool, 'lab_catalog_tests', row, 'test_id');
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

  const patientId = firstText(after.patientId);
  const patientName = firstText(after.patientName);
  const bookingAge = optionalFiniteNumber(after.patientAge);
  const testIds = Array.isArray(after.testIds)
    ? after.testIds.map((item) => String(item || '').trim()).filter(Boolean)
    : [];
  const testNames = Array.isArray(after.testNames)
    ? after.testNames.map((item) => String(item || '').trim()).filter(Boolean)
    : [];
  const testId = firstText(after.testId, testIds[0]);
  const testName = firstText(after.testName, testNames[0]);
  const slotLabel = firstText(after.slotLabel);
  const dateTime = toIsoTimestamp(after.dateTime);
  const collectionType = firstText(after.collectionType);
  const collectionOk = ['homeCollection', 'labVisit', 'walkIn'].includes(collectionType);
  const bookingStatuses = ['confirmed', 'sampleCollected', 'inAnalysis', 'completed', 'cancelled'];
  const rawBookingStatus = firstText(after.status);
  // Patient and walk-in bookings are created with status confirmed.
  // frontend/lib/core/firebase/repositories/lab_booking_repository.dart:109
  const status = rawBookingStatus
    ? (bookingStatuses.includes(rawBookingStatus) ? rawBookingStatus : undefined)
    : 'confirmed';
  const missing = [];
  if (!patientId) missing.push('patient_id');
  if (!patientName) missing.push('patient_name');
  if (bookingAge === undefined) missing.push('patient_age');
  if (!testId) missing.push('test_id');
  if (!testName) missing.push('test_name');
  if (testNames.length === 0 && !testName) missing.push('test_names');
  if (!collectionOk) missing.push('collection_type');
  if (!dateTime) missing.push('date_time');
  if (!slotLabel) missing.push('slot_label');
  if (!status) missing.push('status');
  if (missing.length > 0) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_booking',
      entityId: bookingId,
      payload: { reason: `lab_booking_required_missing:${missing.join(',')}` },
      errorMessage: `Skipped lab booking: ${missing.join(', ')} required.`,
      retryCount: 0,
    });
    return;
  }

  await ensurePatientExistsInPostgres(patientId, {
    patientName,
    patientAge: bookingAge,
    patientGender: after.patientGender,
  }, { url, key, pool });

  if (after.labId) {
    await ensureLabExistsInPostgres(after.labId, { labName: after.partnerLab }, { url, key, pool });
  }

  const bookingPayload = {
    booking_id: bookingId,
    patient_id: patientId,
    patient_name: patientName,
    patient_age: Math.trunc(bookingAge),
    test_id: testId,
    test_name: testName,
    test_names: testNames.length > 0 ? testNames : [testName],
    collection_type: collectionType,
    date_time: dateTime,
    slot_label: slotLabel,
    status,
  };
  if (testIds.length > 0) bookingPayload.test_ids = testIds;
  putText(bookingPayload, 'lab_id', after.labId);
  putText(bookingPayload, 'patient_gender', after.patientGender);
  putText(bookingPayload, 'contact_number', after.contactNumber);
  putText(bookingPayload, 'family_member_id', after.familyMemberId);
  putText(bookingPayload, 'partner_lab', after.partnerLab);
  putText(bookingPayload, 'address', after.address);
  if (typeof after.bookingForSelf === 'boolean') bookingPayload.booking_for_self = after.bookingForSelf;
  const bookingSource = firstText(after.source);
  if (bookingSource === 'app' || bookingSource === 'walkin') bookingPayload.source = bookingSource;
  putText(bookingPayload, 'report_file_name', after.reportFileName);
  putText(bookingPayload, 'report_storage_url', after.reportStorageUrl);
  putText(bookingPayload, 'report_booking_id', after.reportBookingId);
  const reportSubmittedAt = toIsoTimestamp(after.reportSubmittedAt);
  if (reportSubmittedAt) bookingPayload.report_submitted_at = reportSubmittedAt;
  const bookingCreatedAt = toIsoTimestamp(after.createdAt);
  if (bookingCreatedAt) bookingPayload.created_at = bookingCreatedAt;
  const bookingUpdatedAt = toIsoTimestamp(after.updatedAt);
  if (bookingUpdatedAt) bookingPayload.updated_at = bookingUpdatedAt;

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
          await pgMergeUpsert(pool, 'lab_bookings', bookingPayload, 'booking_id');
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

  const doctorId = firstText(after.doctorId);
  const patientId = firstText(after.patientId);
  const doctorName = firstText(after.doctorName);
  const patientName = firstText(after.patientName);
  const orderAge = optionalFiniteNumber(after.patientAge);
  const testIds = Array.isArray(after.testIds)
    ? after.testIds.map((item) => String(item || '').trim()).filter(Boolean)
    : [];
  const testNames = Array.isArray(after.testNames)
    ? after.testNames.map((item) => String(item || '').trim()).filter(Boolean)
    : [];
  const orderStatuses = ['ordered', 'received', 'inProgress', 'completed', 'cancelled'];
  const rawOrderStatus = firstText(after.status);
  // Doctor lab orders are constructed with status ordered.
  // frontend/lib/core/firebase/models/doctor_lab_order.dart:20
  const status = rawOrderStatus
    ? (orderStatuses.includes(rawOrderStatus) ? rawOrderStatus : undefined)
    : 'ordered';
  const rawUrgency = firstText(after.urgency);
  const urgency = !rawUrgency
    ? undefined
    : (['Routine', 'Urgent', 'STAT'].includes(rawUrgency) ? rawUrgency : undefined);
  const missing = [];
  if (!doctorId) missing.push('doctor_id');
  if (!patientId) missing.push('patient_id');
  if (!doctorName) missing.push('doctor_name');
  if (!patientName) missing.push('patient_name');
  if (orderAge === undefined) missing.push('patient_age');
  if (testIds.length === 0) missing.push('test_ids');
  if (testNames.length === 0) missing.push('test_names');
  if (!status) missing.push('status');
  if (rawUrgency && !urgency) missing.push('urgency');
  if (missing.length > 0) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_order',
      entityId: orderId,
      payload: { reason: `lab_order_required_missing:${missing.join(',')}` },
      errorMessage: `Skipped lab order: ${missing.join(', ')} required.`,
      retryCount: 0,
    });
    return;
  }

  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensurePatientExistsInPostgres(patientId, {
    patientName,
    patientAge: orderAge,
  }, { url, key, pool });

  if (after.labId) {
    await ensureLabExistsInPostgres(after.labId, { labName: after.labName }, { url, key, pool });
  }

  const orderPayload = {
    order_id: orderId,
    doctor_id: doctorId,
    patient_id: patientId,
    doctor_name: doctorName,
    patient_name: patientName,
    patient_age: Math.trunc(orderAge),
    test_ids: testIds,
    test_names: testNames,
    status,
  };
  putText(orderPayload, 'lab_id', after.labId);
  putText(orderPayload, 'appointment_id', after.appointmentId);
  putText(orderPayload, 'facility_id', after.facilityId);
  putText(orderPayload, 'admission_id', after.admissionId);
  putText(orderPayload, 'lab_name', after.labName);
  putText(orderPayload, 'indication', after.indication);
  if (urgency) orderPayload.urgency = urgency;
  if (typeof after.fastingRequired === 'boolean') orderPayload.fasting_required = after.fastingRequired;
  if (typeof after.homeCollection === 'boolean') orderPayload.home_collection = after.homeCollection;
  const orderSource = firstText(after.source);
  if (orderSource) orderPayload.source = orderSource;
  putText(orderPayload, 'report_file_name', after.reportFileName);
  putText(orderPayload, 'report_storage_url', after.reportStorageUrl);
  const orderReportAt = toIsoTimestamp(after.reportSubmittedAt);
  if (orderReportAt) orderPayload.report_submitted_at = orderReportAt;
  const orderCreatedAt = toIsoTimestamp(after.createdAt);
  if (orderCreatedAt) orderPayload.created_at = orderCreatedAt;
  const orderUpdatedAt = toIsoTimestamp(after.updatedAt);
  if (orderUpdatedAt) orderPayload.updated_at = orderUpdatedAt;

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
          await pgMergeUpsert(pool, 'lab_orders', orderPayload, 'order_id');
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

  const doctorId = firstText(after.doctorId);
  const labId = firstText(after.labId);
  const doctorName = firstText(after.doctorName);
  const labName = firstText(after.labName);
  const connectionStatuses = ['pending', 'active', 'rejected', 'removed'];
  const rawStatus = firstText(after.status);
  // New lab connections are created as pending.
  // frontend/lib/features/lab/data/lab_connection_store.dart:204
  const status = rawStatus
    ? (connectionStatuses.includes(rawStatus) ? rawStatus : undefined)
    : 'pending';
  const rawReqBy = firstText(after.requestedBy);
  // A doctor-sent invite sets requestedBy to doctor.
  // frontend/lib/features/lab/data/lab_connection_store.dart:205
  const requestedBy = rawReqBy
    ? (['doctor', 'lab'].includes(rawReqBy) ? rawReqBy : undefined)
    : 'doctor';
  const missing = [];
  if (!doctorId) missing.push('doctor_id');
  if (!labId) missing.push('lab_id');
  if (!doctorName) missing.push('doctor_name');
  if (!labName) missing.push('lab_name');
  if (!status) missing.push('status');
  if (!requestedBy) missing.push('requested_by');
  if (missing.length > 0) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'lab_connection',
      entityId: connectionId,
      payload: { reason: `lab_connection_required_missing:${missing.join(',')}` },
      errorMessage: `Skipped lab connection: ${missing.join(', ')} required.`,
      retryCount: 0,
    });
    return;
  }

  await ensureDoctorExistsInPostgres(doctorId, { url, key, pool });
  await ensureLabExistsInPostgres(labId, { labName }, { url, key, pool });

  const labConnectionPayload = {
    connection_id: connectionId,
    doctor_id: doctorId,
    lab_id: labId,
    doctor_name: doctorName,
    lab_name: labName,
    status,
    requested_by: requestedBy,
  };
  const requestedAt = toIsoTimestamp(after.requestedAt);
  if (requestedAt) labConnectionPayload.requested_at = requestedAt;
  const respondedAt = toIsoTimestamp(after.respondedAt);
  if (respondedAt) labConnectionPayload.responded_at = respondedAt;
  const connectionUpdatedAt = toIsoTimestamp(after.updatedAt);
  if (connectionUpdatedAt) labConnectionPayload.updated_at = connectionUpdatedAt;

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
          await pgMergeUpsert(pool, 'lab_connections', labConnectionPayload, 'connection_id');
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

  const builtAmbulance = buildAmbulanceSupabasePayload(ambulanceId, docData, fallbackData);
  if (builtAmbulance.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance',
      entityId: ambulanceId,
      payload: { ambulance_id: ambulanceId },
      errorMessage: `Skipped ambulance placeholder: ${builtAmbulance.reason}`,
      retryCount: 0,
    });
    return;
  }
  const placeholder = builtAmbulance.ambulance;

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

  const builtBroadcast = buildAmbulanceBroadcastSupabasePayload(broadcastId, docData, fallbackData);
  if (builtBroadcast.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_broadcast',
      entityId: broadcastId,
      payload: { reason: builtBroadcast.reason },
      errorMessage: `Skipped ambulance broadcast placeholder: ${builtBroadcast.reason}`,
      retryCount: 0,
    });
    return;
  }
  const placeholder = builtBroadcast.row;

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

  const builtAmbulanceSync = buildAmbulanceSupabasePayload(ambulanceId, after);
  if (builtAmbulanceSync.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance',
      entityId: ambulanceId,
      payload: { ambulance_id: ambulanceId },
      errorMessage: `Skipped ambulance sync: ${builtAmbulanceSync.reason}`,
      retryCount: 0,
    });
    return;
  }
  const ambulancePayload = builtAmbulanceSync.ambulance;
  putText(ambulancePayload, 'address_line1', after.addressLine1, after.address && after.address.addressLine1);
  putText(ambulancePayload, 'address_line2', after.addressLine2, after.address && after.address.addressLine2);
  putText(ambulancePayload, 'pincode', after.pincode, after.address && (after.address.pinCode || after.address.pincode));
  putText(ambulancePayload, 'base_address', after.baseAddress);
  putText(ambulancePayload, 'license_number', after.licenseNumber);
  putText(ambulancePayload, 'insurance_number', after.insuranceNumber);
  const ratePerKm = optionalFiniteNumber(after.ratePerKm);
  if (ratePerKm !== undefined) ambulancePayload.rate_per_km = ratePerKm;
  const totalRating = optionalFiniteNumber(after.totalRating);
  if (totalRating !== undefined) ambulancePayload.total_rating = totalRating;
  const ratingCount = optionalFiniteNumber(after.ratingCount);
  if (ratingCount !== undefined) ambulancePayload.rating_count = Math.trunc(ratingCount);
  putBooleanIfPresent(ambulancePayload, 'profile_completed', after.profileCompleted);
  if (Array.isArray(after.serviceAreas)) ambulancePayload.service_areas = toStringArray(after.serviceAreas, []);

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
          await pgMergeUpsert(pool, 'ambulances', ambulancePayload, 'ambulance_id');
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

  const builtBroadcastSync = buildAmbulanceBroadcastSupabasePayload(broadcastId, after);
  if (builtBroadcastSync.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_broadcast',
      entityId: broadcastId,
      payload: { reason: builtBroadcastSync.reason },
      errorMessage: `Skipped ambulance broadcast sync: ${builtBroadcastSync.reason}`,
      retryCount: 0,
    });
    return;
  }
  const broadcastPayload = {
    ...builtBroadcastSync.row,
    notes: after.notes || null,
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
        if (broadcastPayload.status === 'accepted' && after.acceptedDriverId) {
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
        } else if (broadcastPayload.status === 'cancelled') {
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

  const builtRequest = buildAmbulanceRequestSupabasePayload(requestId, after);
  if (builtRequest.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_request',
      entityId: requestId,
      payload: { reason: builtRequest.reason },
      errorMessage: `Skipped ambulance request sync: ${builtRequest.reason}`,
      retryCount: 0,
    });
    return;
  }
  const requestPayload = {
    ...builtRequest.row,
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

  const builtInvite = buildAmbulanceInviteSupabasePayload(inviteId, after);
  if (builtInvite.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'ambulance_invite',
      entityId: inviteId,
      payload: { reason: builtInvite.reason },
      errorMessage: `Skipped ambulance invite sync: ${builtInvite.reason}`,
      retryCount: 0,
    });
    return;
  }
  const invitePayload = {
    ...builtInvite.row,
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

function normalizeRole(role) {
  const raw = String(role || '').trim();
  const lower = raw.toLowerCase();
  if (lower === 'patient') return 'patient';
  if (lower === 'doctor') return 'doctor';
  if (lower === 'medical' || lower === 'medicalstore' || lower === 'medical_store' || lower === 'pharmacy') return 'medicalStore';
  if (lower === 'lab') return 'lab';
  if (lower === 'ambulance') return 'ambulance';
  if (lower === 'superadmin' || lower === 'super_admin') return 'superAdmin';
  if (lower === 'admin') return 'admin';
  return raw;
}

function buildUserSupabasePayload(uid, docData) {
  const doc = docData || {};
  const normalizedUid = String(uid || '').trim();
  if (!normalizedUid) {
    return { skip: true, reason: 'user_uid_missing' };
  }

  const role = normalizeRole(doc.role || 'patient');
  const profileId = firstText(doc.profileId, doc.profile_id, doc.id, normalizedUid);
  if (!profileId) {
    return { skip: true, reason: 'user_profile_id_missing' };
  }

  const rawEmail = firstText(doc.email);
  const rawMobile = firstText(doc.mobile, doc.phone);
  let mobile = rawMobile ? String(rawMobile).replace(/\D/g, '') : null;
  if (mobile && mobile.length === 12 && mobile.startsWith('91')) {
    mobile = mobile.slice(2);
  } else if (mobile && mobile.length === 11 && mobile.startsWith('0')) {
    mobile = mobile.slice(1);
  }
  const email = (rawEmail || `${mobile || normalizedUid}@signup.doctornect.app`).toLowerCase();
  const displayName = firstText(doc.displayName, doc.name, 'User');
  const profileCompleted = typeof doc.profileCompleted === 'boolean' ? doc.profileCompleted : false;
  const verified = typeof doc.verified === 'boolean' ? doc.verified : false;
  const status = firstText(doc.status, 'approved');
  const photoUrl = firstText(doc.photoUrl, doc.photo_url) || null;
  const createdAt = toIsoTimestamp(doc.createdAt) || new Date().toISOString();
  const updatedAt = toIsoTimestamp(doc.updatedAt) || new Date().toISOString();
  const verifiedAt = toIsoTimestamp(doc.verifiedAt) || null;
  const deactivated = Boolean(doc.deactivated);

  const row = {
    firebase_uid: normalizedUid,
    role,
    profile_id: profileId,
    display_name: displayName,
    email,
    mobile: mobile || null,
    profile_completed: profileCompleted,
    verified,
    status,
    deactivated,
    updated_at: updatedAt,
  };
  if (photoUrl) row.photo_url = photoUrl;
  if (verifiedAt) row.verified_at = verifiedAt;

  return {
    skip: false,
    row,
    createdAt,
  };
}

/**
 * Sync Firestore users/{uid} to Supabase public.users
 * Keyed on firebase_uid. Idempotent. Handles creates, updates, role changes, and deletes.
 */
async function syncFirestoreUserToSupabase(event) {
  const change = event.data;
  if (!change) return;

  const uid = event.params?.uid || change.after?.id || change.before?.id;
  if (!uid) return;

  // 1. Loop Prevention Check
  const afterData = change.after?.exists ? change.after.data() : null;
  if (afterData && (afterData.syncedBy === 'supabase_bridge' || afterData.syncedBy === 'reconciler_bot')) {
    return;
  }

  const { url, key } = getSupabaseConfig();
  const pool = getPgPool();

  if ((!url || !key) && !pool) {
    console.warn('[SyncBridge] Supabase credentials not configured in Cloud Functions. Skipping user sync.');
    return;
  }

  // 2. Handle document deletion: follow deleteMyAccount cleanup policy
  if (!change.after || !change.after.exists) {
    const beforeData = change.before?.exists ? change.before.data() : {};
    const role = beforeData.role ? normalizeRole(beforeData.role) : undefined;
    const profileId = beforeData.profileId || beforeData.profile_id;
    try {
      await executeWithRetry(
        async () => {
          const { cleanupUserSupabaseRows } = require('./delete_my_account');
          const res = await cleanupUserSupabaseRows({ uid, role, profileId });
          if (res && res.failedSupabaseTables && res.failedSupabaseTables.length > 0) {
            throw new Error(`Failed to cleanup Supabase tables: ${res.failedSupabaseTables.join(', ')}`);
          }
        },
        { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'user', entityId: uid, action: 'delete' } }
      );
    } catch (err) {
      await recordDlqFailure({
        direction: 'firestore_to_supabase',
        entityType: 'user',
        entityId: uid,
        payload: { uid, action: 'delete' },
        errorMessage: err.message,
        errorStack: err.stack,
        retryCount: err.retryCount || 3,
      });
      throw err;
    }
    return;
  }

  // 3. Monotonic compare-and-skip
  const localMs = firestoreTimestampMs(afterData.updatedAt);
  let remoteMs = null;
  try {
    remoteMs = await readRemoteUpdatedAtMs({
      url,
      key,
      pool,
      table: 'users',
      idColumn: 'firebase_uid',
      id: uid,
    });
  } catch (err) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'user',
      entityId: uid,
      payload: { reason: 'compare_and_skip_read_failed' },
      errorMessage: err.message,
      errorStack: err.stack,
    });
    return;
  }
  if (remoteMs != null && (localMs == null || localMs <= remoteMs)) {
    console.info(`[SyncBridge] Skipping stale user snapshot ${uid}`);
    return;
  }

  // 4. Build payload
  const built = buildUserSupabasePayload(uid, afterData);
  if (built.skip) {
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'user',
      entityId: uid,
      payload: { uid },
      errorMessage: `Skipped user sync: ${built.reason}`,
      retryCount: 0,
    });
    return;
  }

  const { row, createdAt } = built;

  // 5. Execute upsert with retry
  try {
    await executeWithRetry(
      async () => {
        if (url && key) {
          const checkResp = await fetch(
            `${url.replace(/\/+$/, '')}/rest/v1/users?firebase_uid=eq.${encodeURIComponent(uid)}&select=id&limit=1`,
            {
              method: 'GET',
              headers: {
                apikey: key,
                Authorization: `Bearer ${key}`,
              },
            }
          );
          const existingRows = checkResp.ok ? await checkResp.json() : [];
          if (Array.isArray(existingRows) && existingRows.length > 0) {
            // Row already exists - update via PATCH keyed on firebase_uid
            const patchResp = await fetch(
              `${url.replace(/\/+$/, '')}/rest/v1/users?firebase_uid=eq.${encodeURIComponent(uid)}`,
              {
                method: 'PATCH',
                headers: {
                  apikey: key,
                  Authorization: `Bearer ${key}`,
                  'Content-Type': 'application/json',
                  Prefer: 'return=minimal',
                },
                body: JSON.stringify(row),
              }
            );
            if (!patchResp.ok) {
              const errBody = await patchResp.text();
              throw new Error(`Supabase PostgREST user update error (${patchResp.status}): ${errBody}`);
            }
          } else {
            // Row does not exist - insert with generated UUID and on_conflict=firebase_uid
            const insertPayload = {
              id: crypto.randomUUID(),
              created_at: createdAt,
              ...row,
            };
            const postResp = await fetch(
              `${url.replace(/\/+$/, '')}/rest/v1/users?on_conflict=firebase_uid`,
              {
                method: 'POST',
                headers: {
                  apikey: key,
                  Authorization: `Bearer ${key}`,
                  'Content-Type': 'application/json',
                  Prefer: 'resolution=merge-duplicates,return=minimal',
                },
                body: JSON.stringify(insertPayload),
              }
            );
            if (!postResp.ok) {
              const errBody = await postResp.text();
              throw new Error(`Supabase PostgREST user insert error (${postResp.status}): ${errBody}`);
            }
          }
        } else if (pool) {
          const insertPayload = {
            id: crypto.randomUUID(),
            created_at: createdAt,
            ...row,
          };
          await upsertMergeRow(pool, 'users', 'firebase_uid', insertPayload);
        }
      },
      { maxRetries: 3, baseDelayMs: 200, context: { entityType: 'user', entityId: uid } }
    );
  } catch (err) {
    const retryCount = err.retryCount || 3;
    const actualErr = err.originalError || err;
    await recordDlqFailure({
      direction: 'firestore_to_supabase',
      entityType: 'user',
      entityId: uid,
      payload: row,
      errorMessage: actualErr.message,
      errorStack: actualErr.stack,
      retryCount,
    });
    throw actualErr;
  }
}

module.exports = {
  syncFirestoreUserToSupabase,
  buildUserSupabasePayload,
  normalizeRole,
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
  resolveWriterSyncOrigin,
  buildAppointmentSupabasePayload,
  firestoreTimestampMs,
  optionalFiniteNumber,
  experienceYearsFromDoctorDoc,
  placeholderPatientPayload,
  buildDoctorSupabasePayload,
  buildMedicalStoreSupabasePayload,
  buildLabSupabasePayload,
  buildAmbulanceSupabasePayload,
  buildAmbulanceBroadcastSupabasePayload,
  buildAmbulanceRequestSupabasePayload,
  buildAmbulanceInviteSupabasePayload,
  buildAvailabilitySupabasePayload,
  toStringArray,
  toIsoTimestamp,
  toDateString,
  toValidUuid,
};




