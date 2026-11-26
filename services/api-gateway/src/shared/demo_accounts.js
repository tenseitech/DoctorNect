/** Deploy bundle copy of scripts/lib/demo_accounts.js (the gateway image ships only src/). Keep identical: test/shared_module_parity.test.js */
'use strict';

/**
 * The five DoctorNect demo / store-reviewer accounts. Single source of truth for:
 *  - which mobile numbers may use the fixed demo OTP (REVIEW_FIXED_OTP), with no SMS
 *  - which numbers and Firebase UIDs live on the STAGING (Supabase) data plane
 *  - the staging seed (scripts/db/seed_staging_demo_accounts.js)
 *
 * Membership is decided here, server-side, from the canonical mobile number or the
 * Firebase UID. Nothing the client sends (role, headers, flags) can add to this list.
 *
 * Deploy-bundle copy: backend/functions/lib/demo_accounts.js must stay byte-identical
 * below this header (test/demo_routing_bundle_parity.test.js).
 */

const DEMO_ACCOUNTS = Object.freeze([
  Object.freeze({ digits: '9999900001', role: 'doctor', uid: 'rev_fb_doc_001', profileId: 'demo_doctor_001' }),
  Object.freeze({ digits: '9999900002', role: 'patient', uid: 'rev_fb_pat_001', profileId: 'demo_patient_001' }),
  Object.freeze({ digits: '9999900003', role: 'medicalStore', uid: 'rev_fb_store_001', profileId: 'demo_medicalstore_001' }),
  Object.freeze({ digits: '9999900004', role: 'lab', uid: 'rev_fb_lab_001', profileId: 'demo_lab_001' }),
  Object.freeze({ digits: '9999900005', role: 'ambulance', uid: 'rev_fb_amb_001', profileId: 'demo_ambulance_001' }),
]);

const BY_DIGITS = new Map(DEMO_ACCOUNTS.map((a) => [a.digits, a]));
const BY_UID = new Map(DEMO_ACCOUNTS.map((a) => [a.uid, a]));

/**
 * Strict canonical Indian mobile number: exactly 10 digits, optionally written as
 * "+91XXXXXXXXXX" or "91XXXXXXXXXX", with spaces / dashes / brackets ignored.
 * Everything else (leading 0, extra digits, letters, other country codes) returns null.
 * Unlike "take the last 10 digits", this never maps a longer number onto a demo number.
 */
function canonicalMobileDigits(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== 'string' && typeof raw !== 'number') return null;
  const compact = String(raw).trim().replace(/[\s\-().]/g, '');
  let m = /^\+91(\d{10})$/.exec(compact);
  if (!m) m = /^91(\d{10})$/.exec(compact);
  if (!m) m = /^(\d{10})$/.exec(compact);
  if (!m) return null;
  const digits = m[1];
  // Indian mobile numbers start with 6-9; anything else is not a phone we serve.
  if (!/^[6-9]/.test(digits)) return null;
  return digits;
}

/** Demo account for a mobile number (strict canonical match), or null. */
function demoAccountByMobile(raw) {
  const digits = canonicalMobileDigits(raw);
  return digits ? BY_DIGITS.get(digits) || null : null;
}

function isDemoMobile(raw) {
  return demoAccountByMobile(raw) !== null;
}

function demoAccountByUid(uid) {
  return BY_UID.get(String(uid || '').trim()) || null;
}

function isDemoUid(uid) {
  return demoAccountByUid(uid) !== null;
}

/**
 * True when any of the demo numbers appears in a string (any formatting). Used to
 * refuse writes of demo numbers to the production plane.
 */
function containsDemoMobile(text) {
  const digitsOnly = String(text || '').replace(/\D/g, '');
  return DEMO_ACCOUNTS.some((a) => digitsOnly.includes(a.digits));
}

module.exports = {
  DEMO_ACCOUNTS,
  canonicalMobileDigits,
  demoAccountByMobile,
  isDemoMobile,
  demoAccountByUid,
  isDemoUid,
  containsDemoMobile,
};
