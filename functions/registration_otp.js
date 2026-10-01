const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { sendMsg91Email } = require('./msg91_email');
const { readMsg91AuthKey } = require('./secure_config');
const { isProductionFirebaseProject } = require('./production_otp_guard');
const {
  GENERIC_ACCOUNT_LOOKUP_FAILED,
  GENERIC_PASSWORD_UPDATE_FAILED,
  GENERIC_MOBILE_LOGIN_FAILED,
  logInternalError,
} = require('./public_error_messages');

const OTP_EXPIRY_MS = 10 * 60 * 1000;
const SESSION_EXPIRY_MS = 30 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
/** Dev-only: when OTP_TEST_MODE=true, all numbers accept this OTP (never returned in prod). */
const DEV_TEST_OTP = '123456';
/**
 * Demo / store-review accounts — fixed OTP 000000, no SMS, one phone per role.
 * Set DEMO_PHONE_* in functions env (server-only). Legacy: GOOGLE_PLAY_REVIEW_PHONE = patient.
 */
// No hardcoded DEMO_OTP here anymore. It must come from Firestore.

/** Env keys tried in order per role (first non-empty wins). */
const DEMO_PHONE_ENV_BY_ROLE = {
  patient: ['DEMO_PHONE_PATIENT', 'GOOGLE_PLAY_REVIEW_PHONE', 'TEST_PHONE_NUMBER'],
  doctor: ['DEMO_PHONE_DOCTOR'],
  medicalStore: ['DEMO_PHONE_MEDICAL_STORE', 'DEMO_PHONE_PHARMACY'],
  lab: ['DEMO_PHONE_LAB'],
  ambulance: ['DEMO_PHONE_AMBULANCE'],
  superAdmin: ['DEMO_PHONE_SUPER_ADMIN'],
  super_admin: ['DEMO_PHONE_SUPER_ADMIN'],
};

const DEFAULT_DEMO_CONFIG = {
  demoOtp: '000000',
  demoPhones: {
    patient: ['7058809803'],
    doctor: ['7666892394'],
    medicalStore: ['9359503874'],
    lab: ['9409858233'],
    ambulance: ['9307583929'],
    superAdmin: ['9999988888'],
  },
  enableDemoSuperAdmin: false,
};

// Cache for demo config to reduce Firestore reads (lives for the life of the Cloud Function instance)
let cachedDemoConfig = null;
let lastDemoConfigFetchTime = 0;
const DEMO_CONFIG_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

async function getDemoConfig() {
  if (cachedDemoConfig && (Date.now() - lastDemoConfigFetchTime < DEMO_CONFIG_CACHE_TTL_MS)) {
    return cachedDemoConfig;
  }
  
  try {
    const { getFirestore } = require('firebase-admin/firestore');
    const doc = await getFirestore().collection('app_config').doc('demo_accounts').get();
    if (doc.exists) {
      cachedDemoConfig = doc.data();
      lastDemoConfigFetchTime = Date.now();
      return cachedDemoConfig;
    }
  } catch (error) {
    console.error('Error fetching demo config:', error);
  }
  return DEFAULT_DEMO_CONFIG;
}

function demoPhoneDigitsForRole(role) {
  const r = String(role || '').trim();
  const keys = DEMO_PHONE_ENV_BY_ROLE[r];
  if (!keys) return null;
  for (const key of keys) {
    const raw = String(process.env[key] || '').trim();
    if (!raw) continue;
    const digits = normalizeMobileDigits(raw);
    if (digits) return digits;
  }
  return null;
}

/** True when [digits] is the env-configured demo number for [role] only. */
async function isDemoPhone(digits, role) {
  const r = String(role || '').trim();
  const isSuperAdminRole = r === 'superAdmin' || r === 'super_admin';
  const config = await getDemoConfig();

  // Safety gate: demo Super Admin is enabled ONLY when dev/demo flag is on
  // In production with flag off, behaves like a normal number!
  if (isSuperAdminRole) {
    const isProd = isProductionFirebaseProject();
    const isExplicitlyEnabled = Boolean(
      config && (config.enableDemoSuperAdmin === true || config.demoSuperAdminEnabled === true)
    );
    if (isProd && !isExplicitlyEnabled) {
      return false;
    }
  }
  
  // 1. Check remote config (Firestore)
  if (config && config.demoPhones && config.demoOtp) {
    const remoteList = config.demoPhones[r] || (isSuperAdminRole ? (config.demoPhones.superAdmin || config.demoPhones.super_admin) : null);
    if (Array.isArray(remoteList)) {
      for (const remoteNumber of remoteList) {
        if (normalizeMobileDigits(remoteNumber) === digits) {
          return true;
        }
      }
    }
  }

  // 2. Block env-based demo numbers in production to prevent accidental leaks
  if (isProductionFirebaseProject()) {
    return false;
  }
  
  const expected = demoPhoneDigitsForRole(role);
  return expected != null && expected === digits;
}

/** Callable/request mobile + role — demo bypass only for matching role number. */
async function isDemoMobileInput(mobile, role) {
  const digits = normalizeMobileDigits(mobile);
  if (!digits) return false;
  return await isDemoPhone(digits, String(role || 'patient').trim());
}

/** @deprecated use isDemoPhone(digits, role) */
async function isPlayReviewPhone(digits) {
  return await isDemoPhone(digits, 'patient');
}

/** @deprecated use isDemoMobileInput(mobile, role) */
async function isPlayReviewMobileInput(mobile) {
  return await isDemoMobileInput(mobile, 'patient');
}
const SEND_IP_WINDOW_MS = 60 * 60 * 1000;
const SEND_IP_MAX = 10;
const SEND_MOBILE_WINDOW_MS = 60 * 60 * 1000;
const SEND_MOBILE_MAX = 5;
const VERIFY_IP_WINDOW_MS = 60 * 60 * 1000;
const VERIFY_IP_MAX = 15;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_IP_MAX = 20;
const LOGIN_IDENTIFIER_MAX = 5;
const PASSWORD_RESET_WINDOW_MS = 60 * 60 * 1000;
const PASSWORD_RESET_IP_MAX = 10;
const PASSWORD_RESET_IDENTIFIER_MAX = 5;
const PBKDF2_ITERATIONS = 120000;
const PBKDF2_KEYLEN = 32;
const PBKDF2_DIGEST = 'sha256';

function isTestMode() {
  if (isProductionFirebaseProject()) {
    return false;
  }
  const mode = String(process.env.OTP_TEST_MODE || '').trim().toLowerCase();
  return mode === 'true' || mode === '1';
}

