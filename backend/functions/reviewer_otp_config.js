'use strict';

const REVIEW_TEST_PHONE_ROLES = {
  9999900001: 'patient',
  9999900002: 'doctor',
  9999900003: 'medicalStore',
  9999900004: 'lab',
  9999900005: 'ambulance',
};

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

function normalizeMobileDigits(mobile) {
  return String(mobile || '').replace(/\D/g, '').slice(-10);
}

function parseReviewerPhoneList(raw, maxCount = 2) {
  if (!raw) return [];
  const list = String(raw)
    .split(',')
    .map((n) => normalizeMobileDigits(n))
    .filter(Boolean);
  return list.slice(0, maxCount);
}

function phonesFromReviewTestNumbers(roleKey) {
  const raw = String(process.env.REVIEW_TEST_NUMBERS || '').trim();
  if (!raw) return [];
  const out = [];
  for (const part of raw.split(',')) {
    const d = normalizeMobileDigits(part);
    if (!d || d.length !== 10) continue;
    const mapped = REVIEW_TEST_PHONE_ROLES[d];
    if (mapped && normalizeRole(mapped) === roleKey) {
      out.push(d);
    }
  }
  return out.slice(0, 2);
}

function readReviewerFixedOtp() {
  return String(process.env.REVIEW_FIXED_OTP || '').trim();
}

function getReviewerConfig(role) {
  const enabled =
    String(process.env.REVIEWER_OTP_ENABLED || '')
      .trim()
      .toLowerCase() === 'true';
  if (!enabled) return null;

  const fixedOtp = readReviewerFixedOtp();
  const accessUntil = String(process.env.REVIEW_ACCESS_UNTIL || '').trim();
  if (!fixedOtp || !accessUntil) return null;

  const expiryDate = new Date(accessUntil);
  if (isNaN(expiryDate.getTime()) || Date.now() > expiryDate.getTime()) {
    return null;
  }

  if (!role) return null;

  const roleKey = normalizeRole(role);
  const envKey = `REVIEW_${roleKey.toUpperCase()}_PHONES`;
  let testNumbers = parseReviewerPhoneList(process.env[envKey], 2);
  if (testNumbers.length === 0 && roleKey === 'medicalStore') {
    testNumbers = parseReviewerPhoneList(process.env.REVIEW_MEDICAL_STORE_PHONES, 2);
  }
  if (testNumbers.length === 0 && roleKey === 'medicalStore') {
    testNumbers = parseReviewerPhoneList(process.env.REVIEW_MEDICALSTORE_PHONES, 2);
  }
  if (testNumbers.length === 0) {
    testNumbers = phonesFromReviewTestNumbers(roleKey);
  }
  if (testNumbers.length === 0) return null;

  return {
    testNumbers,
    fixedOtp,
    accessUntil: expiryDate,
    role: roleKey,
  };
}

function isReviewerPhone(digits, role) {
  if (!role) return false;
  const config = getReviewerConfig(role);
  if (!config) return false;
  const d = normalizeMobileDigits(digits);
  if (!d) return false;
  if (normalizeRole(role) !== config.role) return false;
  return config.testNumbers.includes(d);
}

const REVIEWER_LOGIN_ROLES = ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance'];

function isAnyReviewerPhone(digits) {
  return REVIEWER_LOGIN_ROLES.some((role) => isReviewerPhone(digits, role));
}

module.exports = {
  REVIEW_TEST_PHONE_ROLES,
  REVIEWER_LOGIN_ROLES,
  normalizeRole,
  normalizeMobileDigits,
  getReviewerConfig,
  isReviewerPhone,
  isAnyReviewerPhone,
  readReviewerFixedOtp,
  phonesFromReviewTestNumbers,
};