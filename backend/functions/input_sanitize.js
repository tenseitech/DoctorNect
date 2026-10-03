'use strict';

/**
 * Strict input validation / sanitization for Cloud Functions.
 * Firestore is not SQL — still reject control chars, script payloads, and
 * type-mismatched fields so stored/reflected XSS and injection stay out.
 */

const { HttpsError } = require('firebase-functions/v2/https');

const DOC_ID_RE = /^[A-Za-z0-9_\-]{1,128}$/;
const USERNAME_RE = /^[a-z0-9._\-]{3,32}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const INDIAN_MOBILE_RE = /^[6-9]\d{9}$/;
const OTP_RE = /^\d{6}$/;
const PIN_RE = /^\d{6}$/;
const HEX_TOKEN_RE = /^[A-Fa-f0-9]{8,256}$/;
const INVITE_TOKEN_RE = /^[a-z0-9]{16,64}$/;
const RAZORPAY_ID_RE = /^[A-Za-z0-9_\-]{6,64}$/;
const SAFE_SCHEME_RE = /^(https?|tel|mailto|sms):/i;

/** Params clients may pass into validateField / validateFormFields. */
const ALLOWED_RULE_PARAM_KEYS = new Set([
  'field',
  'dialCode',
  'password',
  'current',
  'min',
  'max',
  'selected',
]);

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function stripControlChars(value) {
  return String(value ?? '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '');
}

/** Remove angle brackets / javascript: to blunt script injection in stored text. */
function sanitizePlainText(value, { maxLength = 2000 } = {}) {
  let s = stripControlChars(value).trim();
  s = s.replace(/[<>]/g, '');
  s = s.replace(/javascript\s*:/gi, '');
  s = s.replace(/data\s*:/gi, '');
  s = s.replace(/vbscript\s*:/gi, '');
  if (s.length > maxLength) s = s.slice(0, maxLength);
  return s;
}

function requireString(value, field, { min = 1, max = 256, pattern = null } = {}) {
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new HttpsError('invalid-argument', `${field} must be a string.`);
  }
  const s = stripControlChars(String(value)).trim();
  if (s.length < min || s.length > max) {
    throw new HttpsError(
      'invalid-argument',
      `${field} must be between ${min} and ${max} characters.`,
    );
  }
  if (pattern && !pattern.test(s)) {
    throw new HttpsError('invalid-argument', `Invalid ${field}.`);
  }
  return s;
}

function requireDocId(value, field = 'id') {
  return requireString(value, field, { min: 1, max: 128, pattern: DOC_ID_RE });
}

function requireEmail(value, field = 'email') {
  const s = requireString(value, field, { min: 5, max: 254 }).toLowerCase();
  if (!EMAIL_RE.test(s)) {
    throw new HttpsError('invalid-argument', `Invalid ${field}.`);
  }
  return s;
}

function requireIndianMobile(value, field = 'mobile') {
  const digits = String(value || '').replace(/\D/g, '');
  let normalized = digits;
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.slice(2);
  } else if (normalized.length === 11 && normalized.startsWith('0')) {
    normalized = normalized.slice(1);
  }
  if (!INDIAN_MOBILE_RE.test(normalized)) {
    throw new HttpsError('invalid-argument', `Enter a valid 10-digit ${field}.`);
  }
  return normalized;
}

function optionalIndianMobile(value, field = 'mobile') {
  const raw = String(value || '').trim();
  if (!raw) return '';
  return requireIndianMobile(raw, field);
}

function requireOtp(value) {
  const s = String(value || '').replace(/\D/g, '');
  if (!OTP_RE.test(s)) {
    throw new HttpsError('invalid-argument', 'OTP must be a 6-digit code.');
  }
  return s;
}

function requirePin(value, field = 'pin') {
  const s = String(value || '').replace(/\D/g, '');
  if (!PIN_RE.test(s)) {
    throw new HttpsError('invalid-argument', `${field} must be a 6-digit number.`);
  }
  return s;
}

/** Ambulance driver dashboard password (PBKDF2 hash verified server-side). */
function requireAmbulancePassword(value, field = 'password') {
  const s = requireString(value, field, { min: 6, max: 128 });
  return s;
}

function requireUsername(value) {
  const s = requireString(value, 'username', { min: 3, max: 32 }).toLowerCase();
  if (!USERNAME_RE.test(s)) {
    throw new HttpsError('invalid-argument', 'Invalid username.');
  }
  return s;
}

function requireIntInSet(value, field, allowed) {
  const n = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isInteger(n) || !allowed.includes(n)) {
    throw new HttpsError(
      'invalid-argument',
      `${field} must be one of: ${allowed.join(', ')}.`,
    );
  }
  return n;
}

function requireStars(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 5) {
    throw new HttpsError('invalid-argument', 'Rating must be an integer from 1 to 5.');
  }
  return n;
}

