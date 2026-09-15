const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { sendMsg91Email } = require('./msg91_email');
const { readMsg91AuthKey } = require('./secure_config');

const OTP_EXPIRY_MS = 10 * 60 * 1000;
const SESSION_EXPIRY_MS = 30 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
/** Dev-only: when OTP_TEST_MODE=true, all numbers accept this OTP (never returned in prod). */
const DEV_TEST_OTP = '123456';
/**
 * Demo / store-review accounts — fixed OTP 000000, no SMS, one phone per role.
 * Set DEMO_PHONE_* in functions env (server-only). Legacy: GOOGLE_PLAY_REVIEW_PHONE = patient.
 */
const DEMO_OTP = '000000';
const DEMO_OTP_EXPIRY_MS = 365 * 24 * 60 * 60 * 1000;
/** @deprecated alias */
const PLAY_REVIEW_OTP = DEMO_OTP;
/** @deprecated alias */
const PLAY_REVIEW_EXPIRY_MS = DEMO_OTP_EXPIRY_MS;

/** Env keys tried in order per role (first non-empty wins). */
const DEMO_PHONE_ENV_BY_ROLE = {
  patient: ['DEMO_PHONE_PATIENT', 'GOOGLE_PLAY_REVIEW_PHONE', 'TEST_PHONE_NUMBER'],
  doctor: ['DEMO_PHONE_DOCTOR'],
  medicalStore: ['DEMO_PHONE_MEDICAL_STORE', 'DEMO_PHONE_PHARMACY'],
  lab: ['DEMO_PHONE_LAB'],
  ambulance: ['DEMO_PHONE_AMBULANCE'],
};

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
function isDemoPhone(digits, role) {
  const expected = demoPhoneDigitsForRole(role);
  return expected != null && expected === digits;
}

/** Callable/request mobile + role — demo bypass only for matching role number. */
function isDemoMobileInput(mobile, role) {
  const digits = normalizeMobileDigits(mobile);
  if (!digits) return false;
  return isDemoPhone(digits, String(role || 'patient').trim());
}

/** @deprecated use isDemoPhone(digits, role) */
function isPlayReviewPhone(digits) {
  return isDemoPhone(digits, 'patient');
}

/** @deprecated use isDemoMobileInput(mobile, role) */
function isPlayReviewMobileInput(mobile) {
  return isDemoMobileInput(mobile, 'patient');
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
  const mode = String(process.env.OTP_TEST_MODE || '').trim().toLowerCase();
  return mode === 'true' || mode === '1';
}

function normalizeMobileDigits(mobile) {
  const digits = String(mobile || '').replace(/\D/g, '');
  let normalized = digits;
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.slice(2);
  } else if (normalized.length === 11 && normalized.startsWith('0')) {
    normalized = normalized.slice(1);
  }
  if (normalized.length !== 10 || !/^[6-9]\d{9}$/.test(normalized)) return '';
  return normalized;
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

