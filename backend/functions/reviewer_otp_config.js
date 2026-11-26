'use strict';

/**
 * Demo / store-reviewer OTP policy.
 *
 * Exactly five numbers (lib/demo_accounts.js, one per role) may log in with a fixed OTP:
 *   9999900001 doctor, 9999900002 patient, 9999900003 pharmacy, 9999900004 lab,
 *   9999900005 ambulance.
 * The bypass is active only when ALL of these hold:
 *   REVIEWER_OTP_ENABLED=true
 *   REVIEW_FIXED_OTP  = 6 digits (Firebase Secret Manager; never in code or a plain env file)
 *   REVIEW_ACCESS_UNTIL = ISO 8601 instant in the future
 * No SMS is ever sent for these numbers. Their role, Firebase UID and data plane come from
 * the allowlist, never from the client. Any other number (including look-alikes such as a
 * leading 0 or extra digits) is a normal number: random OTP via MSG91.
 */

const {
  DEMO_ACCOUNTS,
  canonicalMobileDigits,
  demoAccountByMobile,
  isDemoMobile,
} = require('./lib/demo_accounts');

/** Kept for callers that still import it: canonical digits -> demo role. */
const REVIEW_TEST_PHONE_ROLES = Object.freeze(
  Object.fromEntries(DEMO_ACCOUNTS.map((a) => [a.digits, a.role])),
);

function normalizeRole(role) {
  const raw = String(role || '').trim();
  const lower = raw.toLowerCase();
  if (lower === 'patient') return 'patient';
  if (lower === 'doctor') return 'doctor';
  if (lower === 'medical' || lower === 'medicalstore' || lower === 'medical_store' || lower === 'pharmacy') {
    return 'medicalStore';
  }
  if (lower === 'lab') return 'lab';
  if (lower === 'ambulance') return 'ambulance';
  if (lower === 'superadmin' || lower === 'super_admin') return 'superAdmin';
  return raw;
}

/** Lenient last-10-digits normaliser used by non-OTP code paths. Not used for demo checks. */
function normalizeMobileDigits(mobile) {
  return String(mobile || '').replace(/\D/g, '').slice(-10);
}

function readReviewerFixedOtp(env = process.env) {
  return String(env.REVIEW_FIXED_OTP || '').trim();
}

/**
 * @returns {{active: boolean, reason: string, fixedOtp?: string, accessUntil?: Date}}
 * reason is one of: active, disabled, missing_fixed_otp, invalid_fixed_otp,
 * missing_access_until, invalid_access_until, expired.
 */
function demoOtpPolicy(env = process.env, now = Date.now()) {
  const enabled = String(env.REVIEWER_OTP_ENABLED || '').trim().toLowerCase() === 'true';
  if (!enabled) return { active: false, reason: 'disabled' };
  const fixedOtp = readReviewerFixedOtp(env);
  if (!fixedOtp) return { active: false, reason: 'missing_fixed_otp' };
  if (!/^\d{6}$/.test(fixedOtp)) return { active: false, reason: 'invalid_fixed_otp' };
  const rawUntil = String(env.REVIEW_ACCESS_UNTIL || '').trim();
  if (!rawUntil) return { active: false, reason: 'missing_access_until' };
  const accessUntil = new Date(rawUntil);
  if (Number.isNaN(accessUntil.getTime())) return { active: false, reason: 'invalid_access_until' };
  if (now > accessUntil.getTime()) return { active: false, reason: 'expired' };
  return { active: true, reason: 'active', fixedOtp, accessUntil };
}

/**
 * Legacy shape used by older call sites. Returns the active policy for a role, or null.
 * testNumbers holds the single allowlisted number for that role.
 */
function getReviewerConfig(role) {
  const policy = demoOtpPolicy();
  if (!policy.active || !role) return null;
  const roleKey = normalizeRole(role);
  const testNumbers = DEMO_ACCOUNTS.filter((a) => a.role === roleKey).map((a) => a.digits);
  if (testNumbers.length === 0) return null;
  return { testNumbers, fixedOtp: policy.fixedOtp, accessUntil: policy.accessUntil, role: roleKey };
}

/**
 * True when `mobile` is one of the five demo numbers (strict canonical match) AND the demo
 * OTP policy is active. A role, when given, must equal the allowlisted role; omitting the
 * role never widens the list.
 */
function isReviewerPhone(mobile, role) {
  const account = demoAccountByMobile(mobile);
  if (!account) return false;
  if (!demoOtpPolicy().active) return false;
  if (role && normalizeRole(role) !== account.role) return false;
  return true;
}

function isAnyReviewerPhone(mobile) {
  return isReviewerPhone(mobile);
}

const REVIEWER_LOGIN_ROLES = ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance'];

/** @deprecated numbers are fixed in lib/demo_accounts.js; kept for scripts that import it. */
function phonesFromReviewTestNumbers(roleKey) {
  return DEMO_ACCOUNTS.filter((a) => a.role === normalizeRole(roleKey)).map((a) => a.digits);
}

module.exports = {
  REVIEW_TEST_PHONE_ROLES,
  REVIEWER_LOGIN_ROLES,
  normalizeRole,
  normalizeMobileDigits,
  canonicalMobileDigits,
  demoAccountByMobile,
  isDemoMobile,
  demoOtpPolicy,
  getReviewerConfig,
  isReviewerPhone,
  isAnyReviewerPhone,
  readReviewerFixedOtp,
  phonesFromReviewTestNumbers,
};