function sanitizeReview(value) {
  return sanitizePlainText(value, { maxLength: 500 });
}

function sanitizeSafeUrl(value, field = 'url') {
  const s = stripControlChars(String(value || '')).trim();
  if (!s) {
    throw new HttpsError('invalid-argument', `${field} is required.`);
  }
  if (!SAFE_SCHEME_RE.test(s) && !s.startsWith('/')) {
    throw new HttpsError('invalid-argument', `Unsupported ${field} scheme.`);
  }
  if (/javascript\s*:/i.test(s) || /data\s*:/i.test(s)) {
    throw new HttpsError('invalid-argument', `Unsafe ${field}.`);
  }
  return s.slice(0, 2048);
}

function sanitizeFileName(name) {
  const base = String(name || 'file')
    .split(/[/\\]/)
    .pop();
  let clean = stripControlChars(base).replace(/[^\w.\-]/g, '_');
  clean = clean.replace(/^\.+/, '');
  if (!clean || clean === '.' || clean === '..') clean = 'file';
  if (clean.length > 120) {
    const extMatch = clean.match(/(\.[A-Za-z0-9]{1,8})$/);
    const ext = extMatch ? extMatch[1] : '';
    clean = `${clean.slice(0, 120 - ext.length)}${ext}`;
  }
  return clean;
}

function assertSafeUploadMeta({ fileName, contentType, sizeBytes, allowedExts, allowedMimePrefixes, maxBytes }) {
  const safeName = sanitizeFileName(fileName);
  const lower = safeName.toLowerCase();
  const extOk = allowedExts.some((ext) => lower.endsWith(ext.toLowerCase()));
  if (!extOk) {
    throw new HttpsError('invalid-argument', 'File type not allowed.');
  }
  const mime = String(contentType || '').toLowerCase();
  const mimeOk = allowedMimePrefixes.some((p) => mime.startsWith(p.toLowerCase()));
  if (!mimeOk) {
    throw new HttpsError('invalid-argument', 'File content type not allowed.');
  }
  const size = Number(sizeBytes);
  if (!Number.isFinite(size) || size <= 0 || size > maxBytes) {
    throw new HttpsError('invalid-argument', 'File size exceeds limit.');
  }
  return safeName;
}

function sanitizeRuleParams(params) {
  if (params == null) return {};
  if (typeof params !== 'object' || Array.isArray(params)) {
    throw new HttpsError('invalid-argument', 'params must be an object.');
  }
  const out = {};
  for (const [key, val] of Object.entries(params)) {
    if (!ALLOWED_RULE_PARAM_KEYS.has(key)) continue;
    if (key === 'selected') {
      if (Array.isArray(val)) {
        out.selected = val.map((v) => sanitizePlainText(String(v), { maxLength: 80 })).slice(0, 50);
      } else if (val && typeof val === 'object') {
        out.selected = Object.keys(val)
          .map((k) => sanitizePlainText(k, { maxLength: 80 }))
          .slice(0, 50);
      }
      continue;
    }
    if (key === 'min' || key === 'max') {
      const n = Number(val);
      if (Number.isFinite(n)) out[key] = n;
      continue;
    }
    out[key] = sanitizePlainText(String(val), { maxLength: 120 });
  }
  return out;
}

function requireKnownRule(ruleName, RULES) {
  const name = requireString(ruleName, 'rule', { min: 1, max: 64, pattern: /^[A-Za-z][A-Za-z0-9_]*$/ });
  if (!RULES || !RULES[name]) {
    throw new HttpsError('invalid-argument', 'Unknown validation rule.');
  }
  return name;
}

function requireRazorpayId(value, field) {
  return requireString(value, field, { min: 6, max: 64, pattern: RAZORPAY_ID_RE });
}

function requireHexLikeToken(value, field = 'token') {
  return requireString(value, field, { min: 8, max: 256, pattern: HEX_TOKEN_RE });
}

function requireInviteToken(value, field = 'token') {
  return requireString(value, field, { min: 16, max: 64, pattern: INVITE_TOKEN_RE });
}

module.exports = {
  escapeHtml,
  stripControlChars,
  sanitizePlainText,
  sanitizeFileName,
  sanitizeRuleParams,
  sanitizeReview,
  sanitizeSafeUrl,
  requireString,
  requireDocId,
  requireEmail,
  requireIndianMobile,
  optionalIndianMobile,
  requireOtp,
  requirePin,
  requireAmbulancePassword,
  requireUsername,
  requireIntInSet,
  requireStars,
  requireKnownRule,
  requireRazorpayId,
  requireHexLikeToken,
  requireInviteToken,
  assertSafeUploadMeta,
  DOC_ID_RE,
  ALLOWED_RULE_PARAM_KEYS,
};
