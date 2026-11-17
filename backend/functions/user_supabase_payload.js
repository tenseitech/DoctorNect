'use strict';

/** Postgres `public.users` row builder from legacy profile document shapes (backfill + triggers). */

function firstText(...values) {
  for (const v of values) {
    if (v == null) continue;
    const s = String(v).trim();
    if (s.length > 0) return s;
  }
  return null;
}

function toIsoTimestamp(val) {
  if (!val) return null;
  if (typeof val.toDate === 'function') {
    return val.toDate().toISOString();
  }
  if (val instanceof Date) {
    return Number.isNaN(val.getTime()) ? null : val.toISOString();
  }
  if (typeof val === 'string' || typeof val === 'number') {
    const d = new Date(val);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
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
  firstText,
  toIsoTimestamp,
  normalizeRole,
  buildUserSupabasePayload,
};