'use strict';

const {
  optionalFiniteNumber,
  firestoreTimestampMs,
  toStringArray,
  toIsoTimestamp,
  toDateString,
  toValidUuid,
} = require('./cross_role_sync_coerce');

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

module.exports = {
  APPOINTMENT_SYNC_ORIGINS,
  experienceYearsFromDoctorDoc,
  firstText,
  putText,
  putBooleanIfPresent,
  placeholderPatientPayload,
  buildDoctorSupabasePayload,
  buildMedicalStoreSupabasePayload,
  buildLabSupabasePayload,
  buildAmbulanceSupabasePayload,
  buildAmbulanceBroadcastSupabasePayload,
  buildAmbulanceRequestSupabasePayload,
  buildAmbulanceInviteSupabasePayload,
  buildAvailabilitySupabasePayload,
  resolveWriterSyncOrigin,
  buildAppointmentSupabasePayload,
  normalizeRole,
  buildUserSupabasePayload,
};