function assertSupportedRole(role) {
  const supported = new Set(['patient', 'doctor', 'lab', 'medicalStore', 'ambulance']);
  if (!supported.has(role)) {
    throw new HttpsError(
      'invalid-argument',
      'Unsupported role. Use patient, doctor, lab, medicalStore, or ambulance.',
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
  if (isDemoPhone(digits, role)) return;
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
  if (isDemoPhone(digits, role)) return;
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
  if (allowedEmails.length === 0) {
    throw new HttpsError(
      'permission-denied',
      'Account approval is not configured. Set ACCOUNT_APPROVAL_ADMIN_EMAILS.',
    );
  }
  if (!allowedEmails.includes(callerEmail)) {
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

function postMsg91OtpRequest({ authKey, mobileDigits, code, templateId, senderId }) {
  const built = buildMsg91OtpRequest({ mobileDigits, code, templateId, senderId });

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

const ROLE_LABELS = {
  doctor: 'Doctor',
  patient: 'Patient',
  medicalStore: 'Medical Store',
  lab: 'Diagnostic Lab',
  ambulance: 'Ambulance',
  super_admin: 'Super Admin',
  superAdmin: 'Super Admin',
};

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
    const uid = doc.data()?.ownerUid || doc.id;
    return { found: true, role: roleMatch.role, uid, data: doc.data() };
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
    const uid = doc.data()?.ownerUid || doc.id;
    return { found: true, role: roleMatch.role, uid, data: doc.data() };
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
      const displayRole = ROLE_LABELS[search.role] || search.role || 'another';
      throw new HttpsError(
        'already-exists',
        `This mobile number is already registered under the ${displayRole} role. Please log in or use a different number.`
      );
    }
  }

  if (otpType === 'login' || otpType === 'forgot_password') {
    const search = await findUserByMobileDigits(db, digits);
    if (!search.found) {
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }
    if (search.role && search.role !== role) {
      const displayRole = ROLE_LABELS[search.role] || search.role;
      throw new HttpsError('failed-precondition', `This mobile number is registered under a ${displayRole} account.`);
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
  const isDemoAccount = isDemoPhone(digits, role);
  if (existing.exists && !isDemoAccount) {
    const lastSentAt = existing.data()?.sentAt?.toDate?.();
    if (lastSentAt && Date.now() - lastSentAt.getTime() < RESEND_COOLDOWN_MS) {
      throw new HttpsError(
        'resource-exhausted',
        'Please wait a minute before requesting another OTP.',
      );
    }
  }

  const code = isDemoAccount ? DEMO_OTP : generateOtpCode();
  const expiryMs = isDemoAccount ? DEMO_OTP_EXPIRY_MS : OTP_EXPIRY_MS;
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

  // Outbound MSG91 API call via VPC Connector (static IP).
  try {
    if (isDemoAccount) {
      // No SMS — demo/store-review number for this role only; OTP is DEMO_OTP.
    } else if (!isTestMode()) {
      await sendMsg91SmsOtp(digits, code, otpType);
    } else {
      console.info(`OTP test mode active for mobile ending ${digits.slice(-4)}`);
    }
  } catch (err) {
    await challengeRef.delete().catch(() => {});
    throw err;
  }

  return {
    ok: true,
    expiresInSeconds: Math.floor(expiryMs / 1000),
    ...(isTestMode() && !isDemoAccount ? { debugOtp: DEV_TEST_OTP } : {}),
  };
}

/**
 * Atomically validates an OTP challenge, increments failed attempts, or consumes it.
 * Prevents concurrent verify calls from bypassing lockout or reusing a challenge.
 */
async function consumeOtpChallengeAtomically(db, { challengeKey, otp, isDemoAccount }) {
  const challengeRef = db.collection('otp_challenges').doc(challengeKey);

  const outcome = await db.runTransaction(async (tx) => {
    const challengeSnap = await tx.get(challengeRef);
    if (!challengeSnap.exists) {
      return { status: 'missing' };
    }

    const challenge = challengeSnap.data() || {};
    const expiresAt = challenge.expiresAt?.toDate?.();
    if (!expiresAt || Date.now() > expiresAt.getTime()) {
      tx.delete(challengeRef);
      return { status: 'expired' };
    }

    const attempts = Number(challenge.attempts) || 0;
    if (attempts >= 5) {
      tx.delete(challengeRef);
      return { status: 'locked' };
    }

    const otpValid = otpHashesEqual(hashOtp(otp), challenge.otpHash)
      || (!isDemoAccount && isTestMode() && otp === DEV_TEST_OTP);
    if (!otpValid) {
      tx.set(challengeRef, { attempts: attempts + 1 }, { merge: true });
      return { status: 'invalid', attempts: attempts + 1 };
    }

    tx.delete(challengeRef);
    return { status: 'consumed' };
  });

  switch (outcome.status) {
    case 'missing':
      throw new HttpsError('failed-precondition', 'Send OTP first.');
    case 'expired':
      throw new HttpsError('deadline-exceeded', 'OTP expired. Send a new one.');
    case 'locked':
      throw new HttpsError('resource-exhausted', 'Too many invalid attempts. Send a new OTP.');
    case 'invalid':
      throw new HttpsError('permission-denied', 'Invalid OTP.');
    case 'consumed':
      return { consumed: true };
    default:
      throw new HttpsError('internal', 'OTP verification failed.');
  }
}

async function verifyUserRegistrationOtp(db, data, auth, { clientIp = 'unknown' } = {}) {
  const role = String(data?.role || 'patient').trim();
  assertSupportedRole(role);

  const emailInput = String(data?.email || data?.identifier || '').trim().toLowerCase();
  const isEmail = emailInput.includes('@');
  if (isEmail) {
    throw new HttpsError('invalid-argument', 'Email verification is disabled. Please verify via mobile phone SMS OTP.');
  }

  const digits = normalizeMobileDigits(data?.mobile || data?.identifier);
  const otp = String(data?.otp || '').trim();

  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError('invalid-argument', 'Enter the 6-digit OTP.');
  }

  await enforceVerifyOtpRateLimits(db, { clientIp, role, digits });

  const challengeKey = mobileHash(role, digits);
  const isDemoAccount = isDemoPhone(digits, role);

  await consumeOtpChallengeAtomically(db, {
    challengeKey,
    otp,
    isDemoAccount,
  });

  const verifiedAt = FieldValue.serverTimestamp();
  const sessionExpiresAt = Timestamp.fromDate(new Date(Date.now() + SESSION_EXPIRY_MS));
  const sessionId = crypto.randomBytes(16).toString('hex');
  const otpType = String(data?.otpType || 'registration').trim();

  // Signed-in account — refresh mobileVerified only when users/{uid} already exists.
  if (auth?.uid && !isEmail) {
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
    const search = await findUserByMobileDigits(db, digits);
    if (!search.found || !search.uid) {
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }
    if (search.role && search.role !== role) {
      const displayRole = ROLE_LABELS[search.role] || search.role;
      throw new HttpsError(
        'failed-precondition',
        `This mobile number is registered under a ${displayRole} account.`,
      );
    }
    const customToken = await getAuth().createCustomToken(search.uid, { role });
    return {
      ok: true,
      mobileVerified: true,
      sessionId,
      customToken,
      uid: search.uid,
    };
  }

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

  const sessionRef = db.collection('otp_verification_sessions').doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('failed-precondition', 'OTP verification session expired. Verify again.');
  }

  const session = sessionSnap.data() || {};
  if (session.consumed === true) {
    throw new HttpsError('failed-precondition', 'OTP verification session already used.');
  }

  const expiresAt = session.expiresAt?.toDate?.();
  if (!expiresAt || Date.now() > expiresAt.getTime()) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError('deadline-exceeded', 'OTP verification session expired. Verify again.');
  }

  if (session.role !== userRole || session.mobileVerified !== true) {
    throw new HttpsError('failed-precondition', 'OTP verification incomplete.');
  }

  const sessionMobile = normalizeMobileDigits(session.mobileDigits);
  const profileMobile = normalizeMobileDigits(userProfile.mobile);
  if (!sessionMobile || !profileMobile || sessionMobile !== profileMobile) {
    throw new HttpsError(
      'permission-denied',
      'Registered mobile does not match OTP verification.',
    );
  }

  await markUserMobileVerified(db, {
    uid: auth.uid,
    mobileDigits: sessionMobile,
    role: userRole,
  });

  await sessionRef.set({ consumed: true, consumedAt: FieldValue.serverTimestamp() }, { merge: true });

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

async function validateAmbulancePinResetSession(db, { sessionId, mobileDigits }) {
  const sessionRef = db.collection('otp_verification_sessions').doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('failed-precondition', 'OTP verification session expired. Verify again.');
  }

  const session = sessionSnap.data() || {};
  if (session.consumed === true) {
    throw new HttpsError('failed-precondition', 'OTP verification session already used.');
  }

  const expiresAt = session.expiresAt?.toDate?.();
  if (!expiresAt || Date.now() > expiresAt.getTime()) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError('deadline-exceeded', 'OTP verification session expired. Verify again.');
  }

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

  return { sessionRef, sessionMobile };
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

  const { sessionRef } = await validateAmbulancePinResetSession(db, {
    sessionId,
    mobileDigits,
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

  await sessionRef.set({ consumed: true, consumedAt: FieldValue.serverTimestamp() }, { merge: true });

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

  const { sessionRef } = await validateAmbulancePinResetSession(db, {
    sessionId,
    mobileDigits,
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
  batch.set(sessionRef, { consumed: true, consumedAt: now }, { merge: true });
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

  // 1. Verify OTP Session and bind it to the target account
  const sessionRef = db.collection('otp_verification_sessions').doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('failed-precondition', 'OTP verification session has expired. Please verify OTP again.');
  }
  const session = sessionSnap.data() || {};
  if (session.consumed === true) {
    throw new HttpsError('failed-precondition', 'This OTP session has already been used.');
  }
  const expiresAt = session.expiresAt?.toDate?.();
  if (!expiresAt || Date.now() > expiresAt.getTime()) {
    throw new HttpsError('deadline-exceeded', 'OTP session expired. Please verify OTP again.');
  }

  const sessionRole = String(session.role || '').trim();
  if (sessionRole && sessionRole !== role) {
    throw new HttpsError('permission-denied', 'OTP session does not match this account.');
  }

  const isEmail = identifier.includes('@');
  if (isEmail) {
    const sessionEmail = String(session.email || session.identifier || '').trim().toLowerCase();
    if (!sessionEmail || sessionEmail !== identifier || session.emailVerified !== true) {
      throw new HttpsError('permission-denied', 'OTP session does not match this email address.');
    }
  } else {
    const digits = normalizeMobileDigits(identifier);
    const sessionMobile = normalizeMobileDigits(session.mobileDigits || session.identifier);
    if (!digits || !sessionMobile || sessionMobile !== digits || session.mobileVerified !== true) {
      throw new HttpsError('permission-denied', 'OTP session does not match this mobile number.');
    }
  }

  // 2. Find Auth UID
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
        throw new HttpsError('internal', `Account lookup failed: ${e.message}`);
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

  // 3. Update password in Firebase Auth
  try {
    await getAuth().updateUser(authUid, { password: newPassword });
  } catch (e) {
    throw new HttpsError('internal', `Failed to update password: ${e.message}`);
  }

  // 4. Mark session consumed + revoke refresh tokens so old sessions die
  await sessionRef.set({ consumed: true, consumedAt: FieldValue.serverTimestamp() }, { merge: true });
  try {
    await getAuth().revokeRefreshTokens(authUid);
  } catch (_) {
    // Non-fatal: password was updated; token revoke is best-effort.
  }

  return { ok: true, success: true, message: 'Password updated successfully! You can now log in.' };
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

  const sessionRef = db.collection('otp_verification_sessions').doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('failed-precondition', 'OTP verification session expired. Verify again.');
  }
  const session = sessionSnap.data() || {};
  if (session.consumed === true) {
    throw new HttpsError('failed-precondition', 'This OTP session has already been used.');
  }
  const expiresAt = session.expiresAt?.toDate?.();
  if (!expiresAt || Date.now() > expiresAt.getTime()) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError('deadline-exceeded', 'OTP session expired. Please verify OTP again.');
  }

  const sessionRole = String(session.role || '').trim();
  const sessionMobile = normalizeMobileDigits(session.mobileDigits || session.identifier);
  if (sessionRole !== role || session.mobileVerified !== true) {
    throw new HttpsError('permission-denied', 'OTP verification incomplete.');
  }
  if (!sessionMobile || sessionMobile !== mobileDigits) {
    throw new HttpsError('permission-denied', 'OTP session does not match this mobile number.');
  }

  const search = await findUserByMobileDigits(db, mobileDigits);
  if (!search.found || !search.uid) {
    throw new HttpsError('not-found', 'No account found for this mobile number.');
  }
  if (search.role && search.role !== role) {
    throw new HttpsError('failed-precondition', 'This mobile number is registered under a different account.');
  }

  let authUid = search.uid;
  try {
    await getAuth().getUser(authUid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'No Firebase account found for this mobile number.');
    }
    throw new HttpsError('internal', `Account lookup failed: ${e.message}`);
  }

  await sessionRef.set({ consumed: true, consumedAt: FieldValue.serverTimestamp() }, { merge: true });

  const customToken = await getAuth().createCustomToken(authUid, { role, loginMethod: 'mobile_otp' });
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

/** Read-only: which module (role) owns this mobile, if any. */
async function lookupMobileRegistration(db, data) {
  const digits = normalizeMobileDigits(data?.mobile);
  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  const search = await findUserByMobileDigits(db, digits);
  if (!search.found) {
    return { ok: true, found: false, role: null, roleLabel: null };
  }
  const roleLabel = ROLE_LABELS[search.role] || search.role || 'Unknown';
  return {
    ok: true,
    found: true,
    role: search.role || null,
    roleLabel,
  };
}

module.exports = {
  sendUserRegistrationOtp,
  consumeOtpChallengeAtomically,
  verifyUserRegistrationOtp,
  hashOtp,
  lookupMobileRegistration,
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
};