function normalizeMobileDigits(mobile) {
  let digits = String(mobile || '').replace(/\D/g, '');
  while (digits.length > 10 && digits.startsWith('91')) {
    digits = digits.slice(2);
  }
  while (digits.length > 10 && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (digits.length !== 10 || !/^[6-9]\d{9}$/.test(digits)) return '';
  return digits;
}

function mobileHash(role, digits) {
  return crypto.createHash('sha256').update(`${role}:${digits}`).digest('hex');
}

function hashOtp(code) {
  return crypto.createHash('sha256').update(String(code || '')).digest('hex');
}

function otpHashesEqual(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

function generateOtpCode() {
  return String(crypto.randomInt(100000, 1000000));
}

function assertStrongPassword(password) {
  const value = String(password || '');
  if (value.length < 8) {
    throw new HttpsError('invalid-argument', 'Password must be at least 8 characters.');
  }
  if (!/[A-Z]/.test(value) || !/[a-z]/.test(value) || !/[0-9]/.test(value)
      || !/[!@#$%^&*(),.?":{}|<>_\-\+=/\\]/.test(value)) {
    throw new HttpsError(
      'invalid-argument',
      'Password must include upper, lower, number, and special character.',
    );
  }
}

function hashAmbulancePin(pin) {
  const salt = crypto.randomBytes(16);
  const derived = crypto.pbkdf2Sync(
    String(pin || '').trim(),
    salt,
    PBKDF2_ITERATIONS,
    PBKDF2_KEYLEN,
    PBKDF2_DIGEST,
  );
  return `pbkdf2$sha256$${PBKDF2_ITERATIONS}$${salt.toString('hex')}$${derived.toString('hex')}`;
}

function legacySha256Pin(pin) {
  return crypto.createHash('sha256').update(String(pin || '').trim()).digest('hex');
}

function ambulancePinMatches(storedPin, enteredPin) {
  const stored = String(storedPin || '').trim();
  const entered = String(enteredPin || '').trim();
  if (!stored || !entered) return false;

  // pbkdf2$sha256$iterations$salt$hash
  if (stored.startsWith('pbkdf2$sha256$')) {
    const parts = stored.split('$');
    if (parts.length !== 5) return false;
    const iterations = Number(parts[2]);
    const salt = Buffer.from(parts[3], 'hex');
    const expected = Buffer.from(parts[4], 'hex');
    if (!iterations || salt.length === 0 || expected.length === 0) return false;
    const actual = crypto.pbkdf2Sync(entered, salt, iterations, expected.length, PBKDF2_DIGEST);
    return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
  }

  // Legacy pbkdf2$iterations$salt$hash
  if (stored.startsWith('pbkdf2$')) {
    const parts = stored.split('$');
    if (parts.length === 4) {
      const iterations = Number(parts[1]);
      const salt = Buffer.from(parts[2], 'hex');
      const expected = Buffer.from(parts[3], 'hex');
      if (!iterations || salt.length === 0 || expected.length === 0) return false;
      const actual = crypto.pbkdf2Sync(entered, salt, iterations, expected.length, PBKDF2_DIGEST);
      return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
    }
  }

  if (/^[a-f0-9]{64}$/i.test(stored)) {
    const legacy = legacySha256Pin(entered);
    const left = Buffer.from(legacy.toLowerCase(), 'utf8');
    const right = Buffer.from(stored.toLowerCase(), 'utf8');
    return left.length === right.length && crypto.timingSafeEqual(left, right);
  }

  return false;
}

function normalizeRole(role) {
  const raw = String(role || '').trim();
  const lower = raw.toLowerCase();
  if (lower === 'patient') return 'patient';
  if (lower === 'doctor') return 'doctor';
  if (lower === 'medicalstore' || lower === 'medical_store' || lower === 'pharmacy') return 'medicalStore';
  if (lower === 'lab') return 'lab';
  if (lower === 'ambulance') return 'ambulance';
  if (lower === 'superadmin' || lower === 'super_admin') return 'superAdmin';
  return raw;
}

function assertSupportedRole(role) {
  const normalized = normalizeRole(role);
  const supported = new Set(['patient', 'doctor', 'lab', 'medicalStore', 'ambulance', 'superAdmin']);
  if (!supported.has(normalized)) {
    throw new HttpsError(
      'invalid-argument',
      'Unsupported role. Use patient, doctor, lab, medicalStore, ambulance, or superAdmin.',
    );
  }
}

function hashRateLimitKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

async function assertOtpRateLimit(db, { bucket, windowMs, maxAttempts }) {
  const ref = db.collection('otp_rate_limits').doc(bucket);
  const nowMs = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const windowStartMs = data.windowStart?.toDate?.()?.getTime() || 0;
    const withinWindow = windowStartMs > 0 && nowMs - windowStartMs < windowMs;
    const count = withinWindow ? (Number(data.count) || 0) : 0;

    if (count >= maxAttempts) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many OTP requests. Please try again later.',
      );
    }

    tx.set(ref, {
      count: count + 1,
      windowStart: withinWindow
        ? data.windowStart
        : Timestamp.fromDate(new Date(nowMs)),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function enforceSendOtpRateLimits(db, { clientIp, role, digits }) {
  if (await isDemoPhone(digits, role)) return;
  await assertOtpRateLimit(db, {
    bucket: `send_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: SEND_IP_WINDOW_MS,
    maxAttempts: SEND_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `send_mobile_${mobileHash(role, digits)}`,
    windowMs: SEND_MOBILE_WINDOW_MS,
    maxAttempts: SEND_MOBILE_MAX,
  });
}

async function enforceVerifyOtpRateLimits(db, { clientIp, role, digits }) {
  if (await isDemoPhone(digits, role)) return;
  await assertOtpRateLimit(db, {
    bucket: `verify_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: VERIFY_IP_WINDOW_MS,
    maxAttempts: VERIFY_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `verify_mobile_${mobileHash(role, digits)}`,
    windowMs: VERIFY_IP_WINDOW_MS,
    maxAttempts: VERIFY_IP_MAX,
  });
}

function resolveLoginBuckets(data, clientIp = 'unknown') {
  const identifier = String(data?.identifier || data?.email || '').trim().toLowerCase();
  if (!identifier) {
    throw new HttpsError('invalid-argument', 'Identifier is required.');
  }
  return {
    identifier,
    idBucket: `login_id_${hashRateLimitKey(identifier)}`,
    ipBucket: `login_ip_${hashRateLimitKey(clientIp)}`,
  };
}

async function incrementLoginFailureBucket(db, bucket) {
  const ref = db.collection('otp_rate_limits').doc(bucket);
  const nowMs = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const windowStartMs = data.windowStart?.toDate?.()?.getTime() || 0;
    const withinWindow = windowStartMs > 0 && nowMs - windowStartMs < LOGIN_WINDOW_MS;
    const count = withinWindow ? (Number(data.count) || 0) : 0;

    tx.set(ref, {
      count: count + 1,
      windowStart: withinWindow
        ? data.windowStart
        : Timestamp.fromDate(new Date(nowMs)),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function clearLoginFailureBucket(db, bucket) {
  const ref = db.collection('otp_rate_limits').doc(bucket);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    tx.delete(ref);
  });
}

async function consumeLoginAttempt(db, data, { clientIp = 'unknown' } = {}) {
  return assertLoginAllowed(db, data, { clientIp });
}

async function enforcePasswordResetRateLimits(db, { clientIp, identifier }) {
  await assertOtpRateLimit(db, {
    bucket: `pwd_reset_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: PASSWORD_RESET_WINDOW_MS,
    maxAttempts: PASSWORD_RESET_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `pwd_reset_id_${hashRateLimitKey(identifier)}`,
    windowMs: PASSWORD_RESET_WINDOW_MS,
    maxAttempts: PASSWORD_RESET_IDENTIFIER_MAX,
  });
}

async function readUserProfile(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return null;
  return snap.data() || null;
}

async function markUserMobileVerified(db, { uid, mobileDigits, role }) {
  const now = FieldValue.serverTimestamp();
  await db.collection('users').doc(uid).set(
    {
      mobileVerified: true,
      mobileVerifiedAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  await db
    .collection('otp_verification_sessions')
    .doc(mobileHash(role, mobileDigits))
    .delete()
    .catch(() => {});

  return { mobileVerified: true, uid };
}

async function markPatientMobileVerified(db, { uid, mobileDigits }) {
  return markUserMobileVerified(db, { uid, mobileDigits, role: 'patient' });
}

async function approveUserAccount(db, data, auth) {
  const allowedEmails = (
    process.env.ACCOUNT_APPROVAL_ADMIN_EMAILS
    || process.env.PATIENT_APPROVAL_ADMIN_EMAILS
    || process.env.BACKFILL_ADMIN_EMAILS
    || ''
  )
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const callerEmail = String(auth?.token?.email || '').trim().toLowerCase();
  const emailVerified = auth?.token?.email_verified === true;
  if (allowedEmails.length === 0) {
    throw new HttpsError(
      'permission-denied',
      'Account approval is not configured. Set ACCOUNT_APPROVAL_ADMIN_EMAILS.',
    );
  }
  if (!emailVerified || !allowedEmails.includes(callerEmail)) {
    throw new HttpsError('permission-denied', 'Not authorized to approve accounts.');
  }

  const role = String(data?.role || 'patient').trim();
  const roleConfig = {
    patient: { collection: 'patients', idField: 'patientId' },
    doctor: { collection: 'doctors', idField: 'doctorId' },
    lab: { collection: 'labs', idField: 'labId' },
    medicalStore: { collection: 'medical_stores', idField: 'storeId' },
  }[role];

  if (!roleConfig) {
    throw new HttpsError('invalid-argument', 'Unsupported role. Use patient, doctor, lab, or medicalStore.');
  }

  const profileId = String(
    data?.profileId
    || data?.[roleConfig.idField]
    || data?.patientId
    || data?.doctorId
    || data?.labId
    || data?.storeId
    || '',
  ).trim();
  if (!profileId) {
    throw new HttpsError('invalid-argument', `${roleConfig.idField} is required.`);
  }

  const roleRef = db.collection(roleConfig.collection).doc(profileId);
  const roleSnap = await roleRef.get();
  if (!roleSnap.exists) {
    throw new HttpsError('not-found', `${role} profile not found.`);
  }

  const roleData = roleSnap.data() || {};
  const ownerUid = String(roleData.ownerUid || '').trim();
  if (!ownerUid) {
    throw new HttpsError('failed-precondition', `${role} ownerUid is missing.`);
  }

  const now = FieldValue.serverTimestamp();
  const verifiedFields = {
    verified: true,
    verifiedAt: now,
    updatedAt: now,
    status: 'active',
  };

  const batch = db.batch();
  batch.set(roleRef, verifiedFields, { merge: true });
  batch.set(db.collection('users').doc(ownerUid), {
    verified: true,
    verifiedAt: now,
    updatedAt: now,
  }, { merge: true });
  await batch.commit();

  return { ok: true, role, profileId, ownerUid, verified: true };
}

async function approvePatientAccount(db, data, auth) {
  return approveUserAccount(db, { ...data, role: 'patient' }, auth);
}

const https = require('https');

/** Mask mobile for logs (never log full number + OTP together). */
function maskMsg91Mobile(mobileDigits) {
  const digits = String(mobileDigits || '').replace(/\D/g, '');
  if (digits.length < 4) return '91****';
  return `91******${digits.slice(-4)}`;
}

/**
 * Parse MSG91 OTP send API body. Success: { type: "success", message: "<requestId>" }.
 * @returns {{ ok: true, requestId: string, parsed: object|null } | { ok: false, reason: string, httpStatus: number, parsed: object|null, rawBody: string }}
 */
function parseMsg91OtpSendResponse(statusCode, rawBody) {
  const body = String(rawBody || '');
  let parsed = null;
  if (body.trim()) {
    try {
      parsed = JSON.parse(body);
    } catch (_) {
      parsed = null;
    }
  }

  const type = String(parsed?.type || '').trim().toLowerCase();
  const message = String(
    parsed?.message || parsed?.msg || parsed?.error || parsed?.errors || '',
  ).trim();

  if (statusCode >= 200 && statusCode < 300 && type === 'success') {
    return {
      ok: true,
      requestId: message || String(parsed?.request_id || parsed?.requestId || ''),
      parsed,
    };
  }

  const reason = message
    || (parsed ? JSON.stringify(parsed) : body)
    || `HTTP ${statusCode}`;

  return {
    ok: false,
    reason,
    httpStatus: statusCode,
    parsed,
    rawBody: body,
  };
}

function logMsg91Otp(event, fields) {
  const payload = {
    severity: fields.severity || 'INFO',
    component: 'msg91_otp',
    event,
    ...fields,
  };
  const line = JSON.stringify(payload);
  if (payload.severity === 'ERROR') {
    console.error(line);
  } else {
    console.info(line);
  }
}

function resolveMsg91TemplateId(otpType) {
  let envKey = 'MSG91_TEMPLATE_ID_REGISTRATION';
  if (otpType === 'login') envKey = 'MSG91_TEMPLATE_ID_LOGIN';
  if (otpType === 'password_reset' || otpType === 'forgot_password') {
    envKey = 'MSG91_TEMPLATE_ID_PASSWORD_RESET';
  }
  // Prefer type-specific ID; fall back to shared MSG91_TEMPLATE_ID.
  // Treat whitespace-only as unset (empty dotenv values must not win).
  const specific = String(process.env[envKey] || '').trim();
  const shared = String(process.env.MSG91_TEMPLATE_ID || '').trim();
  return specific || shared;
}

function resolveMsg91SenderId() {
  return String(process.env.MSG91_SENDER_ID || process.env.MSG91_SENDER || 'DRNECT')
    .trim()
    .toUpperCase();
}

/**
 * Builds the exact MSG91 v5 OTP request body + query.
 * template_id is REQUIRED for India DLT delivery — never omit it.
 */
function buildMsg91OtpRequest({ mobileDigits, code, templateId, senderId }) {
  const mobile = `91${mobileDigits}`;
  const queryParams = new URLSearchParams({
    mobile,
    otp: code,
    template_id: templateId,
  });
  const bodyObject = {
    template_id: templateId,
    mobile,
    otp: code,
    sender: senderId,
  };
  return {
    mobile,
    queryParams,
    bodyObject,
    payload: JSON.stringify(bodyObject),
  };
}

function requestMsg91Api({ authKey, path, method = 'GET' }) {
  const proxyUrl = String(process.env.MSG91_PROXY_URL || '').trim();
  const proxySecret = String(process.env.PROXY_SECRET || '').trim();

  // If a static IP Cloud Run proxy is configured, route through it to satisfy MSG91 IP allowlisting
  if (proxyUrl && proxySecret) {
    return new Promise((resolve, reject) => {
      const u = new URL(proxyUrl);
      const options = {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname + (path.startsWith('/') ? path : `/${path}`),
        method,
        headers: {
          authkey: authKey,
          'x-proxy-key': proxySecret,
          accept: 'application/json',
        },
      };

      const protocol = u.protocol === 'http:' ? require('http') : https;
      const req = protocol.request(options, (res) => {
        let responseData = '';
        res.on('data', (chunk) => { responseData += chunk; });
        res.on('end', () => {
          resolve({
            statusCode: res.statusCode || 0,
            body: responseData,
          });
        });
      });

      req.setTimeout(8000, () => {
        req.destroy(new Error('MSG91 proxy API request timed out'));
      });
      req.on('error', (err) => reject(err));
      req.end();
    });
  }

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'control.msg91.com',
      path,
      method,
      headers: {
        authkey: authKey,
        accept: 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let responseData = '';
      res.on('data', (chunk) => { responseData += chunk; });
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode || 0,
          body: responseData,
        });
      });
    });

    req.setTimeout(8000, () => {
      req.destroy(new Error('MSG91 API request timed out'));
    });
    req.on('error', (err) => reject(err));
    req.end();
  });
}

function parseMsg91OtpVerifyResponse(statusCode, rawBody) {
  const body = String(rawBody || '');
  let parsed = null;
  if (body.trim()) {
    try {
      parsed = JSON.parse(body);
    } catch (_) {
      parsed = null;
    }
  }
  const type = String(parsed?.type || '').trim().toLowerCase();
  const message = String(parsed?.message || parsed?.msg || '').trim().toLowerCase();
  if (statusCode >= 200 && statusCode < 300 && (type === 'success' || message.includes('already verified') || message.includes('verified success'))) {
    return { ok: true, parsed };
  }
  return {
    ok: false,
    httpStatus: statusCode,
    parsed,
    rawBody: body,
  };
}

/**
 * Confirms OTP against MSG91's active OTP session (source of truth for SMS content).
 * Returns false when auth key is missing or MSG91 rejects the code.
 */
async function verifyMsg91Otp(mobileDigits, otp) {
  const authKey = readMsg91AuthKey({ required: false });
  const normalizedMobile = normalizeMobileDigits(mobileDigits);
  const normalizedOtp = String(otp || '').trim();
  if (!authKey || !normalizedMobile || !/^\d{6}$/.test(normalizedOtp)) {
    console.warn('[verifyMsg91Otp] Skipped check: missing authKey, invalid mobile, or invalid otp format', {
      hasAuthKey: Boolean(authKey),
      hasMobile: Boolean(normalizedMobile),
      otpLength: normalizedOtp.length,
    });
    return false;
  }

  const query = new URLSearchParams({
    mobile: `91${normalizedMobile}`,
    otp: normalizedOtp,
  });

  try {
    const { statusCode, body } = await requestMsg91Api({
      authKey,
      path: `/api/v5/otp/verify?${query.toString()}`,
    });
    const parsed = parseMsg91OtpVerifyResponse(statusCode, body);
    if (!parsed.ok) {
      logMsg91Otp('verify_rejected', {
        severity: 'INFO',
        mobile: maskMsg91Mobile(normalizedMobile),
        httpStatus: statusCode,
        responseBody: body,
      });
      console.warn(`[verifyMsg91Otp] MSG91 rejected OTP for mobile ending ${normalizedMobile.slice(-4)}, httpStatus=${statusCode}, response=${body}`);
    } else {
      logMsg91Otp('verify_confirmed', {
        severity: 'INFO',
        mobile: maskMsg91Mobile(normalizedMobile),
        httpStatus: statusCode,
      });
      console.info(`[verifyMsg91Otp] MSG91 confirmed OTP for mobile ending ${normalizedMobile.slice(-4)}`);
    }
    return parsed.ok;
  } catch (err) {
    logMsg91Otp('verify_network_error', {
      severity: 'ERROR',
      mobile: maskMsg91Mobile(normalizedMobile),
      error: err?.message || String(err),
    });
    console.error(`[verifyMsg91Otp] MSG91 network error for mobile ending ${normalizedMobile.slice(-4)}:`, err?.message || err);
    return false;
  }
}

/** Resends the same MSG91 OTP (do not rotate local hash on resend). */
async function retryMsg91SmsOtp(mobileDigits) {
  const authKey = readMsg91AuthKey({ required: false });
  const normalizedMobile = normalizeMobileDigits(mobileDigits);
  if (!authKey) {
    throw new HttpsError(
      'unavailable',
      'SMS service is temporarily unavailable. Please try again later.',
    );
  }
  if (!normalizedMobile) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }

  const query = new URLSearchParams({
    mobile: `91${normalizedMobile}`,
    retrytype: 'text',
  });

  const { statusCode, body } = await requestMsg91Api({
    authKey,
    path: `/api/v5/otp/retry?${query.toString()}`,
  });

  const parsed = parseMsg91OtpSendResponse(statusCode, body);
  if (!parsed.ok) {
    logMsg91Otp('retry_rejected', {
      severity: 'ERROR',
      mobile: maskMsg91Mobile(normalizedMobile),
      httpStatus: parsed.httpStatus,
      responseBody: body,
    });
    throw new HttpsError(
      'failed-precondition',
      'OTP session expired. Send a new one.',
    );
  }

  logMsg91Otp('retry_confirmed', {
    mobile: maskMsg91Mobile(normalizedMobile),
    httpStatus: statusCode,
    requestId: parsed.requestId,
  });
}

function postMsg91OtpRequest({ authKey, mobileDigits, code, templateId, senderId }) {
  const built = buildMsg91OtpRequest({ mobileDigits, code, templateId, senderId });
  const proxyUrl = String(process.env.MSG91_PROXY_URL || '').trim();
  const proxySecret = String(process.env.PROXY_SECRET || '').trim();

  // If a static IP Cloud Run proxy is configured, route through it to satisfy MSG91 IP allowlisting
  if (proxyUrl && proxySecret) {
    return new Promise((resolve, reject) => {
      const u = new URL(proxyUrl);
      const postData = JSON.stringify({
        mobile: built.mobile,
        otp: code,
        template_id: templateId,
        sender: senderId,
      });

      const options = {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname + u.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-proxy-key': proxySecret,
          'Content-Length': Buffer.byteLength(postData),
        },
      };

      const protocol = u.protocol === 'http:' ? require('http') : https;
      const req = protocol.request(options, (res) => {
        let responseData = '';
        res.on('data', (chunk) => { responseData += chunk; });
        res.on('end', () => {
          resolve({
            statusCode: res.statusCode || 0,
            body: responseData,
            requestPayload: {
              template_id: templateId,
              mobile: built.mobile,
              sender: senderId,
              otp: '[REDACTED]',
              routedVia: 'cloud_run_proxy',
            },
          });
        });
      });

      req.on('error', (err) => reject(err));
      req.write(postData);
      req.end();
    });
  }

  // Direct fallback to control.msg91.com
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'control.msg91.com',
      path: `/api/v5/otp?${built.queryParams.toString()}`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        authkey: authKey,
        'Content-Length': Buffer.byteLength(built.payload),
      },
    };

    const req = https.request(options, (res) => {
      let responseData = '';
      res.on('data', (chunk) => { responseData += chunk; });
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode || 0,
          body: responseData,
          requestPayload: {
            template_id: templateId,
            mobile: built.mobile,
            sender: senderId,
            otp: '[REDACTED]',
            routedVia: 'direct',
          },
        });
      });
    });

    req.on('error', (err) => reject(err));
    req.write(built.payload);
    req.end();
  });
}

/**
 * Sends OTP SMS via MSG91 v5. Throws HttpsError('unavailable') on any failure.
 * Fail-closed: refuses to call MSG91 without a DLT-mapped template_id.
 * @returns {Promise<{ requestId: string }>}
 */
async function sendMsg91SmsOtp(mobileDigits, code, otpType = 'registration') {
  const authKey = readMsg91AuthKey({ required: false });

  const templateId = resolveMsg91TemplateId(otpType);
  const senderId = resolveMsg91SenderId();
  const maskedMobile = maskMsg91Mobile(mobileDigits);

  if (!authKey) {
    logMsg91Otp('missing_auth_key', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId: templateId || null,
      senderId,
    });
    throw new HttpsError(
      'unavailable',
      'SMS service is temporarily unavailable. Please try again later.',
    );
  }

  // India DLT: MSG91 may return type=success without template_id, but carriers
  // drop the SMS. Never send without the DLT-mapped MSG91 template ID.
  if (!templateId) {
    logMsg91Otp('missing_template_id', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId: null,
      senderId,
      envKeysChecked: [
        'MSG91_TEMPLATE_ID_REGISTRATION',
        'MSG91_TEMPLATE_ID_LOGIN',
        'MSG91_TEMPLATE_ID_PASSWORD_RESET',
        'MSG91_TEMPLATE_ID',
      ],
    });
    throw new HttpsError(
      'failed-precondition',
      'SMS template is not configured. Contact support.',
    );
  }

  if (!senderId || senderId.length < 3 || senderId.length > 6) {
    logMsg91Otp('invalid_sender_id', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId: senderId || null,
    });
    throw new HttpsError(
      'failed-precondition',
      'SMS sender ID is not configured. Contact support.',
    );
  }

  try {
    const { statusCode, body, requestPayload } = await postMsg91OtpRequest({
      authKey,
      mobileDigits,
      code,
      templateId,
      senderId,
    });

    logMsg91Otp('send_response', {
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId,
      httpStatus: statusCode,
      requestPayload,
      responseBody: body,
    });

    const parsed = parseMsg91OtpSendResponse(statusCode, body);
    if (!parsed.ok) {
      logMsg91Otp('send_rejected', {
        severity: 'ERROR',
        otpType,
        mobile: maskedMobile,
        templateId,
        senderId,
        httpStatus: parsed.httpStatus,
        failureReason: parsed.reason,
        requestPayload,
        responseBody: body,
        parsed: parsed.parsed,
      });
      if (parsed.parsed && (parsed.parsed.code === '418' || parsed.parsed.code === 418 || parsed.reason?.includes('AuthenticationFailure'))) {
        throw new HttpsError(
          'unavailable',
          'SMS gateway authentication rejected: Server IP not whitelisted in MSG91. Please whitelist the outbound IP or route through the Cloud Run proxy.',
        );
      }
      throw new HttpsError(
        'unavailable',
        'Could not send OTP SMS right now. Please try again in a few minutes.',
      );
    }

    logMsg91Otp('send_confirmed', {
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId,
      httpStatus: statusCode,
      requestId: parsed.requestId,
      requestPayload,
      responseBody: body,
      parsed: parsed.parsed,
      dltTemplateAttached: true,
    });

    return { requestId: parsed.requestId, templateId, senderId };
  } catch (err) {
    if (err instanceof HttpsError) throw err;

    logMsg91Otp('send_network_error', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId,
      error: err?.message || String(err),
    });
    throw new HttpsError(
      'unavailable',
      'Could not reach SMS service. Please try again later.',
    );
  }
}

const REGISTRATION_MOBILE_EXISTS_MESSAGE =
  'This mobile number may already be registered. Try logging in, or use a different number.';
const LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE =
  'This mobile number may be registered under a different account type. Try another login option or contact support.';

/** Pure conflict resolver for mobile lookup (login vs registration intent). */
function resolveMobileLookupConflict({ found, registeredRole, requestedRole, intent }) {
  if (!found) return false;
  if (intent === 'registration') return true;
  if (!requestedRole) return true;
  return String(registeredRole || '').trim() !== String(requestedRole || '').trim();
}

async function usersDocExists(db, uid) {
  const normalized = String(uid || '').trim();
  if (!normalized) return false;
  const snap = await db.collection('users').doc(normalized).get();
  return snap.exists;
}

function accountUidFromRoleDoc(role, data) {
  const row = data || {};
  if (role === 'ambulance') {
    const authUid = String(row.authUid || '').trim();
    if (authUid) return authUid;
  }
  return String(row.ownerUid || '').trim();
}

async function resolveActiveAccountUid(db, role, doc) {
  const directUid = accountUidFromRoleDoc(role, doc.data());
  if (directUid && (await usersDocExists(db, directUid))) {
    return directUid;
  }
  const profileId = String(doc.id || '').trim();
  if (!profileId) return null;
  const userSnap = await db.collection('users').where('profileId', '==', profileId).limit(1).get();
  if (userSnap.empty) return null;
  const uid = userSnap.docs[0].id;
  if (uid && (await usersDocExists(db, uid))) return uid;
  return null;
}

async function findUserByMobileDigits(db, digits) {
  const candidates = [digits, `+91${digits}`, `+91 ${digits}`, `+91-${digits}`, `91${digits}`, `0${digits}`];
  const fields = ['mobile', 'phone', 'phoneNumber', 'mobileNumber'];
  const collectionMap = {
    patient: 'patients',
    doctor: 'doctors',
    medicalStore: 'medical_stores',
    lab: 'labs',
    ambulance: 'ambulances',
  };

  // 1. Search users collection in parallel
  const userQueries = [];
  for (const candidate of candidates) {
    for (const field of fields) {
      userQueries.push(
        db.collection('users').where(field, '==', candidate).limit(1).get()
      );
    }
  }
  const userSnapshots = await Promise.all(userQueries);
  for (const snap of userSnapshots) {
    if (!snap.empty) {
      const doc = snap.docs[0];
      return { found: true, role: doc.data()?.role, uid: doc.id, data: doc.data() };
    }
  }

  // 2. Search role collections in parallel
  const roleQueries = [];
  for (const [r, coll] of Object.entries(collectionMap)) {
    for (const candidate of candidates) {
      for (const field of fields) {
        roleQueries.push(
          db.collection(coll).where(field, '==', candidate).limit(1).get().then(snap => {
            if (!snap.empty) {
              return { role: r, doc: snap.docs[0] };
            }
            return null;
          })
        );
      }
    }
  }
  const roleSnapshots = await Promise.all(roleQueries);
  const roleMatch = roleSnapshots.find(Boolean);
  if (roleMatch) {
    const doc = roleMatch.doc;
    const uid = await resolveActiveAccountUid(db, roleMatch.role, doc);
    if (uid) {
      return { found: true, role: roleMatch.role, uid, data: doc.data() };
    }
  }

  return { found: false, role: null, uid: null, data: null };
}

async function findUserByEmail(db, email) {
  const normalized = String(email || '').trim().toLowerCase();
  if (!normalized || !normalized.includes('@')) return { found: false, role: null, uid: null, data: null };

  const collectionMap = {
    patient: 'patients',
    doctor: 'doctors',
    medicalStore: 'medical_stores',
    lab: 'labs',
    ambulance: 'ambulances',
  };

  // 1. Check users collection
  const userSnap = await db.collection('users').where('email', '==', normalized).limit(1).get();
  if (!userSnap.empty) {
    const doc = userSnap.docs[0];
    return { found: true, role: doc.data()?.role, uid: doc.id, data: doc.data() };
  }

  // 2. Check role collections in parallel
  const roleQueries = Object.entries(collectionMap).map(([r, coll]) =>
    db.collection(coll).where('email', '==', normalized).limit(1).get().then(snap => {
      if (!snap.empty) return { role: r, doc: snap.docs[0] };
      return null;
    })
  );
  const roleSnapshots = await Promise.all(roleQueries);
  const roleMatch = roleSnapshots.find(Boolean);
  if (roleMatch) {
    const doc = roleMatch.doc;
    const uid = await resolveActiveAccountUid(db, roleMatch.role, doc);
    if (uid) {
      return { found: true, role: roleMatch.role, uid, data: doc.data() };
    }
  }

  return { found: false, role: null, uid: null, data: null };
}

async function sendUserRegistrationOtp(db, data, { clientIp = 'unknown' } = {}) {
  const role = String(data?.role || 'patient').trim();
  const otpType = String(data?.otpType || 'registration').trim();
  assertSupportedRole(role);

  const emailInput = String(data?.email || '').trim().toLowerCase();
  const isEmail = emailInput.includes('@');
  if (isEmail) {
    throw new HttpsError('invalid-argument', 'Email OTP is disabled. Please enter your 10-digit mobile number for phone SMS verification.');
  }

  const digits = normalizeMobileDigits(data?.mobile || data?.identifier);
  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }

  if (otpType === 'registration') {
    const search = await findUserByMobileDigits(db, digits);
    if (search.found) {
      console.warn('[sendUserRegistrationOtp] Registration blocked: mobile already registered', {
        mobileSuffix: digits.slice(-4),
        existingRole: search.role,
      });
      throw new HttpsError('already-exists', REGISTRATION_MOBILE_EXISTS_MESSAGE);
    }
  }

  if (otpType === 'login' || otpType === 'forgot_password') {
    let search = await findUserByMobileDigits(db, digits);
    const isDemo = await isDemoPhone(digits, role);
    if ((!search.found || !search.uid) && isDemo) {
      try {
        search = await ensureDemoAccount(db, digits, role);
      } catch (err) {
        console.warn('[sendUserRegistrationOtp] Failed to ensure demo account:', err.message);
      }
    }
    if (!search.found) {
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }
    if (search.role && search.role !== role) {
      console.warn('[sendUserRegistrationOtp] Login blocked: account type mismatch', {
        mobileSuffix: digits.slice(-4),
        requestedRole: role,
        existingRole: search.role,
      });
      throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
    }
    if (search.uid && otpType === 'login') {
      await db.collection('users').doc(search.uid).set({
        role,
        mobile: digits,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }

  await enforceSendOtpRateLimits(db, { clientIp, role, digits });

  const challengeRef = db.collection('otp_challenges').doc(mobileHash(role, digits));
  const existing = await challengeRef.get();
  const isDemoAccount = await isDemoPhone(digits, role);

  if (existing.exists && !isDemoAccount) {
    const existingData = existing.data() || {};
    const lastSentAt = existingData.sentAt?.toDate?.();
    if (lastSentAt && Date.now() - lastSentAt.getTime() < RESEND_COOLDOWN_MS) {
      throw new HttpsError(
        'resource-exhausted',
        'Please wait a minute before requesting another OTP.',
      );
    }
    // MSG91 retry resends the same OTP session; rotating our hash breaks verify.
    if (!isTestMode() && existingData.otpHash) {
      const expiryMs = OTP_EXPIRY_MS;
      const expiresAt = Timestamp.fromDate(new Date(Date.now() + expiryMs));
      try {
        await retryMsg91SmsOtp(digits);
        await challengeRef.set({
          sentAt: FieldValue.serverTimestamp(),
          expiresAt,
          attempts: 0,
        }, { merge: true });
        return {
          ok: true,
          expiresInSeconds: Math.floor(expiryMs / 1000),
        };
      } catch (err) {
        if (err instanceof HttpsError) throw err;
        logMsg91Otp('retry_network_error', {
          severity: 'ERROR',
          mobile: maskMsg91Mobile(digits),
          error: err?.message || String(err),
        });
      }
    }
  }


  const config = await getDemoConfig();
  if (isDemoAccount && (!config || !config.demoOtp)) {
    throw new HttpsError('internal', 'Demo configuration missing demoOtp');
  }

  const code = isDemoAccount ? config.demoOtp : generateOtpCode();
  // 10 years for demo expiry if we want it long lived, or just standard if not defined
  const expiryMs = isDemoAccount ? (365 * 24 * 60 * 60 * 1000) : OTP_EXPIRY_MS;
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + expiryMs));

  await challengeRef.set({
    role,
    mobileDigits: digits,
    otpHash: hashOtp(code),
    expiresAt,
    sentAt: FieldValue.serverTimestamp(),
    attempts: 0,
    ...(isDemoAccount ? { demoAccount: true } : {}),
  });

  // Mirror OTP challenge token in Redis cache if available
  try {
    const { redis } = require('./redis');
    if (redis && digits) {
      const ttlSec = Math.max(1, Math.floor(expiryMs / 1000));
      const redisPayload = JSON.stringify({
        code,
        otpHash: hashOtp(code),
        role,
        mobileDigits: digits,
        expiresAt: Date.now() + expiryMs,
      });
      await Promise.all([
        redis.set(`otp:challenge:${digits}`, redisPayload, 'EX', ttlSec).catch(() => {}),
        redis.set(`otp:challenge:${role}:${digits}`, redisPayload, 'EX', ttlSec).catch(() => {}),
      ]);
      console.info(`[sendUserRegistrationOtp] OTP cached in Redis for mobile ending ${digits.slice(-4)}`);
    }
  } catch (redisErr) {
    console.warn('[sendUserRegistrationOtp] Redis cache write skipped:', redisErr.message);
  }

  // Outbound MSG91 API call via VPC Connector (static IP).
  try {
    if (isDemoAccount) {
      // No SMS — demo/store-review number for this role only; OTP comes from Firestore.
    } else if (!isTestMode()) {
      await sendMsg91SmsOtp(digits, code, otpType);
    } else {
      console.info(`OTP test mode active for mobile ending ${digits.slice(-4)}`);
    }
  } catch (err) {
    await challengeRef.delete().catch(() => {});
    try {
      const { redis } = require('./redis');
      if (redis && digits) {
        await Promise.all([
          redis.del(`otp:challenge:${digits}`).catch(() => {}),
          redis.del(`otp:challenge:${role}:${digits}`).catch(() => {}),
        ]).catch(() => {});
      }
    } catch (_) {}
    throw err;
  }

  return {
    ok: true,
    expiresInSeconds: Math.floor(expiryMs / 1000),
    ...(isTestMode() && !isDemoAccount ? { debugOtp: DEV_TEST_OTP } : {}),
  };
}

async function isChallengeOtpValid({ otp, challenge, isDemoAccount, demoOtp }) {
  const entered = String(otp || '').trim();
  if (isDemoAccount && demoOtp != null && entered === String(demoOtp).trim()) {
    return true;
  }
  if (!isDemoAccount && isTestMode() && entered === DEV_TEST_OTP) {
    return true;
  }
  if (otpHashesEqual(hashOtp(otp), challenge.otpHash)) {
    return true;
  }
  if (isTestMode() || isDemoAccount) {
    return false;
  }
  return verifyMsg91Otp(challenge.mobileDigits, otp);
}

/**
 * Atomically validates an OTP challenge, increments failed attempts, or consumes it.
 * Prevents concurrent verify calls from bypassing lockout or reusing a challenge.
 *
 * Supports fast-path local hash match, Redis cached challenge token, and fallback
 * to MSG91 verify API when MSG91 delivers its own gateway-generated OTP.
 */
async function consumeOtpChallengeAtomically(
  db,
  { challengeKey, otp, isDemoAccount, mobileDigits, role },
) {
  const challengeRef = db.collection('otp_challenges').doc(challengeKey);
  const digits = normalizeMobileDigits(mobileDigits);
  const normalizedRole = role ? normalizeRole(role) : null;

  // 1. Locate challenge document: primary key, fallback by mobileDigits if role differed
  let effectiveChallengeRef = challengeRef;
  if (typeof challengeRef.get === 'function') {
    try {
      const initialSnap = await challengeRef.get();
      if (!initialSnap.exists && digits && typeof db.collection === 'function') {
        const query = db.collection('otp_challenges');
        if (typeof query.where === 'function') {
          const fallbackSnap = await query.where('mobileDigits', '==', digits).limit(1).get();
          if (fallbackSnap && !fallbackSnap.empty) {
            console.info(
              `[consumeOtpChallengeAtomically] Found challenge via mobileDigits fallback for mobile ending ${digits.slice(-4)}`,
            );
            effectiveChallengeRef = fallbackSnap.docs[0].ref;
          }
        }
      }
    } catch (_) {}
  }

  // 2. Query Redis cache for OTP token
  let redisChallenge = null;
  let redisClient = null;
  try {
    redisClient = require('./redis').redis;
    if (redisClient && digits) {
      const raw = (await redisClient.get(`otp:challenge:${digits}`).catch(() => null))
        || (normalizedRole ? await redisClient.get(`otp:challenge:${normalizedRole}:${digits}`).catch(() => null) : null);
      if (raw) {
        redisChallenge = JSON.parse(raw);
        console.info(`[consumeOtpChallengeAtomically] REDIS_KEY_FOUND for mobile ending ${digits.slice(-4)}`);
      } else {
        console.info(`[consumeOtpChallengeAtomically] REDIS_KEY_NOT_FOUND for mobile ending ${digits.slice(-4)}`);
      }
    }
  } catch (redisErr) {
    console.warn('[consumeOtpChallengeAtomically] Redis lookup skipped:', redisErr.message);
  }

  const demoConfig = await getDemoConfig();
  const demoOtp =
    demoConfig?.demoOtp != null ? String(demoConfig.demoOtp).trim() : null;

  // 3. Atomically check challenge state and fast-path local hash match
  const outcome = await db.runTransaction(async (tx) => {
    const challengeSnap = await tx.get(effectiveChallengeRef);
    if (!challengeSnap.exists) {
      return { status: 'missing' };
    }

    const challenge = challengeSnap.data() || {};
    const expiresAt = challenge.expiresAt?.toDate?.();
    if (!expiresAt || Date.now() > expiresAt.getTime()) {
      tx.delete(effectiveChallengeRef);
      return { status: 'expired' };
    }

    const attempts = Number(challenge.attempts) || 0;
    if (attempts >= 5) {
      tx.delete(effectiveChallengeRef);
      return { status: 'locked' };
    }

    const treatAsDemo = isDemoAccount || challenge.demoAccount === true;
    const localMatch = otpHashesEqual(hashOtp(otp), challenge.otpHash)
      || (treatAsDemo && demoOtp != null && otp === demoOtp)
      || (!treatAsDemo && isTestMode() && otp === DEV_TEST_OTP)
      || (redisChallenge?.otpHash && otpHashesEqual(hashOtp(otp), redisChallenge.otpHash))
      || (redisChallenge?.code && String(redisChallenge.code).trim() === otp);

    if (localMatch) {
      tx.delete(effectiveChallengeRef);
      return { status: 'consumed', challenge, treatAsDemo };
    }

    // Local hash didn't match. Check if MSG91 verify API should be queried outside transaction.
    const canCheckMsg91 = !treatAsDemo && !isTestMode() && Boolean(challenge.mobileDigits || digits);
    if (canCheckMsg91) {
      return { status: 'check_msg91', challenge, attempts };
    }

    // No MSG91 fallback available (e.g. test mode, demo, or missing mobile). Increment attempts.
    tx.set(effectiveChallengeRef, { attempts: attempts + 1 }, { merge: true });
    return { status: 'invalid', attempts: attempts + 1, challenge };
  });

  // Handle immediate outcomes
  if (outcome.status === 'consumed') {
    if (redisClient && digits) {
      await Promise.all([
        redisClient.del(`otp:challenge:${digits}`).catch(() => {}),
        normalizedRole ? redisClient.del(`otp:challenge:${normalizedRole}:${digits}`).catch(() => {}) : Promise.resolve(),
      ]).catch(() => {});
    }
    console.info(`[consumeOtpChallengeAtomically] OTP_VERIFIED successfully (local match) for mobile ending ${digits ? digits.slice(-4) : 'unknown'}`);
    return { consumed: true };
  }

  if (outcome.status === 'missing') {
    console.warn(`[consumeOtpChallengeAtomically] OTP_NOT_FOUND (Firestore missing) for challengeKey=${challengeKey}`);
    throw new HttpsError('failed-precondition', 'Send OTP first.');
  }

  if (outcome.status === 'expired') {
    console.warn(`[consumeOtpChallengeAtomically] OTP_EXPIRED for mobile ending ${digits ? digits.slice(-4) : 'unknown'}`);
    if (redisClient && digits) {
      await Promise.all([
        redisClient.del(`otp:challenge:${digits}`).catch(() => {}),
        normalizedRole ? redisClient.del(`otp:challenge:${normalizedRole}:${digits}`).catch(() => {}) : Promise.resolve(),
      ]).catch(() => {});
    }
    throw new HttpsError('deadline-exceeded', 'OTP expired. Send a new one.');
  }

  if (outcome.status === 'locked') {
    console.warn(`[consumeOtpChallengeAtomically] OTP_LOCKED for mobile ending ${digits ? digits.slice(-4) : 'unknown'}`);
    if (redisClient && digits) {
      await Promise.all([
        redisClient.del(`otp:challenge:${digits}`).catch(() => {}),
        normalizedRole ? redisClient.del(`otp:challenge:${normalizedRole}:${digits}`).catch(() => {}) : Promise.resolve(),
      ]).catch(() => {});
    }
    throw new HttpsError('resource-exhausted', 'Too many invalid attempts. Send a new OTP.');
  }

  if (outcome.status === 'invalid') {
    console.warn(`[consumeOtpChallengeAtomically] INVALID_CODE attempt ${outcome.attempts}/5 for mobile ending ${digits ? digits.slice(-4) : 'unknown'}`);
    throw new HttpsError('permission-denied', 'Invalid OTP.');
  }

  // 4. If status is 'check_msg91', query MSG91 v5 OTP verify API
  if (outcome.status === 'check_msg91') {
    const mobileForMsg91 = outcome.challenge.mobileDigits || digits;
    console.info(`[consumeOtpChallengeAtomically] Querying MSG91 verify API for mobile ending ${mobileForMsg91.slice(-4)}`);
    const msg91Valid = await verifyMsg91Otp(mobileForMsg91, otp);

    if (msg91Valid) {
      // Consume challenge document atomically
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(effectiveChallengeRef);
        if (snap.exists) {
          tx.delete(effectiveChallengeRef);
        }
      });
      if (redisClient && digits) {
        await Promise.all([
          redisClient.del(`otp:challenge:${digits}`).catch(() => {}),
          normalizedRole ? redisClient.del(`otp:challenge:${normalizedRole}:${digits}`).catch(() => {}) : Promise.resolve(),
        ]).catch(() => {});
      }
      console.info(`[consumeOtpChallengeAtomically] OTP_VERIFIED successfully (MSG91 API confirmed) for mobile ending ${mobileForMsg91.slice(-4)}`);
      return { consumed: true };
    }

    // Both local hash and MSG91 rejected the code -> Increment attempts
    const failOutcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(effectiveChallengeRef);
      if (!snap.exists) return { status: 'missing' };
      const curAttempts = (Number(snap.data()?.attempts) || 0) + 1;
      if (curAttempts >= 5) {
        tx.delete(effectiveChallengeRef);
        return { status: 'locked', attempts: curAttempts };
      }
      tx.set(effectiveChallengeRef, { attempts: curAttempts }, { merge: true });
      return { status: 'invalid', attempts: curAttempts };
    });

    console.warn(`[consumeOtpChallengeAtomically] INVALID_CODE (MSG91 rejected) attempt ${failOutcome.attempts}/5 for mobile ending ${mobileForMsg91.slice(-4)}`);
    if (failOutcome.status === 'locked') {
      if (redisClient && digits) {
        await Promise.all([
          redisClient.del(`otp:challenge:${digits}`).catch(() => {}),
          normalizedRole ? redisClient.del(`otp:challenge:${normalizedRole}:${digits}`).catch(() => {}) : Promise.resolve(),
        ]).catch(() => {});
      }
      throw new HttpsError('resource-exhausted', 'Too many invalid attempts. Send a new OTP.');
    }
    throw new HttpsError('permission-denied', 'Invalid OTP.');
  }

  throw new HttpsError('internal', 'OTP verification failed.');
}

/**
 * Atomically validates and consumes an OTP verification session.
 * Prevents concurrent completion calls from reusing the same session.
 */
async function consumeOtpVerificationSessionAtomically(
  db,
  sessionId,
  {
    assertSession,
    messages = {},
  } = {},
) {
  const msg = {
    missing: 'OTP verification session expired. Verify again.',
    alreadyUsed: 'OTP verification session already used.',
    expired: 'OTP verification session expired. Verify again.',
    ...messages,
  };
  const sessionRef = db.collection('otp_verification_sessions').doc(sessionId);

  const outcome = await db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) {
      return { status: 'missing' };
    }

    const session = sessionSnap.data() || {};
    if (session.consumed === true) {
      return { status: 'already_used' };
    }

    const expiresAt = session.expiresAt?.toDate?.();
    if (!expiresAt || Date.now() > expiresAt.getTime()) {
      tx.delete(sessionRef);
      return { status: 'expired' };
    }

    if (assertSession) {
      try {
        assertSession(session);
      } catch (err) {
        if (err instanceof HttpsError) {
          return {
            status: 'rejected',
            errorCode: err.code,
            errorMessage: err.message,
          };
        }
        throw err;
      }
    }

    tx.set(sessionRef, {
      consumed: true,
      consumedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { status: 'consumed', session };
  });

  switch (outcome.status) {
    case 'missing':
      throw new HttpsError('failed-precondition', msg.missing);
    case 'already_used':
      throw new HttpsError('failed-precondition', msg.alreadyUsed);
    case 'expired':
      throw new HttpsError('deadline-exceeded', msg.expired);
    case 'rejected':
      throw new HttpsError(outcome.errorCode, outcome.errorMessage);
    case 'consumed':
      return outcome.session;
    default:
      throw new HttpsError('internal', 'OTP session verification failed.');
  }
}

function assertAmbulanceOtpSession(session, mobileDigits) {
  if (session.role !== 'ambulance' || session.mobileVerified !== true) {
    throw new HttpsError('failed-precondition', 'OTP verification incomplete.');
  }

  const sessionMobile = normalizeMobileDigits(session.mobileDigits);
  if (!sessionMobile || !mobileDigits || sessionMobile !== mobileDigits) {
    throw new HttpsError(
      'permission-denied',
      'Registered mobile does not match OTP verification.',
    );
  }
}

async function verifyUserRegistrationOtp(db, data, auth, { clientIp = 'unknown' } = {}) {
  const role = normalizeRole(data?.role || 'patient');
  assertSupportedRole(role);

  const emailInput = String(data?.email || data?.identifier || '').trim().toLowerCase();
  const isEmail = emailInput.includes('@');
  if (isEmail) {
    throw new HttpsError('invalid-argument', 'Email verification is disabled. Please verify via mobile phone SMS OTP.');
  }

  const digits = normalizeMobileDigits(data?.mobile || data?.identifier);
  const otp = String(data?.otp || '').trim();
  const otpType = String(data?.otpType || 'registration').trim();

  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError('invalid-argument', 'Enter the 6-digit OTP.');
  }

  console.info('[verifyUserRegistrationOtp] Starting verification', {
    role,
    otpType,
    mobileLast4: digits.slice(-4),
    otpLength: otp.length,
    hasAuth: Boolean(auth?.uid),
  });

  await enforceVerifyOtpRateLimits(db, { clientIp, role, digits });

  const challengeKey = mobileHash(role, digits);
  const isDemoAccount = await isDemoPhone(digits, role);

  await consumeOtpChallengeAtomically(db, {
    challengeKey,
    otp,
    isDemoAccount,
    mobileDigits: digits,
    role,
  });

  const verifiedAt = FieldValue.serverTimestamp();
  const sessionExpiresAt = Timestamp.fromDate(new Date(Date.now() + SESSION_EXPIRY_MS));
  const sessionId = crypto.randomBytes(16).toString('hex');

  // Signed-in account — refresh mobileVerified only when users/{uid} already exists
  // and the caller explicitly intends to update their contact info (contact_change).
  // For standard registration or mobile login, never let a stale auth token block verification.
  if (auth?.uid && !isEmail && otpType === 'contact_change') {
    const userProfile = await readUserProfile(db, auth.uid);
    if (userProfile) {
      const signedInRoles = new Set(['patient', 'doctor', 'lab', 'medicalStore', 'ambulance']);
      const userRole = String(userProfile.role || '').trim();
      if (!signedInRoles.has(userRole)) {
        throw new HttpsError('permission-denied', 'Supported account role required.');
      }

      const profileMobile = normalizeMobileDigits(userProfile.mobile);
      if (!profileMobile || profileMobile !== digits) {
        throw new HttpsError(
          'permission-denied',
          'OTP mobile number does not match your account.',
        );
      }

      await markUserMobileVerified(db, {
        uid: auth.uid,
        mobileDigits: digits,
        role: userRole,
      });

      return {
        ok: true,
        mobileVerified: true,
        sessionId: null,
      };
    }
  }

  // Handles user and ambulance registration OTPs via MSG91 — session used after signup or ambulance PIN reset.
  await db.collection('otp_verification_sessions').doc(sessionId).set({
    role,
    identifier: isEmail ? emailInput : digits,
    email: isEmail ? emailInput : null,
    mobileDigits: isEmail ? null : digits,
    mobileVerified: !isEmail,
    emailVerified: isEmail,
    verifiedAt,
    expiresAt: sessionExpiresAt,
    consumed: false,
  });

  if (!isEmail) {
    await db.collection('otp_verification_sessions').doc(mobileHash(role, digits)).set({
      role,
      mobileDigits: digits,
      mobileVerified: true,
      verifiedAt,
      expiresAt: sessionExpiresAt,
      sessionId,
      consumed: false,
    });
  }

  // Phone OTP login must establish a real Firebase Auth session.
  if (otpType === 'login') {
    let search = await findUserByMobileDigits(db, digits);
    const isDemo = await isDemoPhone(digits, role);
    if ((!search.found || !search.uid) && isDemo) {
      try {
        search = await ensureDemoAccount(db, digits, role);
      } catch (err) {
        console.warn('[verifyUserRegistrationOtp] Failed to ensure demo account:', err.message);
      }
    }
    if (!search.found || !search.uid) {
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }
    if (search.role && normalizeRole(search.role) !== role) {
      console.warn('[verifyUserRegistrationOtp] Login blocked: account type mismatch', {
        mobileSuffix: digits.slice(-4),
        requestedRole: role,
        existingRole: search.role,
      });
      throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
    }
    if (isDemo && search.uid) {
      if (role === 'doctor') {
        await ensureDoctorFullVerified(db, search.uid, search.data?.profileId, { mobile: digits });
      } else {
        await ensureRoleFullVerified(db, search.uid, role, search.data?.profileId, { mobile: digits });
      }
    }
    const customToken = await getAuth().createCustomToken(search.uid, { role });
    console.info('[verifyUserRegistrationOtp] Login OTP verified successfully, customToken minted', {
      role,
      mobileLast4: digits.slice(-4),
      uid: search.uid,
    });
    return {
      ok: true,
      mobileVerified: true,
      sessionId,
      customToken,
      uid: search.uid,
    };
  }

  console.info('[verifyUserRegistrationOtp] Registration OTP verified successfully, sessionId generated', {
    role,
    mobileLast4: digits.slice(-4),
    sessionId,
  });

  return {
    ok: true,
    mobileVerified: !isEmail,
    emailVerified: isEmail,
    sessionId,
  };
}

async function finalizePatientOtpVerification(db, data, auth) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required to finalize verification.');
  }

  const sessionId = String(data?.sessionId || '').trim();
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'sessionId is required.');
  }

  const userProfile = await readUserProfile(db, auth.uid);
  const userRole = String(userProfile?.role || '').trim();
  if (!userProfile || !['patient', 'doctor', 'lab', 'medicalStore', 'ambulance'].includes(userRole)) {
    throw new HttpsError('permission-denied', 'Supported account role required.');
  }

  const profileId = String(userProfile.profileId || '').trim();
  if (!profileId) {
    throw new HttpsError('failed-precondition', 'Patient profile not found.');
  }

  const session = await consumeOtpVerificationSessionAtomically(db, sessionId, {
    assertSession: (sessionData) => {
      if (sessionData.role !== userRole || sessionData.mobileVerified !== true) {
        throw new HttpsError('failed-precondition', 'OTP verification incomplete.');
      }

      const sessionMobile = normalizeMobileDigits(sessionData.mobileDigits);
      const profileMobile = normalizeMobileDigits(userProfile.mobile);
      if (!sessionMobile || !profileMobile || sessionMobile !== profileMobile) {
        throw new HttpsError(
          'permission-denied',
          'Registered mobile does not match OTP verification.',
        );
      }
    },
  });

  const sessionMobile = normalizeMobileDigits(session.mobileDigits);
  await markUserMobileVerified(db, {
    uid: auth.uid,
    mobileDigits: sessionMobile,
    role: userRole,
  });

  return { ok: true, mobileVerified: true, profileId };
}

const PIN_RESET_IP_WINDOW_MS = 60 * 60 * 1000;
const PIN_RESET_IP_MAX = 10;
const PIN_RESET_MOBILE_WINDOW_MS = 60 * 60 * 1000;
const PIN_RESET_MOBILE_MAX = 5;

async function enforcePinResetRateLimits(db, { clientIp, mobileDigits }) {
  await assertOtpRateLimit(db, {
    bucket: `reset_pin_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: PIN_RESET_IP_WINDOW_MS,
    maxAttempts: PIN_RESET_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `reset_pin_mobile_${mobileHash('ambulance', mobileDigits)}`,
    windowMs: PIN_RESET_MOBILE_WINDOW_MS,
    maxAttempts: PIN_RESET_MOBILE_MAX,
  });
}

function phoneLookupCandidates(phone) {
  const trimmed = String(phone || '').trim();
  const candidates = new Set([trimmed, trimmed.replace(/\s+/g, '')]);
  const digits = trimmed.replace(/\D/g, '');
  if (digits.length >= 10) {
    const lastTen = digits.slice(-10);
    candidates.add(lastTen);
    candidates.add(`+91${lastTen}`);
  }
  return [...candidates].filter(Boolean);
}

function isRegisteredAmbulanceData(data) {
  const username = String(data?.username || '').trim();
  const serviceName = String(data?.serviceName || '').trim();
  return username.length >= 3 && serviceName.length > 0;
}

async function findAmbulanceByPhone(db, phone) {
  for (const candidate of phoneLookupCandidates(phone)) {
    const snapshot = await db
      .collection('ambulances')
      .where('phone', '==', candidate)
      .limit(1)
      .get();
    if (snapshot.empty) continue;

    const doc = snapshot.docs[0];
    const data = doc.data() || {};
    if (!isRegisteredAmbulanceData(data)) continue;
    return { id: doc.id, data };
  }
  return null;
}

/** Ambulance driver login after mobile OTP — same outcome as username/PIN verify. */
async function completeAmbulanceMobileOtpLogin(db, data, auth, { clientIp = 'unknown' } = {}) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
  }

  const mobileDigits = normalizeMobileDigits(data?.mobile);
  const sessionId = String(data?.sessionId || '').trim();

  if (!mobileDigits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'OTP verification session is required.');
  }

  await enforceVerifyOtpRateLimits(db, { clientIp, role: 'ambulance', digits: mobileDigits });

  await consumeOtpVerificationSessionAtomically(db, sessionId, {
    assertSession: (session) => assertAmbulanceOtpSession(session, mobileDigits),
  });

  const found = await findAmbulanceByPhone(db, mobileDigits);
  if (!found) {
    throw new HttpsError('not-found', 'No ambulance account found for this mobile number.');
  }

  const phoneOnDoc = normalizeMobileDigits(found.data.phone);
  if (!phoneOnDoc || phoneOnDoc !== mobileDigits) {
    throw new HttpsError(
      'permission-denied',
      'Registered mobile does not match ambulance profile.',
    );
  }

  const username = String(found.data.username || '').trim().toLowerCase();
  if (username) {
    try {
      await clearFailedLogins(db, { identifier: `ambulance:${username}` });
    } catch (err) {
      console.error('[completeAmbulanceMobileOtpLogin] Failed to clear login attempts', {
        username,
        error: err,
      });
    }
  }

  const profile = found.data;
  return {
    ok: true,
    driverId: found.id,
    serviceName: profile.serviceName || '',
    driverName: profile.driverName || '',
    username: profile.username || username,
    city: profile.city || '',
    isAvailable: profile.isAvailable !== false,
  };
}

async function resetAmbulanceDriverPin(db, data, auth, { clientIp = 'unknown' } = {}) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Anonymous sign-in required.');
  }

  const mobileDigits = normalizeMobileDigits(data?.mobile);
  const sessionId = String(data?.sessionId || data?.otpSessionId || '').trim();
  const newPin = String(data?.newPin || '').trim();

  if (!mobileDigits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'otpSessionId is required.');
  }
  if (newPin.length < 6) {
    throw new HttpsError('invalid-argument', 'Enter a valid password (minimum 6 characters).');
  }

  await enforcePinResetRateLimits(db, { clientIp, mobileDigits });

  await consumeOtpVerificationSessionAtomically(db, sessionId, {
    assertSession: (session) => assertAmbulanceOtpSession(session, mobileDigits),
  });

  const found = await findAmbulanceByPhone(db, mobileDigits);
  if (!found) {
    throw new HttpsError('not-found', 'Ambulance account not found with this phone number.');
  }

  const phoneOnDoc = normalizeMobileDigits(found.data.phone);
  if (!phoneOnDoc || phoneOnDoc !== mobileDigits) {
    throw new HttpsError(
      'permission-denied',
      'Registered mobile does not match ambulance profile.',
    );
  }

  const pinHash = hashAmbulancePin(newPin.trim());
  const now = FieldValue.serverTimestamp();
  const privateRef = db
    .collection('ambulances')
    .doc(found.id)
    .collection('private')
    .doc('settings');

  const batch = db.batch();
  batch.set(privateRef, {
    pin: pinHash,
    pinUpdatedAt: now,
  }, { merge: true });
  batch.set(db.collection('ambulances').doc(found.id), {
    authUid: auth.uid,
    updatedAt: now,
  }, { merge: true });
  await batch.commit();

  return {
    ok: true,
    driverId: found.id,
    username: String(found.data.username || '').trim(),
  };
}

async function resetUserPasswordWithOtp(db, data, { clientIp = 'unknown' } = {}) {
  const role = String(data?.role || '').trim();
  const identifier = String(data?.identifier || data?.email || data?.mobile || '').trim().toLowerCase();
  const sessionId = String(data?.sessionId || data?.otpSessionId || '').trim();
  const newPassword = String(data?.newPassword || '').trim();

  if (!identifier) {
    throw new HttpsError('invalid-argument', 'Email or mobile number is required.');
  }
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'OTP verification session is required.');
  }
  assertStrongPassword(newPassword);
  if (!role) {
    throw new HttpsError('invalid-argument', 'Account role is required.');
  }

  await enforcePasswordResetRateLimits(db, { clientIp, identifier });

  const isEmail = identifier.includes('@');
  await consumeOtpVerificationSessionAtomically(db, sessionId, {
    messages: {
      missing: 'OTP verification session has expired. Please verify OTP again.',
      alreadyUsed: 'This OTP session has already been used.',
      expired: 'OTP session expired. Please verify OTP again.',
    },
    assertSession: (session) => {
      const sessionRole = String(session.role || '').trim();
      if (sessionRole && sessionRole !== role) {
        throw new HttpsError('permission-denied', 'OTP session does not match this account.');
      }

      if (isEmail) {
        const sessionEmail = String(session.email || session.identifier || '').trim().toLowerCase();
        if (!sessionEmail || sessionEmail !== identifier || session.emailVerified !== true) {
          throw new HttpsError('permission-denied', 'OTP session does not match this email address.');
        }
        return;
      }

      const digits = normalizeMobileDigits(identifier);
      const sessionMobile = normalizeMobileDigits(session.mobileDigits || session.identifier);
      if (!digits || !sessionMobile || sessionMobile !== digits || session.mobileVerified !== true) {
        throw new HttpsError('permission-denied', 'OTP session does not match this mobile number.');
      }
    },
  });

  // Find Auth UID
  let authUid = null;

  if (isEmail) {
    try {
      const userRecord = await getAuth().getUserByEmail(identifier);
      authUid = userRecord.uid;
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        const search = await findUserByEmail(db, identifier);
        if (search.found && search.uid) {
          authUid = search.uid;
        } else {
          throw new HttpsError('not-found', 'No account found with this email address.');
        }
      } else {
        logInternalError('resetUserPasswordWithOtp', e, { identifier, stage: 'getUserByEmail' });
        throw new HttpsError('internal', GENERIC_ACCOUNT_LOOKUP_FAILED);
      }
    }
  } else {
    const digits = normalizeMobileDigits(identifier);
    const search = await findUserByMobileDigits(db, digits);
    if (!search.found || !search.uid) {
      throw new HttpsError('not-found', 'No account found with this mobile number.');
    }
    if (search.role && search.role !== role) {
      throw new HttpsError('permission-denied', 'OTP session does not match this account.');
    }
    authUid = search.uid;
  }

  try {
    await getAuth().updateUser(authUid, { password: newPassword });
  } catch (e) {
    logInternalError('resetUserPasswordWithOtp', e, { authUid, stage: 'updateUser' });
    throw new HttpsError('internal', GENERIC_PASSWORD_UPDATE_FAILED);
  }

  try {
    await getAuth().revokeRefreshTokens(authUid);
  } catch (_) {
    // Non-fatal: password was updated; token revoke is best-effort.
  }

  return { ok: true, success: true, message: 'Password updated successfully! You can now log in.' };
}

async function ensureDoctorFullVerified(db, uid, profileId, overrides = {}) {
  const doctorId = profileId || `demo_doctor_${overrides.mobile || '7666892394'}`;
  const mobile = overrides.mobile || '7666892394';
  const email = overrides.email || `doctor.${mobile}@doctornect.com`;
  const displayName = overrides.displayName || 'Dr. Demo Doctor';

  const batch = db.batch();
  const userRef = db.collection('users').doc(uid);
  batch.set(userRef, {
    role: 'doctor',
    profileId: doctorId,
    displayName,
    email,
    mobile,
    phone: mobile,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    mobileVerified: true,
    kycSubmitted: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const doctorRef = db.collection('doctors').doc(doctorId);
  batch.set(doctorRef, {
    doctorId,
    ownerUid: uid,
    name: displayName,
    fullName: displayName,
    mobile,
    phone: mobile,
    email,
    qualification: 'MBBS, MD (General Medicine)',
    specialization: 'General Medicine (Internal Medicine)',
    councilNumber: `MCI-${mobile}`,
    stateCouncil: 'Maharashtra Medical Council',
    registrationYear: 2016,
    yearsExperience: 10,
    clinicName: 'Dr. Demo Healthcare Clinic',
    clinicType: 'Private Clinic',
    addressLine1: 'Suite 101, Medical Enclave',
    city: 'Mumbai',
    state: 'Maharashtra',
    country: 'India',
    pincode: '400001',
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    kycSubmitted: true,
    profileCompleted: true,
    deactivated: false,
    rating: 4.9,
    reviewCount: 24,
    registrationCertificate: 'https://storage.googleapis.com/demo/medical_council_cert.pdf',
    idProof: 'https://storage.googleapis.com/demo/doctor_id_proof.pdf',
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await batch.commit();
}

async function ensureRoleFullVerified(db, uid, role, profileId, overrides = {}) {
  const r = String(role || 'patient').trim();
  if (r === 'doctor') {
    return ensureDoctorFullVerified(db, uid, profileId, overrides);
  }
  const mobile = overrides.mobile || '';
  const knownProfileIds = {
    '9359503874': 'ms1784184914244',
    '9409858233': 'l1784185011933',
    '9307583929': 'amb-reg-1787919627226',
    '9999988888': 'demo_super_admin_9999988888',
  };
  const knownDisplayNames = {
    '9359503874': 'KD Rx Pharma',
    '9409858233': 'KD Labs',
    '9307583929': 'Demo Ambulance',
    '9999988888': 'Demo Super Admin',
  };
  const roleMeta = {
    medicalStore: { collection: 'medical_stores', idField: 'storeId', defaultName: 'Demo Medical Store' },
    lab: { collection: 'labs', idField: 'labId', defaultName: 'Demo Diagnostic Lab' },
    ambulance: { collection: 'ambulances', idField: 'ambulanceId', defaultName: 'Demo Ambulance Service' },
    superAdmin: { collection: 'super_admins', idField: 'adminId', defaultName: 'Demo Super Admin' },
    super_admin: { collection: 'super_admins', idField: 'adminId', defaultName: 'Demo Super Admin' },
  };
  const meta = roleMeta[r];
  if (!meta) return;

  const effProfileId = profileId || knownProfileIds[mobile] || `${r}_${mobile}`;
  const displayName = overrides.displayName || knownDisplayNames[mobile] || meta.defaultName;

  const batch = db.batch();
  const userRef = db.collection('users').doc(uid);
  const dbRole = (r === 'superAdmin' || r === 'super_admin') ? 'super_admin' : r;
  batch.set(userRef, {
    role: dbRole,
    profileId: effProfileId,
    displayName,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    mobileVerified: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const roleDocRef = db.collection(meta.collection).doc(effProfileId);
  batch.set(roleDocRef, {
    [meta.idField]: effProfileId,
    ownerUid: uid,
    authUid: uid,
    name: displayName,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await batch.commit();
}

async function ensureDemoDoctorAccount(db, mobileDigits) {
  const doctorId = `demo_doctor_${mobileDigits}`;
  const email = `doctor.${mobileDigits}@doctornect.com`;
  const displayName = 'Dr. Demo Doctor';

  let authUser;
  try {
    authUser = await getAuth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') {
      console.warn('Error finding user by email:', e.message);
    }
  }

  if (!authUser) {
    try {
      authUser = await getAuth().createUser({
        email,
        displayName,
        emailVerified: true,
      });
    } catch (err) {
      authUser = await getAuth().getUserByEmail(email).catch(() => null);
      if (!authUser) {
        authUser = { uid: `demo_user_${mobileDigits}` };
      }
    }
  }

  const uid = authUser.uid;
  await ensureDoctorFullVerified(db, uid, doctorId, { mobile: mobileDigits, email, displayName });
  return {
    found: true,
    role: 'doctor',
    uid,
    data: {
      profileId: doctorId,
      role: 'doctor',
      mobile: mobileDigits,
      verified: true,
      verificationStatus: 'verified',
    },
  };
}

async function ensureDemoAccount(db, mobileDigits, role) {
  const r = String(role || 'patient').trim();
  if (r === 'doctor') {
    return ensureDemoDoctorAccount(db, mobileDigits);
  }

  const roleMeta = {
    patient: {
      collection: 'patients',
      idPrefix: 'demo_patient_',
      idField: 'patientId',
      emailPrefix: 'patient',
      displayName: 'Demo Patient',
    },
    medicalStore: {
      collection: 'medical_stores',
      idPrefix: 'demo_store_',
      idField: 'storeId',
      emailPrefix: 'pharmacy',
      displayName: 'Demo Medical Store',
    },
    lab: {
      collection: 'labs',
      idPrefix: 'demo_lab_',
      idField: 'labId',
      emailPrefix: 'lab',
      displayName: 'Demo Diagnostic Lab',
    },
    ambulance: {
      collection: 'ambulances',
      idPrefix: 'demo_ambulance_',
      idField: 'ambulanceId',
      emailPrefix: 'ambulance',
      displayName: 'Demo Ambulance Service',
    },
    superAdmin: {
      collection: 'super_admins',
      idPrefix: 'demo_admin_',
      idField: 'adminId',
      emailPrefix: 'superadmin',
      displayName: 'Demo Super Admin',
    },
    super_admin: {
      collection: 'super_admins',
      idPrefix: 'demo_admin_',
      idField: 'adminId',
      emailPrefix: 'superadmin',
      displayName: 'Demo Super Admin',
    },
  };

  const knownProfileIds = {
    '9359503874': 'ms1784184914244',
    '9409858233': 'l1784185011933',
    '9307583929': 'amb-reg-1787919627226',
    '7666892394': 'demo_doctor_7666892394',
    '9999988888': 'demo_super_admin_9999988888',
  };
  const knownDisplayNames = {
    '9359503874': 'KD Rx Pharma',
    '9409858233': 'KD Labs',
    '9307583929': 'Demo Ambulance',
    '7666892394': 'Dr. Demo Doctor',
    '9999988888': 'Demo Super Admin',
  };

  const meta = roleMeta[r] || roleMeta.patient;
  const profileId = knownProfileIds[mobileDigits] || `${meta.idPrefix}${mobileDigits}`;
  const displayName = knownDisplayNames[mobileDigits] || meta.displayName;
  const email = `${meta.emailPrefix}.${mobileDigits}@doctornect.com`;

  let authUser;
  try {
    authUser = await getAuth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') {
      console.warn('Error finding user by email:', e.message);
    }
  }

  if (!authUser) {
    try {
      authUser = await getAuth().createUser({
        email,
        displayName,
        emailVerified: true,
      });
    } catch (err) {
      authUser = await getAuth().getUserByEmail(email).catch(() => null);
      if (!authUser) {
        authUser = { uid: `demo_user_${r}_${mobileDigits}` };
      }
    }
  }

  const uid = authUser.uid;
  const batch = db.batch();
  const userRef = db.collection('users').doc(uid);
  const dbRole = (r === 'superAdmin' || r === 'super_admin') ? 'super_admin' : r;
  batch.set(userRef, {
    role: dbRole,
    profileId,
    displayName,
    email,
    mobile: mobileDigits,
    phone: mobileDigits,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    mobileVerified: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const roleDocRef = db.collection(meta.collection).doc(profileId);
  batch.set(roleDocRef, {
    [meta.idField]: profileId,
    ownerUid: uid,
    name: displayName,
    fullName: displayName,
    mobile: mobileDigits,
    phone: mobileDigits,
    email,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await batch.commit();

  return {
    found: true,
    role: r,
    uid,
    data: {
      profileId,
      role: r,
      mobile: mobileDigits,
      verified: true,
      verificationStatus: 'verified',
    },
  };
}

/**
 * Exchanges a verified mobile OTP session for a Firebase custom token so the
 * client gets a real Auth session (request.auth) instead of a local-only profile.
 */
async function completeMobileOtpLogin(db, data, { clientIp = 'unknown' } = {}) {
  const role = String(data?.role || '').trim();
  const sessionId = String(data?.sessionId || '').trim();
  const mobileDigits = normalizeMobileDigits(data?.mobile || data?.identifier);

  if (!role) {
    throw new HttpsError('invalid-argument', 'Account role is required.');
  }
  if (!mobileDigits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'OTP verification session is required.');
  }

  await enforceVerifyOtpRateLimits(db, { clientIp, role, digits: mobileDigits });

  await consumeOtpVerificationSessionAtomically(db, sessionId, {
    messages: {
      alreadyUsed: 'This OTP session has already been used.',
      expired: 'OTP session expired. Please verify OTP again.',
    },
    assertSession: (session) => {
      const sessionRole = String(session.role || '').trim();
      const sessionMobile = normalizeMobileDigits(session.mobileDigits || session.identifier);
      if (sessionRole !== role || session.mobileVerified !== true) {
        throw new HttpsError('permission-denied', 'OTP verification incomplete.');
      }
      if (!sessionMobile || sessionMobile !== mobileDigits) {
        throw new HttpsError('permission-denied', 'OTP session does not match this mobile number.');
      }
    },
  });

  const isDemo = await isDemoPhone(mobileDigits, role);
  let search = await findUserByMobileDigits(db, mobileDigits);
  if ((!search.found || !search.uid) && isDemo) {
    try {
      search = await ensureDemoAccount(db, mobileDigits, role);
    } catch (err) {
      console.warn('[completeMobileOtpLogin] Failed to ensure demo account:', err.message);
    }
  }
  if (!search.found || !search.uid) {
    throw new HttpsError('not-found', 'No account found for this mobile number.');
  }
  if (search.role && search.role !== role) {
    console.warn('[completeAmbulanceMobileOtpLogin] Login blocked: account type mismatch', {
      mobileSuffix: mobileDigits.slice(-4),
      requestedRole: role,
      existingRole: search.role,
    });
    throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
  }

  let authUid = search.uid;
  if (role === 'doctor') {
    await ensureDoctorFullVerified(db, authUid, search.data?.profileId, { mobile: mobileDigits });
  } else if (isDemo) {
    await ensureRoleFullVerified(db, authUid, role, search.data?.profileId, { mobile: mobileDigits });
  }

  try {
    await getAuth().getUser(authUid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      if (isDemo) {
        await getAuth().createUser({
          uid: authUid,
          email: `${role}.${mobileDigits}@doctornect.com`,
          displayName: `Demo ${role}`,
          emailVerified: true,
        }).catch(() => {});
      } else {
        throw new HttpsError('not-found', 'No Firebase account found for this mobile number.');
      }
    } else {
      logInternalError('completeMobileOtpLogin', e, { authUid, stage: 'getUser' });
      throw new HttpsError('internal', GENERIC_MOBILE_LOGIN_FAILED);
    }
  }

  const roleClaim = (role === 'superAdmin' || role === 'super_admin') ? 'super_admin' : role;
  const customToken = await getAuth().createCustomToken(authUid, { role: roleClaim, loginMethod: 'mobile_otp' });
  return { ok: true, customToken, uid: authUid };
}

async function assertLoginAllowed(db, data, { clientIp = 'unknown' } = {}) {
  const { idBucket, ipBucket } = resolveLoginBuckets(data, clientIp);
  const nowMs = Date.now();

  const [idSnap, ipSnap] = await Promise.all([
    db.collection('otp_rate_limits').doc(idBucket).get(),
    db.collection('otp_rate_limits').doc(ipBucket).get(),
  ]);
  for (const [snap, max] of [[idSnap, LOGIN_IDENTIFIER_MAX], [ipSnap, LOGIN_IP_MAX]]) {
    const dataDoc = snap.data() || {};
    const windowStartMs = dataDoc.windowStart?.toDate?.()?.getTime() || 0;
    const withinWindow = windowStartMs > 0 && nowMs - windowStartMs < LOGIN_WINDOW_MS;
    const count = withinWindow ? (Number(dataDoc.count) || 0) : 0;
    if (count >= max) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many login attempts. Please try again later.',
      );
    }
  }

  return { ok: true };
}

async function recordFailedLogin(db, data, { clientIp = 'unknown' } = {}) {
  const { idBucket, ipBucket } = resolveLoginBuckets(data, clientIp);
  try {
    await incrementLoginFailureBucket(db, idBucket);
    await incrementLoginFailureBucket(db, ipBucket);
    return { ok: true };
  } catch (err) {
    console.error('[recordFailedLogin] Failed to persist login failure counter', {
      idBucket,
      ipBucket,
      clientIp,
      error: err,
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Failed to record login failure.');
  }
}

async function clearFailedLogins(db, data) {
  const { idBucket } = resolveLoginBuckets(data);
  try {
    await clearLoginFailureBucket(db, idBucket);
    return { ok: true };
  } catch (err) {
    console.error('[clearFailedLogins] Failed to reset login failure counter', {
      idBucket,
      error: err,
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Failed to clear login attempts.');
  }
}

const recordLoginFailure = recordFailedLogin;
const resetLoginAttempts = clearFailedLogins;

/** Read-only: whether a mobile conflicts with login/registration intent (no role disclosure). */
async function lookupMobileRegistration(db, data) {
  const digits = normalizeMobileDigits(data?.mobile);
  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  const intent = String(data?.intent || 'login').trim();
  if (intent !== 'login' && intent !== 'registration') {
    throw new HttpsError('invalid-argument', 'Invalid lookup intent.');
  }
  const requestedRole = String(data?.role || '').trim();
  const effectiveRole = requestedRole || 'doctor';
  const isDemo = await isDemoPhone(digits, effectiveRole);
  let search = await findUserByMobileDigits(db, digits);
  if (!search.found && isDemo) {
    try {
      search = await ensureDemoAccount(db, digits, effectiveRole);
    } catch (_) {}
  }
  const conflict = resolveMobileLookupConflict({
    found: search.found,
    registeredRole: search.role,
    requestedRole,
    intent,
  });
  return { ok: true, conflict };
}

module.exports = {
  sendUserRegistrationOtp,
  consumeOtpChallengeAtomically,
  consumeOtpVerificationSessionAtomically,
  verifyUserRegistrationOtp,
  hashOtp,
  lookupMobileRegistration,
  resolveMobileLookupConflict,
  REGISTRATION_MOBILE_EXISTS_MESSAGE,
  LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE,
  finalizePatientOtpVerification,
  approveUserAccount,
  approvePatientAccount,
  resetAmbulanceDriverPin,
  completeAmbulanceMobileOtpLogin,
  resetUserPasswordWithOtp,
  completeMobileOtpLogin,
  assertLoginAllowed,
  recordFailedLogin,
  clearFailedLogins,
  consumeLoginAttempt,
  recordLoginFailure,
  resetLoginAttempts,
  hashAmbulancePin,
  ambulancePinMatches,
  isPlayReviewMobileInput,
  isDemoMobileInput,
  isDemoPhone,
  isTestMode,
  normalizeRole,
  normalizeMobileDigits,
  verifyMsg91Otp,
};
