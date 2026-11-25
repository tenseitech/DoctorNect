const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const { getAuth } = require('firebase-admin/auth');
const { sendMsg91Email } = require('./msg91_email');
const { readMsg91AuthKey } = require('./secure_config');
const {
  isProductionFirebaseProject,
  isFunctionsEmulator,
  isOtpTestModeConfigured,
} = require('./production_otp_guard');
const {
  GENERIC_ACCOUNT_LOOKUP_FAILED,
  GENERIC_PASSWORD_UPDATE_FAILED,
  GENERIC_MOBILE_LOGIN_FAILED,
  logInternalError,
} = require('./public_error_messages');
const { emit, SEVERITY, hashIdentifier } = require('./security_logger');

// 5-minute OTP lifetime (Redis TTL matches); single-use, deleted on successful verify.
const OTP_EXPIRY_MS = 5 * 60 * 1000;
const SESSION_EXPIRY_MS = 30 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
// Demo bypass removed: Play Store reviewer login in reviewer_login.js is the only fixed-OTP path.

const SEND_IP_WINDOW_MS = 60 * 60 * 1000;
const SEND_IP_MAX = 10;
const SEND_MOBILE_WINDOW_MS = 60 * 60 * 1000;
const SEND_MOBILE_MAX = 5;
const VERIFY_IP_WINDOW_MS = 60 * 60 * 1000;
const VERIFY_IP_MAX = 15;
// Daily caps (SMS-pumping / cost-abuse guard), independent of role.
const SEND_DAILY_WINDOW_MS = 24 * 60 * 60 * 1000;
const SEND_MOBILE_DAILY_MAX = 10;
const SEND_IP_DAILY_MAX = 50;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_IP_MAX = 20;
const LOGIN_IDENTIFIER_MAX = 5;
const PASSWORD_RESET_WINDOW_MS = 60 * 60 * 1000;
const PASSWORD_RESET_IP_MAX = 10;
const PASSWORD_RESET_IDENTIFIER_MAX = 5;
const PBKDF2_ITERATIONS = 120000;
const PBKDF2_KEYLEN = 32;
const PBKDF2_DIGEST = 'sha256';

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
  const norm = normalizeRole(role);
  return crypto.createHash('sha256').update(`${norm}:${digits}`).digest('hex');
}

const { redisKey: envPrefixedRedisKey } = require('./src/config/redis_keys');

function otpAttemptsRedisKey(digits) {
  return envPrefixedRedisKey(`otp:attempts:${digits}`);
}

const OTP_VERIFY_ATTEMPT_MAX = 5;
const OTP_ATTEMPTS_TTL_MS = 15 * 60 * 1000;

/**
 * Atomically reserves a verify attempt (max 5 per mobile). Returns null when locked out.
 */
async function reserveOtpVerifyAttemptSlot(redis, attemptsKey) {
  const lua = `
    local n = redis.call('INCR', KEYS[1])
    if n == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
    if n > tonumber(ARGV[2]) then return -1 end
    return n
  `;
  if (typeof redis.eval === 'function') {
    const n = await withOtpRedisTimeout(
      redis.eval(lua, 1, attemptsKey, String(OTP_ATTEMPTS_TTL_MS), String(OTP_VERIFY_ATTEMPT_MAX)),
    );
    if (Number(n) === -1) return null;
    return Number(n);
  }
  let newAttempts = 1;
  if (typeof redis.incr === 'function') {
    newAttempts = await withOtpRedisTimeout(redis.incr(attemptsKey));
    if (newAttempts === 1 && typeof redis.pexpire === 'function') {
      await withOtpRedisTimeout(redis.pexpire(attemptsKey, OTP_ATTEMPTS_TTL_MS)).catch(() => {});
    }
  }
  if (newAttempts > OTP_VERIFY_ATTEMPT_MAX) return null;
  return newAttempts;
}

function otpSessionRedisKey(sessionIdOrHash) {
  return envPrefixedRedisKey(`otp:session:${sessionIdOrHash}`);
}

function otpRedisKey(role, digits) {
  const secret = readMsg91AuthKey({ required: false });
  if (!secret) return null;
  const normRole = role ? normalizeRole(role) : '';
  const hashedDigits = crypto
    .createHmac('sha256', secret)
    .update(String(digits || '').trim())
    .digest('hex');
  const base = normRole ? `otp:challenge:${normRole}:${hashedDigits}` : `otp:challenge:${hashedDigits}`;
  return envPrefixedRedisKey(base);
}

const OTP_REDIS_TIMEOUT_MS = 1500;

/** OTP Redis mirror is opt-in; when off the OTP flow must never load or call Redis. */
function isOtpRedisMirrorEnabled() {
  return String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() === 'on';
}

function getOtpRedisClient() {
  if (!isOtpRedisMirrorEnabled()) return null;
  return require('./redis').redis;
}

function withOtpRedisTimeout(promise, ms = OTP_REDIS_TIMEOUT_MS) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Redis OTP mirror operation timed out')), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

async function deleteOtpRedisKeys(redis, role, digits) {
  if (!redis || !digits) return;
  const keyNull = otpRedisKey(null, digits);
  const keyRole = role ? otpRedisKey(role, digits) : null;
  await Promise.all([
    keyNull ? withOtpRedisTimeout(redis.del(keyNull)).catch(() => {}) : Promise.resolve(),
    keyRole ? withOtpRedisTimeout(redis.del(keyRole)).catch(() => {}) : Promise.resolve(),
  ]).catch(() => {});
}

// Read at process start from the environment. Default false.
// Set ALLOW_LEGACY_UNSALTED_OTP_HASH=true only as an instant rollback.

/**
 * Play Store / App Store reviewer OTP bypass (production-gated).
 * When REVIEWER_OTP_ENABLED=true:
 *   REVIEW_{ROLE}_PHONES — comma-separated fictitious 10-digit numbers (max 2 per role)
 *   REVIEW_FIXED_OTP — fixed 6-digit OTP (never logged; audit uses hashIdentifier only)
 *   REVIEW_ACCESS_UNTIL — ISO 8601 expiry; bypass disabled after this instant
 * Rate limits: Redis via abuse_rate_limit.assertBucketRedis (requires REDIS_HOST in production).
 */
const REVIEW_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const REVIEW_RATE_LIMIT_MAX = 5;
let _testingReviewerRedis = null;

const {
  getReviewerConfig,
  isReviewerPhone,
  demoOtpPolicy,
  canonicalMobileDigits,
  demoAccountByMobile,
  isDemoMobile,
} = require('./reviewer_otp_config');

const MSG91_UNAVAILABLE_DETAILS = { reason: 'msg91' };
const DEMO_SIGNIN_UNAVAILABLE_MESSAGE = 'Demo sign-in is not available right now.';
const DEMO_REGISTRATION_BLOCKED_MESSAGE = 'This number is reserved and cannot be used to register.';
const DEMO_LOCKOUT_WINDOW_MS = 30 * 60 * 1000;
const DEMO_LOCKOUT_MAX_FAILURES = 5;

function msg91UnavailableError(message, meta = {}) {
  const err = new HttpsError(
    'unavailable',
    message || 'SMS service is temporarily unavailable. Please try again later.',
    MSG91_UNAVAILABLE_DETAILS,
  );
  if (meta.httpStatus != null) err.httpStatus = meta.httpStatus;
  if (meta.responseBody != null) err.responseBody = meta.responseBody;
  return err;
}

/**
 * The staging-only DEMO_PHONE_NUMBERS / DEMO_FIXED_OTP bypass was removed: the fixed demo OTP
 * applies only to the five numbers in lib/demo_accounts.js (see reviewer_otp_config.js).
 * Kept as a stub so older imports fail safe.
 */
function isStagingDemoPhone(_digits) {
  return false;
}

/** Demo numbers never receive an SMS, whether or not the demo OTP policy is active. */
function shouldSkipMsg91ForPhone(digits, _role) {
  return isDemoMobile(digits);
}

/** OTP for an outbound challenge: the fixed demo OTP for demo numbers, random otherwise. */
function resolveOutboundOtpCode(digits, _role) {
  if (isDemoMobile(digits)) {
    const policy = demoOtpPolicy();
    if (!policy.active) {
      throw new HttpsError('failed-precondition', DEMO_SIGNIN_UNAVAILABLE_MESSAGE);
    }
    return policy.fixedOtp;
  }
  return generateOtpCode();
}

function setReviewerRedisClientForTesting(client) {
  _testingReviewerRedis = client;
}

function getReviewerRedisClient() {
  if (_testingReviewerRedis !== null) return _testingReviewerRedis;
  try {
    return require('./redis').redis || null;
  } catch (_) {
    return null;
  }
}

/** Redis-only reviewer send limiter (fail closed when Redis is unavailable). */
async function checkReviewerRateLimit(digits, { redisClient = null } = {}) {
  const d = normalizeMobileDigits(digits);
  const client = redisClient || getReviewerRedisClient();
  if (!client) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
  const hash = crypto.createHash('sha256').update(`reviewer:${d}`).digest('hex');
  try {
    const { assertBucketRedis } = require('./abuse_rate_limit');
    await assertBucketRedis(client, {
      key: envPrefixedRedisKey(`ratelimit:reviewer:${hash}`),
      windowMs: REVIEW_RATE_LIMIT_WINDOW_MS,
      maxAttempts: REVIEW_RATE_LIMIT_MAX,
      message: 'Reviewer verification rate limit exceeded. Please try again later.',
    });
    return true;
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'resource-exhausted') {
      return false;
    }
    throw err instanceof HttpsError
      ? err
      : new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
}

function resetReviewerRateLimitForTesting() {
  if (_testingReviewerRedis) {
    if (typeof _testingReviewerRedis.flushall === "function") {
      _testingReviewerRedis.flushall();
    } else if (_testingReviewerRedis.store && typeof _testingReviewerRedis.store.clear === "function") {
      _testingReviewerRedis.store.clear();
    }
  }
}

function allowLegacyUnsaltedOtpHash() {
  return String(process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH || '')
    .trim()
    .toLowerCase() === 'true';
}

function legacyHashOtp(code) {
  return crypto.createHash('sha256').update(String(code || '')).digest('hex');
}

function resolveOtpHmacSecret() {
  const dedicated = String(process.env.OTP_HMAC_SECRET || '').trim();
  if (dedicated) return dedicated;
  return readMsg91AuthKey({ required: false }) || null;
}

function hashOtp(code, roleOrOpts, maybeDigits, maybeOpts) {
  let role = '';
  let digits = '';
  let purpose = '';
  if (roleOrOpts && typeof roleOrOpts === 'object') {
    role = roleOrOpts.role || '';
    digits = roleOrOpts.digits || roleOrOpts.mobileDigits || '';
    purpose = roleOrOpts.purpose || '';
  } else {
    role = roleOrOpts || '';
    digits = typeof maybeDigits === 'string' ? maybeDigits : (maybeDigits?.digits || '');
    if (maybeDigits && typeof maybeDigits === 'object') {
      purpose = maybeDigits.purpose || '';
    } else if (maybeOpts && typeof maybeOpts === 'object') {
      purpose = maybeOpts.purpose || '';
    }
  }
  const secret = resolveOtpHmacSecret();
  const normRole = role ? normalizeRole(role) : '';
  const normDigits = digits ? normalizeMobileDigits(digits) : '';
  const codeStr = String(code || '').trim();
  if (!secret) {
    if (isProductionFirebaseProject() && !isFunctionsEmulator()) {
      console.error(JSON.stringify({
        securityEvent: true,
        severity: 'ERROR',
        category: 'security',
        action: 'otp_hash_secret_missing',
        detail: 'Cannot hash OTP without HMAC secret in production project',
      }));
      throw new HttpsError('internal', 'Could not send OTP. Please try again.');
    }
    if (purpose === 'create' && !allowLegacyUnsaltedOtpHash()) {
      throw new HttpsError(
        'failed-precondition',
        'OTP HMAC secret required (MSG91 auth key or OTP_HMAC_SECRET).',
      );
    }
    return legacyHashOtp(code);
  }
  const payload = `${normRole}:${normDigits}:${codeStr}`;
  return crypto.createHmac('sha256', secret).update(payload).digest('hex');
}

function verifyChallengeOtpHash(otp, challengeOrHash, callerRole, callerDigits) {
  let expectedHash = '';
  let challengeRole = '';
  let challengeDigits = '';
  if (typeof challengeOrHash === 'object' && challengeOrHash !== null) {
    expectedHash = challengeOrHash.otpHash || '';
    challengeRole = challengeOrHash.role || '';
    challengeDigits = challengeOrHash.mobileDigits || challengeOrHash.digits || '';
  } else {
    expectedHash = String(challengeOrHash || '');
  }
  if (!expectedHash) return false;

  const role = callerRole || challengeRole || '';
  const digits = callerDigits || challengeDigits || '';

  // If both challenge and caller specify role, and they differ, cannot match
  if (challengeRole && callerRole && normalizeRole(challengeRole) !== normalizeRole(callerRole)) {
    return false;
  }
  // If both challenge and caller specify digits, and they differ, cannot match
  if (challengeDigits && callerDigits && normalizeMobileDigits(challengeDigits) !== normalizeMobileDigits(callerDigits)) {
    return false;
  }

  const currentHash = hashOtp(otp, role, digits);
  if (otpHashesEqual(currentHash, expectedHash)) {
    return true;
  }
  if (allowLegacyUnsaltedOtpHash() && otpHashesEqual(legacyHashOtp(otp), expectedHash)) {
    return true;
  }
  return false;
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
  if (lower === 'medical' || lower === 'medicalstore' || lower === 'medical_store' || lower === 'pharmacy') return 'medicalStore';
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

/** Shared Redis client for OTP / login limits (null when unavailable). */
function getRateLimitRedis() {
  try {
    return getOtpRedisClient() || require('./redis').redis || null;
  } catch (_) {
    return null;
  }
}

/** Redis-only fixed-window limiter. Fails CLOSED when Redis is unavailable. */
async function assertOtpRateLimit(_db, { bucket, windowMs, maxAttempts }) {
  const redis = getRateLimitRedis();
  if (!redis) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
  try {
    const { assertBucketRedis } = require('./abuse_rate_limit');
    await assertBucketRedis(redis, {
      key: envPrefixedRedisKey(`ratelimit:otp:${bucket}`),
      windowMs,
      maxAttempts,
      message: 'Too many OTP requests. Please try again later.',
    });
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'resource-exhausted') {
      throw err;
    }
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
}

/**
 * Per-mobile buckets are keyed by the number only (not role); previously each of the 5 roles
 * had its own bucket, so one number could receive 5x the intended SMS volume.
 */
function mobileRateKey(digits) {
  return hashRateLimitKey(`mobile:${digits}`);
}

async function enforceSendOtpRateLimits(db, { clientIp, role, digits }) {
  await assertOtpRateLimit(db, {
    bucket: `send_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: SEND_IP_WINDOW_MS,
    maxAttempts: SEND_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `send_mobile_${mobileRateKey(digits)}`,
    windowMs: SEND_MOBILE_WINDOW_MS,
    maxAttempts: SEND_MOBILE_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `send_ip_daily_${hashRateLimitKey(clientIp)}`,
    windowMs: SEND_DAILY_WINDOW_MS,
    maxAttempts: SEND_IP_DAILY_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `send_mobile_daily_${mobileRateKey(digits)}`,
    windowMs: SEND_DAILY_WINDOW_MS,
    maxAttempts: SEND_MOBILE_DAILY_MAX,
  });
}

async function enforceVerifyOtpRateLimits(db, { clientIp, role, digits }) {
  await assertOtpRateLimit(db, {
    bucket: `verify_ip_${hashRateLimitKey(clientIp)}`,
    windowMs: VERIFY_IP_WINDOW_MS,
    maxAttempts: VERIFY_IP_MAX,
  });
  await assertOtpRateLimit(db, {
    bucket: `verify_mobile_${mobileRateKey(digits)}`,
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

function loginFailureRedisKey(bucket) {
  return envPrefixedRedisKey(`ratelimit:login_fail:${bucket}`);
}

/** Increments a login-failure counter (TTL = login window). Fails closed. */
async function incrementLoginFailureBucket(_db, bucket) {
  const redis = getRateLimitRedis();
  if (!redis) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
  const key = loginFailureRedisKey(bucket);
  try {
    const n = await withOtpRedisTimeout(redis.incr(key));
    if (Number(n) === 1 && typeof redis.pexpire === 'function') {
      await withOtpRedisTimeout(redis.pexpire(key, LOGIN_WINDOW_MS));
    }
    return Number(n) || 0;
  } catch (_) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
}

async function readLoginFailureCount(bucket) {
  const redis = getRateLimitRedis();
  if (!redis) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
  try {
    return Number(await withOtpRedisTimeout(redis.get(loginFailureRedisKey(bucket)))) || 0;
  } catch (_) {
    throw new HttpsError('unavailable', 'Rate limit service temporarily unavailable.');
  }
}

async function clearLoginFailureBucket(_db, bucket) {
  const redis = getRateLimitRedis();
  if (!redis) return;
  await withOtpRedisTimeout(redis.del(loginFailureRedisKey(bucket))).catch(() => {});
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

const SAFE_FIREBASE_UID_RE = /^[A-Za-z0-9_\-:.]{1,128}$/;

/** Postgres users row for a Firebase UID (routed to the caller's data plane). */
async function readUserProfile(_db, uid) {
  const id = String(uid || '').trim();
  if (!SAFE_FIREBASE_UID_RE.test(id)) return null;
  const { getDatabaseClient } = require('./src/db/client');
  const sb = getDatabaseClient({ firebaseUid: id });
  const { data, error } = await sb
    .from('users')
    .select('*')
    .or(`id.eq.${id},firebase_uid.eq.${id}`)
    .maybeSingle();
  if (error) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  return data || null;
}

async function markUserMobileVerified(_db, { uid, mobileDigits, role }) {
  const id = String(uid || '').trim();
  if (!SAFE_FIREBASE_UID_RE.test(id)) {
    throw new HttpsError('invalid-argument', 'Invalid account.');
  }
  const { getDatabaseClient } = require('./src/db/client');
  const sb = getDatabaseClient({ firebaseUid: id });
  const { error } = await sb
    .from('users')
    .update({ mobile_verified: true, updated_at: new Date().toISOString() })
    .or(`id.eq.${id},firebase_uid.eq.${id}`);
  if (error) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  const redis = getRateLimitRedis();
  if (redis && mobileDigits) {
    await withOtpRedisTimeout(redis.del(otpSessionRedisKey(mobileHash(role, mobileDigits)))).catch(() => {});
  }
  return { mobileVerified: true, uid: id };
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

  const role = normalizeRole(data?.role || 'patient');
  const roleConfig = {
    patient: { collection: 'patients', idField: 'patientId' },
    doctor: { collection: 'doctors', idField: 'doctorId' },
    lab: { collection: 'labs', idField: 'labId' },
    medicalStore: { collection: 'medical_stores', idField: 'storeId' },
    ambulance: { collection: 'ambulances', idField: 'ambulanceId' },
  }[role];

  if (!roleConfig) {
    throw new HttpsError('invalid-argument', 'Unsupported role. Use patient, doctor, lab, medicalStore, or ambulance.');
  }

  const profileId = String(
    data?.profileId
    || data?.[roleConfig.idField]
    || data?.patientId
    || data?.doctorId
    || data?.labId
    || data?.storeId
    || data?.ambulanceId
    || '',
  ).trim();
  if (!profileId) {
    throw new HttpsError('invalid-argument', `${roleConfig.idField} is required.`);
  }

  if (!/^[A-Za-z0-9_\-:.]{1,128}$/.test(profileId)) {
    throw new HttpsError('invalid-argument', 'Invalid profile id.');
  }

  {
    const { getSupabaseAdminClient } = require('./caller_identity');
    const sb = getSupabaseAdminClient();
    if (!sb) throw new HttpsError('internal', 'Supabase admin client not configured.');

    const tableConfig = {
      patient: { table: 'patients', idCol: 'patient_id', ownerCol: 'owner_uid' },
      doctor: { table: 'doctors', idCol: 'doctor_id', ownerCol: 'owner_uid' },
      lab: { table: 'labs', idCol: 'lab_id', ownerCol: 'owner_uid' },
      medicalStore: { table: 'medical_stores', idCol: 'store_id', ownerCol: 'owner_uid' },
      ambulance: { table: 'ambulances', idCol: 'ambulance_id', ownerCol: 'auth_uid' },
    }[role];

    const { data: roleRow, error: roleErr } = await sb
      .from(tableConfig.table)
      .select('*')
      .eq(tableConfig.idCol, profileId)
      .maybeSingle();

    if (roleErr || !roleRow) {
      throw new HttpsError('not-found', `${role} profile not found.`);
    }

    let ownerUid = String(roleRow[tableConfig.ownerCol] || '').trim();
    if (!ownerUid) {
      const { data: userRow } = await sb
        .from('users')
        .select('id, firebase_uid')
        .or(`id.eq.${profileId},firebase_uid.eq.${profileId}`)
        .maybeSingle();
      ownerUid = String(userRow?.firebase_uid || userRow?.id || '').trim();
    }
    if (!ownerUid) {
      throw new HttpsError('failed-precondition', `${role} ownerUid is missing.`);
    }

    const nowIso = new Date().toISOString();
    await sb
      .from(tableConfig.table)
      .update({
        verified: true,
        status: 'active',
        updated_at: nowIso,
      })
      .eq(tableConfig.idCol, profileId);

    await sb
      .from('users')
      .update({
        verified: true,
        updated_at: nowIso,
      })
      .or(`id.eq.${ownerUid},firebase_uid.eq.${ownerUid}`);

    const claims = supabaseCompatibleCustomClaims(role, { verified: true });
    try {
      await getAuth().setCustomUserClaims(ownerUid, claims);
    } catch (claimErr) {
      console.warn('[approveUserAccount] Failed to set custom claims:', claimErr?.message || claimErr);
    }

    return { ok: true, role, profileId, ownerUid, verified: true };
  }

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

function sanitizeResponseBody(rawBody) {
  if (rawBody === null || rawBody === undefined) return null;
  let str = typeof rawBody === 'string' ? rawBody : JSON.stringify(rawBody);
  str = str.replace(/(?:\+?91|0)?([6-9]\d{5})(\d{4})\b/g, '******$2');
  str = str.replace(/("otp"\s*:\s*")([^"]+)(")/gi, '$1[REDACTED]$3');
  str = str.replace(/("authkey"\s*:\s*")([^"]+)(")/gi, '$1[REDACTED]$3');
  try {
    return JSON.parse(str);
  } catch (_) {
    return str;
  }
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

/** Keys that must never reach logs (provider config identifiers, secrets, raw OTP). */
const MSG91_LOG_REDACT_KEYS = new Set([
  'templateId', 'template_id', 'dltId', 'senderId', 'sender', 'otp', 'authkey', 'authKey', 'code',
]);

function redactMsg91LogFields(value, depth = 0) {
  if (value === null || value === undefined || depth > 4) return value;
  if (Array.isArray(value)) return value.map((v) => redactMsg91LogFields(v, depth + 1));
  if (typeof value !== 'object') return value;
  const out = {};
  for (const [k, v] of Object.entries(value)) {
    if (MSG91_LOG_REDACT_KEYS.has(k)) {
      out[k] = v ? '[REDACTED]' : v;
    } else if (k === 'mobile' && typeof v === 'string') {
      out[k] = maskMsg91Mobile(v.replace(/^\+?91/, ''));
    } else if (k === 'responseBody') {
      out[k] = sanitizeResponseBody(v);
    } else {
      out[k] = redactMsg91LogFields(v, depth + 1);
    }
  }
  return out;
}

function logMsg91Otp(event, fields) {
  const payload = {
    severity: fields.severity || 'INFO',
    component: 'msg91_otp',
    event,
    ...redactMsg91LogFields(fields),
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
  return String(process.env.MSG91_SENDER_ID || 'DRNECT')
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
      console.warn(`[verifyMsg91Otp] MSG91 rejected OTP for mobile ending ${normalizedMobile.slice(-4)}, httpStatus=${statusCode}, response=${JSON.stringify(sanitizeResponseBody(body))}`);
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
    throw msg91UnavailableError('SMS service is temporarily unavailable. Please try again later.', {
      httpStatus: null,
      responseBody: 'Missing MSG91 auth key',
    });
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
    const retryErr = new HttpsError(
      'failed-precondition',
      'OTP session expired. Send a new one.',
    );
    retryErr.httpStatus = statusCode;
    retryErr.responseBody = body;
    throw retryErr;
  }

  logMsg91Otp('retry_confirmed', {
    mobile: maskMsg91Mobile(normalizedMobile),
    httpStatus: statusCode,
    requestId: parsed.requestId,
  });
  return { ok: true, httpStatus: statusCode, responseBody: body, requestId: parsed.requestId };
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
    throw msg91UnavailableError('SMS service is temporarily unavailable. Please try again later.', {
      httpStatus: null,
      responseBody: 'Missing MSG91 auth key',
    });
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
    const err = new HttpsError(
      'failed-precondition',
      'SMS template is not configured. Contact support.',
    );
    err.httpStatus = null;
    err.responseBody = 'Missing MSG91 template ID';
    throw err;
  }

  if (!senderId || senderId.length < 3 || senderId.length > 6) {
    logMsg91Otp('invalid_sender_id', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId: senderId || null,
    });
    const err = new HttpsError(
      'failed-precondition',
      'SMS sender ID is not configured. Contact support.',
    );
    err.httpStatus = null;
    err.responseBody = 'Invalid MSG91 sender ID';
    throw err;
  }

  let statusCode = 0;
  let body = '';
  try {
    const postRes = await postMsg91OtpRequest({
      authKey,
      mobileDigits,
      code,
      templateId,
      senderId,
    });
    statusCode = postRes.statusCode;
    body = postRes.body;
    const requestPayload = postRes.requestPayload;

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
        // Operator-only detail; never expose infrastructure hints to end users.
        logMsg91Otp('send_auth_rejected_ip_allowlist', { severity: 'ERROR', otpType, mobile: maskedMobile });
      }
      const errorMsg = 'Could not send OTP SMS right now. Please try again in a few minutes.';
      const sendErr = new HttpsError('unavailable', errorMsg);
      sendErr.httpStatus = statusCode;
      sendErr.responseBody = body;
      throw sendErr;
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

    return {
      ok: true,
      requestId: parsed.requestId,
      templateId,
      senderId,
      httpStatus: statusCode,
      responseBody: body,
    };
  } catch (err) {
    if (err instanceof HttpsError) {
      if (!err.httpStatus && statusCode) {
        err.httpStatus = statusCode;
      }
      if (!err.responseBody && body) {
        err.responseBody = body;
      }
      throw err;
    }

    logMsg91Otp('send_network_error', {
      severity: 'ERROR',
      otpType,
      mobile: maskedMobile,
      templateId,
      senderId,
      error: err?.message || String(err),
    });
    throw msg91UnavailableError('Could not reach SMS service. Please try again later.', {
      httpStatus: err?.statusCode || null,
      responseBody: err?.message || String(err),
    });
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
  return normalizeRole(registeredRole) !== normalizeRole(requestedRole);
}

function mapLoginLookupRow(row) {
  return {
    found: true,
    role: row.role,
    uid: row.id,
    doc: { id: row.id },
    docId: row.id,
    matchedField: 'mobile',
    data: row,
  };
}

/**
 * Postgres login lookup (demo numbers -> staging plane, real -> RDS via login_lookup).
 * Fails CLOSED: a lookup error must never look like "no account" (that would let a
 * registration proceed for an already-registered number during a DB outage).
 */
async function findUserByMobileDigits(_db, digits, roleHint = null) {
  const {
    getLoginLookupClient,
    queryUserByMobile,
    resolveLoginLookupPlane,
  } = require('./src/db/login_lookup');
  let row;
  try {
    const plane = resolveLoginLookupPlane(digits, roleHint);
    const client = getLoginLookupClient(digits, roleHint);
    row = await queryUserByMobile(client, digits, { plane });
  } catch (err) {
    console.error('[findUserByMobileDigits] Postgres login lookup failed', {
      code: err.code || err.name,
      mobileLast4: String(digits || '').slice(-4),
    });
    if (err.code === 'demo_uid_rds_forbidden' || err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  if (row) {
    return mapLoginLookupRow(row);
  }
  return { found: false, role: null, uid: null, data: null };
}

/** Postgres lookup of an account by verified e-mail (public.users.email). */
async function findUserByEmail(_db, email) {
  const normalized = String(email || '').trim().toLowerCase();
  if (!normalized || !normalized.includes('@') || normalized.length > 254 || /[,()\s]/.test(normalized)) {
    return { found: false, role: null, uid: null, data: null };
  }
  const { getSupabaseAdminClient } = require('./caller_identity');
  const sb = getSupabaseAdminClient();
  if (!sb) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  const { data: rows, error } = await sb
    .from('users')
    .select('id, firebase_uid, role, email, profile_id')
    .eq('email', normalized)
    .limit(1);
  if (error) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  const row = Array.isArray(rows) ? rows[0] : null;
  if (!row) return { found: false, role: null, uid: null, data: null };
  return { found: true, role: row.role, uid: row.firebase_uid || row.id, data: row };
}

/**
 * Role used for the OTP challenge. Demo numbers always use their allowlisted role; the
 * unified phone step (otpType 'auth') has no role yet, so the challenge is keyed on 'patient'
 * for every real number (send and verify derive it the same way). Client roles never decide
 * the data plane or the demo bypass.
 */
function resolveChallengeRole(digits, otpType, requestedRole) {
  const demo = demoAccountByMobile(digits);
  if (demo) return demo.role;
  if (otpType === 'auth') return 'patient';
  return normalizeRole(requestedRole || 'patient');
}

async function sendUserRegistrationOtp(db, data, { clientIp = 'unknown' } = {}) {
  const otpType = String(data?.otpType || 'registration').trim();
  const canonicalDigits = canonicalMobileDigits(data?.mobile || data?.identifier);
  const role = resolveChallengeRole(canonicalDigits, otpType, data?.role);
  const initialMobile = data?.mobile || data?.identifier;
  const initialMobileLast4 = initialMobile ? String(initialMobile).replace(/\D/g, '').slice(-4) : null;

  console.info('[sendUserRegistrationOtp] Request received', {
    role,
    otpType,
    ipHash: hashRateLimitKey(clientIp).slice(0, 12),
    mobileLast4: initialMobileLast4,
  });

  if (isProductionFirebaseProject() && isOtpTestModeConfigured()) {
    console.error('[sendUserRegistrationOtp] OTP test mode is enabled in production');
    throw new HttpsError('failed-precondition', 'OTP test mode is enabled in production');
  }

  try {
    assertSupportedRole(role);
  } catch (err) {
    console.warn('[sendUserRegistrationOtp] Early exit', {
      reason: 'UNSUPPORTED_ROLE',
      role,
      error: err.message,
    });
    throw err;
  }

  const emailInput = String(data?.email || '').trim().toLowerCase();
  const isEmail = emailInput.includes('@');
  if (isEmail) {
    console.warn('[sendUserRegistrationOtp] Early exit', {
      reason: 'EMAIL_OTP_DISABLED',
      role,
      mobileLast4: initialMobileLast4,
    });
    throw new HttpsError('invalid-argument', 'Email OTP is disabled. Please enter your 10-digit mobile number for phone SMS verification.');
  }

  const digits = canonicalDigits;
  if (!digits) {
    console.warn('[sendUserRegistrationOtp] Early exit', {
      reason: 'INVALID_MOBILE',
      role,
      mobileLast4: initialMobileLast4,
    });
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }

  const mobileLast4 = digits.slice(-4);

  // Rate limits run BEFORE the account-existence lookup so the distinct
  // "already registered" / "no account" responses cannot be used for unlimited enumeration.
  try {
    await enforceSendOtpRateLimits(db, { clientIp, role, digits });
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'resource-exhausted') {
      console.warn('[sendUserRegistrationOtp] Early exit', {
        reason: 'RATE_LIMIT',
        ipHash: hashRateLimitKey(clientIp).slice(0, 12),
        role,
        mobileLast4,
      });
    }
    throw err;
  }

  const demoAccount = demoAccountByMobile(digits);
  if (demoAccount) {
    // Demo numbers: never an SMS, never a registration, only while the demo policy is active.
    if (otpType === 'registration') {
      throw new HttpsError('permission-denied', DEMO_REGISTRATION_BLOCKED_MESSAGE);
    }
    const policy = demoOtpPolicy();
    if (!policy.active) {
      console.warn('[sendUserRegistrationOtp] Demo OTP unavailable', { reason: policy.reason, mobileLast4 });
      throw new HttpsError('failed-precondition', DEMO_SIGNIN_UNAVAILABLE_MESSAGE);
    }
  }

  // Login, registration and the unified phone step ('auth') do NOT look the number up before
  // the OTP is verified: existing and unknown numbers get the same response (no enumeration).
  if (otpType === 'forgot_password') {
    let search = await findUserByMobileDigits(db, digits, role);
    let matchedField = search.matchedField
      || (search.data?.mobile ? 'mobile'
        : search.data?.phone ? 'phone'
        : search.data?.phoneNumber ? 'phoneNumber'
        : search.data?.mobileNumber ? 'mobileNumber'
        : null);
    let docId = search.doc?.id || search.docId || search.uid || null;

    console.info('[sendUserRegistrationOtp] findUserByMobileDigits result', {
      found: Boolean(search.found),
      matchedField: matchedField || null,
      docId,
      'doc.id': docId,
      storedRole: search.role || null,
      mobileLast4,
    });

    if (!search.found) {
      console.warn('[sendUserRegistrationOtp] Early exit', {
        reason: 'USER_NOT_FOUND',
        role,
        mobileLast4,
      });
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }

    const expectedRole = normalizeRole(role);
    const storedRoleNormalized = search.role ? normalizeRole(search.role) : null;
    const roleCheckPassed = !search.role || storedRoleNormalized === expectedRole;

    console.info('[sendUserRegistrationOtp] Role check', {
      expectedRole,
      storedRole: search.role || null,
      storedRoleNormalized,
      passed: roleCheckPassed,
      mobileLast4,
    });

    if (search.role && normalizeRole(search.role) !== normalizeRole(role)) {
      console.warn('[sendUserRegistrationOtp] Early exit', {
        reason: 'ROLE_MISMATCH',
        expectedRole,
        storedRole: search.role,
        storedRoleNormalized,
        mobileLast4,
      });
      console.warn('[sendUserRegistrationOtp] Login blocked: account type mismatch', {
        mobileSuffix: mobileLast4,
        requestedRole: role,
        existingRole: search.role,
      });
      throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
    }
  }

  {
    const isReviewerAccount = shouldSkipMsg91ForPhone(digits, role);
    if (isReviewerAccount) {
      if (!(await checkReviewerRateLimit(digits))) {
        emit(SEVERITY.WARNING, 'security', 'reviewer.rate_limited', {
          securityEvent: true,
          mobileHash: hashIdentifier(digits),
          role,
          reason: 'exceeded_reviewer_send_rate_limit',
        });
        throw new HttpsError('resource-exhausted', 'Too many OTP requests. Please wait and try again.');
      }
    }

    let redis = null;
    try {
      redis = getOtpRedisClient() || require('./redis').redis;
    } catch (_) {}
    if (!redis) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }

    const keyNull = otpRedisKey(null, digits);
    const keyRole = role ? otpRedisKey(role, digits) : null;
    let existingInRedis = null;
    try {
      const rawExisting = (keyNull ? await withOtpRedisTimeout(redis.get(keyNull)) : null)
        || (keyRole ? await withOtpRedisTimeout(redis.get(keyRole)) : null);
      if (rawExisting) existingInRedis = JSON.parse(rawExisting);
    } catch (err) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }

    if (existingInRedis?.sentAt && Date.now() - existingInRedis.sentAt < RESEND_COOLDOWN_MS) {
      throw new HttpsError('resource-exhausted', 'Please wait a minute before requesting another OTP.');
    }

    const code = isReviewerAccount ? resolveOutboundOtpCode(digits, role) : generateOtpCode();
    const expiryMs = OTP_EXPIRY_MS;
    const ttlSec = Math.max(1, Math.floor(expiryMs / 1000));
    const redisPayload = JSON.stringify({
      otpHash: hashOtp(code, { role, digits, purpose: 'create' }),
      role,
      mobileDigits: digits,
      sentAt: Date.now(),
      expiresAt: Date.now() + expiryMs,
      attempts: 0,
      ...(isReviewerAccount ? { reviewerAccount: true } : {}),
    });

    try {
      await Promise.all([
        keyNull ? withOtpRedisTimeout(redis.set(keyNull, redisPayload, 'EX', ttlSec)) : Promise.resolve(),
        keyRole ? withOtpRedisTimeout(redis.set(keyRole, redisPayload, 'EX', ttlSec)) : Promise.resolve(),
      ]);
      const attemptsKey = otpAttemptsRedisKey(digits);
      if (typeof redis.del === 'function') {
        await withOtpRedisTimeout(redis.del(attemptsKey)).catch(() => {});
      }
    } catch (err) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }

    if (!isReviewerAccount) {
      try {
        // Pass otpType so login / forgot-password use their own DLT templates.
        await sendMsg91SmsOtp(digits, code, otpType);
      } catch (err) {
        // Undelivered OTP must not block the user behind the resend cooldown.
        await deleteOtpRedisKeys(redis, role, digits).catch(() => {});
        throw err;
      }
    }

    return {
      ok: true,
      expiresInSeconds: Math.floor(expiryMs / 1000),
    };
  }

}


async function isChallengeOtpValid({ otp, challenge }) {
  const entered = String(otp || '').trim();
  if (verifyChallengeOtpHash(entered, challenge)) {
    return true;
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
  const digits = normalizeMobileDigits(mobileDigits);
  const normalizedRole = role ? normalizeRole(role) : null;

  {
    let redis = null;
    try {
      redis = getOtpRedisClient() || require('./redis').redis;
    } catch (_) {}
    if (!redis) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }

    const keyNull = otpRedisKey(null, digits);
    const keyRole = normalizedRole ? otpRedisKey(normalizedRole, digits) : null;
    const attemptsKey = otpAttemptsRedisKey(digits);

    let rawChallenge = null;
    try {
      // Role-scoped key first; the shared key is only a fallback and must match the role.
      rawChallenge = (keyRole ? await withOtpRedisTimeout(redis.get(keyRole)) : null)
        || (keyNull ? await withOtpRedisTimeout(redis.get(keyNull)) : null);
    } catch (err) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }

    if (!rawChallenge) {
      throw new HttpsError('failed-precondition', 'Send OTP first.');
    }

    let challenge;
    try {
      challenge = JSON.parse(rawChallenge);
    } catch (_) {
      challenge = {};
    }
    // A challenge issued for another role on the same number is never usable here.
    if (normalizedRole && challenge.role && normalizeRole(challenge.role) !== normalizedRole) {
      throw new HttpsError('failed-precondition', 'Send OTP first.');
    }

    if (challenge.expiresAt && Date.now() > challenge.expiresAt) {
      try {
        await deleteOtpRedisKeys(redis, normalizedRole, digits);
      } catch (_) {}
      throw new HttpsError('deadline-exceeded', 'OTP expired. Send a new one.');
    }

    let attemptNo;
    try {
      attemptNo = await reserveOtpVerifyAttemptSlot(redis, attemptsKey);
    } catch (err) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }
    if (attemptNo == null) {
      try {
        await deleteOtpRedisKeys(redis, normalizedRole, digits);
        if (typeof redis.del === 'function') {
          await withOtpRedisTimeout(redis.del(attemptsKey)).catch(() => {});
        }
      } catch (_) {}
      throw new HttpsError('resource-exhausted', 'Too many failed attempts. Request a new OTP.');
    }

    // Fixed demo OTP: only for the five allowlisted numbers (strict canonical match) while the
    // demo policy is active; constant-time compare. Every other number needs its own challenge.
    const demoPolicy = demoOtpPolicy();
    const isReviewerValid = demoPolicy.active
      && isDemoMobile(mobileDigits)
      && otpHashesEqual(otp, demoPolicy.fixedOtp);
    const localMatch = isReviewerValid || verifyChallengeOtpHash(otp, challenge, role, digits);

    if (localMatch) {
      // Single atomic multi-key DEL: exactly one concurrent verifier observes a deletion (single use).
      let delCount = 0;
      try {
        const keys = [keyRole, keyNull].filter(Boolean);
        delCount = Number(await withOtpRedisTimeout(redis.del(...keys))) || 0;
        await withOtpRedisTimeout(redis.del(attemptsKey)).catch(() => {});
      } catch (err) {
        throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
      }

      if (delCount === 0) {
        throw new HttpsError('failed-precondition', 'Send OTP first.');
      }

      return { consumed: true, challenge };
    }

    if (attemptNo >= OTP_VERIFY_ATTEMPT_MAX) {
      try {
        await deleteOtpRedisKeys(redis, normalizedRole, digits);
        if (typeof redis.del === 'function') {
          await withOtpRedisTimeout(redis.del(attemptsKey)).catch(() => {});
        }
      } catch (_) {}
      throw new HttpsError('resource-exhausted', 'Too many failed attempts. Request a new OTP.');
    }
    throw new HttpsError('permission-denied', 'Invalid OTP.');
  }

}


/**
 * Atomically validates and consumes an OTP verification session (Redis only).
 * GET+DEL runs in one Lua script so two concurrent completion calls can never both
 * consume the same session (single use). Fails closed when Redis is unavailable.
 */
async function consumeOtpVerificationSessionAtomically(
  _db,
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

  const sid = String(sessionId || '').trim();
  if (!/^[a-f0-9]{32}$/i.test(sid)) {
    throw new HttpsError('failed-precondition', msg.missing);
  }

  const redis = getRateLimitRedis();
  if (!redis) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }

  const key = otpSessionRedisKey(sid);
  let raw;
  try {
    if (typeof redis.eval === 'function') {
      raw = await withOtpRedisTimeout(redis.eval(
        "local v = redis.call('GET', KEYS[1]) if v then redis.call('DEL', KEYS[1]) end return v",
        1,
        key,
      ));
    } else if (typeof redis.getdel === 'function') {
      raw = await withOtpRedisTimeout(redis.getdel(key));
    } else {
      raw = await withOtpRedisTimeout(redis.get(key));
      if (raw) await withOtpRedisTimeout(redis.del(key));
    }
  } catch (_) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }

  if (!raw) {
    throw new HttpsError('failed-precondition', msg.missing);
  }

  let session;
  try {
    session = JSON.parse(raw);
  } catch (_) {
    throw new HttpsError('failed-precondition', msg.missing);
  }
  if (session.consumed === true) {
    throw new HttpsError('failed-precondition', msg.alreadyUsed);
  }
  const expiresAt = session.expiresAt ? new Date(session.expiresAt) : null;
  if (!expiresAt || Number.isNaN(expiresAt.getTime()) || Date.now() > expiresAt.getTime()) {
    throw new HttpsError('deadline-exceeded', msg.expired);
  }
  if (session.mobileDigits) {
    await withOtpRedisTimeout(
      redis.del(otpSessionRedisKey(mobileHash(session.role, session.mobileDigits))),
    ).catch(() => {});
  }
  if (assertSession) {
    assertSession(session);
  }
  return session;
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

function demoLockoutKeys(digits) {
  const h = crypto.createHash('sha256').update(`demo-otp:${digits}`).digest('hex').slice(0, 32);
  return {
    failures: envPrefixedRedisKey(`demo_otp_fail:${h}`),
    lock: envPrefixedRedisKey(`demo_otp_lock:${h}`),
  };
}

/** Per-number lockout for the fixed demo OTP: 5 failures within 30 min lock the number for 30 min. */
async function assertDemoNotLockedOut(digits) {
  const redis = getRateLimitRedis();
  if (!redis || typeof redis.get !== 'function') {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  let locked = null;
  try {
    locked = await withOtpRedisTimeout(redis.get(demoLockoutKeys(digits).lock));
  } catch (_) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  if (locked) {
    throw new HttpsError('resource-exhausted', 'Too many failed attempts. Try again later.');
  }
}

async function recordDemoOtpFailure(digits) {
  const redis = getRateLimitRedis();
  if (!redis) return;
  const keys = demoLockoutKeys(digits);
  const ttlSec = Math.ceil(DEMO_LOCKOUT_WINDOW_MS / 1000);
  try {
    const n = Number(await withOtpRedisTimeout(redis.incr(keys.failures))) || 0;
    if (n === 1 && typeof redis.pexpire === 'function') {
      await withOtpRedisTimeout(redis.pexpire(keys.failures, DEMO_LOCKOUT_WINDOW_MS));
    }
    if (n >= DEMO_LOCKOUT_MAX_FAILURES) {
      await withOtpRedisTimeout(redis.set(keys.lock, '1', 'EX', ttlSec));
      emit(SEVERITY.WARNING, 'security', 'demo_otp.locked_out', {
        securityEvent: true,
        mobileHash: hashIdentifier(digits),
      });
    }
  } catch (_) {
    // Lockout bookkeeping is best effort; the per-challenge attempt limit still applies.
  }
}

async function clearDemoOtpFailures(digits) {
  const redis = getRateLimitRedis();
  if (!redis || typeof redis.del !== 'function') return;
  await withOtpRedisTimeout(redis.del(demoLockoutKeys(digits).failures)).catch(() => {});
}

async function verifyUserRegistrationOtp(db, data, auth, { clientIp = 'unknown' } = {}) {
  const otpTypeEarly = String(data?.otpType || 'registration').trim();
  const canonicalDigits = canonicalMobileDigits(data?.mobile || data?.identifier);
  const role = resolveChallengeRole(canonicalDigits, otpTypeEarly, data?.role);
  assertSupportedRole(role);

  const emailInput = String(data?.email || data?.identifier || '').trim().toLowerCase();
  const isEmail = emailInput.includes('@');
  if (isEmail) {
    throw new HttpsError('invalid-argument', 'Email verification is disabled. Please verify via mobile phone SMS OTP.');
  }

  const digits = canonicalDigits;
  const otp = String(data?.otp || '').trim();
  const otpType = otpTypeEarly;
  const demoAccount = demoAccountByMobile(digits);

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

  if (demoAccount && otpType === 'registration') {
    throw new HttpsError('permission-denied', DEMO_REGISTRATION_BLOCKED_MESSAGE);
  }

  await enforceVerifyOtpRateLimits(db, { clientIp, role, digits });
  if (demoAccount) {
    await assertDemoNotLockedOut(digits);
  }

  const challengeKey = mobileHash(role, digits);

  try {
    await consumeOtpChallengeAtomically(db, {
      challengeKey,
      otp,
      mobileDigits: digits,
      role,
    });
  } catch (err) {
    if (demoAccount && err instanceof HttpsError
      && (err.code === 'permission-denied' || err.code === 'resource-exhausted')) {
      await recordDemoOtpFailure(digits);
    }
    throw err;
  }
  if (demoAccount) {
    await clearDemoOtpFailures(digits);
  }

  const accountSearch = await findUserByMobileDigits(db, digits, role);
  const postOtpAccount = postOtpAccountFieldsFromSearch(accountSearch);

  if (demoAccount) {
    // A demo number only ever signs in to its pre-provisioned staging account with the
    // allowlisted role and UID; it never gets a registration session.
    if (!accountSearch.found || !accountSearch.uid) {
      console.error('[verifyUserRegistrationOtp] Demo account missing on the staging plane', {
        mobileLast4: digits.slice(-4),
        role: demoAccount.role,
      });
      throw new HttpsError('failed-precondition', DEMO_SIGNIN_UNAVAILABLE_MESSAGE);
    }
    if (normalizeRole(accountSearch.role) !== demoAccount.role || accountSearch.uid !== demoAccount.uid) {
      console.error('[verifyUserRegistrationOtp] Demo account does not match the allowlist', {
        mobileLast4: digits.slice(-4),
      });
      throw new HttpsError('failed-precondition', DEMO_SIGNIN_UNAVAILABLE_MESSAGE);
    }
  }

  // Unified phone step ('auth'): an unknown number gets a role-less session ('auth') that the
  // registration step later binds to the role the user picks.
  const sessionRole = otpType === 'auth'
    ? (postOtpAccount.exists && postOtpAccount.role ? postOtpAccount.role : 'auth')
    : role;

  const sessionId = crypto.randomBytes(16).toString('hex');
  const SESSION_TTL_SEC = 900;

  // Signed-in account changing contact info: Postgres users row must already hold this number.
  if (auth?.uid && !isEmail && otpType === 'contact_change') {
    const userProfile = await readUserProfile(db, auth.uid);
    if (userProfile) {
      const signedInRoles = new Set(['patient', 'doctor', 'lab', 'medicalStore', 'ambulance']);
      const userRole = normalizeRole(userProfile.role);
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

  // Verified-OTP session (bearer secret) lives only in Redis with a 15-minute TTL. Fail closed:
  // without a stored session the follow-up registration/login step would silently break.
  {
    const redis = getRateLimitRedis();
    if (!redis || typeof redis.set !== 'function') {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }
    const sessionData = {
      role: sessionRole,
      identifier: digits,
      email: null,
      mobileDigits: digits,
      mobileVerified: true,
      emailVerified: false,
      verifiedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + SESSION_TTL_SEC * 1000).toISOString(),
      consumed: false,
    };
    const jsonStr = JSON.stringify(sessionData);
    try {
      await withOtpRedisTimeout(redis.set(otpSessionRedisKey(sessionId), jsonStr, 'EX', SESSION_TTL_SEC));
      await withOtpRedisTimeout(
        redis.set(otpSessionRedisKey(mobileHash(sessionRole, digits)), jsonStr, 'EX', SESSION_TTL_SEC),
      );
    } catch (_) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }
  }

  // Phone OTP login (and generic auth after OTP) must establish a real Firebase Auth session.
  const shouldCompleteLogin =
    otpType === 'login' || (otpType === 'auth' && postOtpAccount.exists && accountSearch.uid);
  if (shouldCompleteLogin) {
    const search = accountSearch;
    const loginRole =
      otpType === 'login' ? role : postOtpAccount.role || role;
    if (!search.found || !search.uid) {
      throw new HttpsError('not-found', 'No account found for this mobile number. Please register first.');
    }
    if (search.role && normalizeRole(search.role) !== normalizeRole(loginRole)) {
      console.warn('[verifyUserRegistrationOtp] Login blocked: account type mismatch', {
        mobileSuffix: digits.slice(-4),
        requestedRole: loginRole,
        existingRole: search.role,
      });
      throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
    }
    const claims = supabaseCompatibleCustomClaims(loginRole);
    try {
      await getAuth().setCustomUserClaims(search.uid, claims);
    } catch (claimErr) {
      console.warn('[verifyUserRegistrationOtp] Failed to set permanent custom claims:', claimErr?.message || claimErr);
    }
    const customToken = await getAuth().createCustomToken(
      search.uid,
      claims,
    );
    const registeredRole = normalizeRole(search.role) || loginRole;
    console.info('[verifyUserRegistrationOtp] Login OTP verified successfully, customToken minted', {
      role: loginRole,
      mobileLast4: digits.slice(-4),
      uid: search.uid,
    });
    return {
      ok: true,
      mobileVerified: true,
      sessionId,
      customToken,
      uid: search.uid,
      exists: true,
      role: registeredRole,
    };
  }

  // sessionId is a bearer credential: never log it.
  console.info('[verifyUserRegistrationOtp] Registration OTP verified successfully, session issued', {
    role,
    mobileLast4: digits.slice(-4),
  });

  return {
    ok: true,
    mobileVerified: !isEmail,
    emailVerified: isEmail,
    sessionId,
    exists: postOtpAccount.exists,
    role: postOtpAccount.role,
  };
}

const ORPHAN_AUTH_MAX_AGE_MS = 10 * 60 * 1000;

function hashUidForLog(uid) {
  return crypto.createHash('sha256').update(String(uid || '')).digest('hex').slice(0, 12);
}

async function loadRegistrationProfileSnapshot(db, uid) {
  const row = await readUserProfile(db, uid);
  if (row) {
    const verified = row.mobile_verified === true || row.email_verified === true;
    const createdMs = row.created_at ? Date.parse(row.created_at) : null;
    return {
      exists: true,
      verified,
      createdMs: Number.isFinite(createdMs) ? createdMs : null,
      profileId: row.profile_id || null,
      role: row.role || null,
    };
  }
  return {
    exists: false,
    verified: false,
    createdMs: null,
    profileId: null,
    role: null,
  };
}

function isFreshOrphanRegistrationProfile(snapshot, nowMs) {
  if (!snapshot?.exists) return false;
  if (snapshot.verified) return false;
  if (!Number.isFinite(snapshot.createdMs)) return false;
  return nowMs - snapshot.createdMs <= ORPHAN_AUTH_MAX_AGE_MS;
}

async function maybeDeleteFreshOrphanRegistrationProfile(db, uid, { nowMs = Date.now() } = {}) {
  const snapshot = await loadRegistrationProfileSnapshot(db, uid);
  if (!isFreshOrphanRegistrationProfile(snapshot, nowMs)) {
    return { deleted: false, reason: snapshot.exists ? 'profile_not_orphan' : 'no_profile' };
  }

  const { getDatabaseClient } = require('./src/db/client');
  const client = getDatabaseClient({ firebaseUid: uid });
  const profileId = String(snapshot.profileId || '').trim();
  const role = normalizeRole(snapshot.role || '');
  if (profileId && role === 'patient') {
    await client.from('patients').delete().eq('patient_id', profileId);
  } else if (profileId && role === 'doctor') {
    await client.from('doctors').delete().eq('doctor_id', profileId);
  }
  await client.from('users').delete().eq('id', uid);

  console.warn('[registration_rollback] deleted fresh orphan profile rows', {
    uidHash: hashUidForLog(uid),
  });
  return { deleted: true };
}

async function authUserHasPersistedProfile(db, uid) {
  const snapshot = await loadRegistrationProfileSnapshot(db, uid);
  return { exists: snapshot.exists, verified: snapshot.verified };
}

/**
 * Deletes the authenticated caller's Auth user only when it is a fresh orphan
 * (no profile row, no verification flags, created within ORPHAN_AUTH_MAX_AGE_MS).
 */
async function maybeDeleteOrphanRegistrationAuthUser(
  auth,
  db,
  {
    nowMs = Date.now(),
    authAdmin = getAuth(),
    loadProfile = loadRegistrationProfileSnapshot,
  } = {},
) {
  const uid = String(auth?.uid || '').trim();
  if (!uid) {
    return { deleted: false, reason: 'no_auth' };
  }

  let record;
  try {
    record = await authAdmin.getUser(uid);
  } catch (_) {
    return { deleted: false, reason: 'auth_user_not_found' };
  }

  const createdMs = Date.parse(record.metadata?.creationTime || '');
  if (!Number.isFinite(createdMs) || nowMs - createdMs > ORPHAN_AUTH_MAX_AGE_MS) {
    return { deleted: false, reason: 'too_old' };
  }

  let snapshot;
  try {
    snapshot = await loadProfile(db, uid);
  } catch (_) {
    return { deleted: false, reason: 'profile_check_failed' };
  }

  if (snapshot.verified) {
    return { deleted: false, reason: 'verified_flag_set' };
  }

  if (snapshot.exists) {
    if (!isFreshOrphanRegistrationProfile(snapshot, nowMs)) {
      return { deleted: false, reason: 'profile_exists' };
    }
    try {
      await maybeDeleteFreshOrphanRegistrationProfile(db, uid, { nowMs });
    } catch (err) {
      console.warn('[registration_rollback] orphan profile delete failed', {
        uidHash: hashUidForLog(uid),
        error: err?.message || String(err),
      });
      return { deleted: false, reason: 'profile_delete_failed' };
    }
  }

  try {
    await authAdmin.deleteUser(uid);
    console.warn('[registration_rollback] deleted orphan auth user', {
      uidHash: hashUidForLog(uid),
    });
    return { deleted: true };
  } catch (err) {
    console.warn('[registration_rollback] delete orphan auth user failed', {
      uidHash: hashUidForLog(uid),
      error: err?.message || String(err),
    });
    return { deleted: false, reason: 'delete_failed' };
  }
}

function authTokenHasVerifiedRegistrationClaims(auth) {
  const token = auth?.token || {};
  return (
    token.mobile_verified === true ||
    token.mobileVerified === true ||
    token.email_verified === true ||
    token.emailVerified === true
  );
}

/**
 * Callable entry: caller may clean up their own fresh, unverified registration attempt.
 * Never reveals whether another account exists — only { ok, cleaned } for the caller.
 */
async function cleanupPendingRegistration(
  db,
  auth,
  {
    nowMs = Date.now(),
    authAdmin = getAuth(),
    loadProfile = loadRegistrationProfileSnapshot,
  } = {},
) {
  const uid = String(auth?.uid || '').trim();
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  if (authTokenHasVerifiedRegistrationClaims(auth)) {
    return { ok: true, cleaned: false };
  }

  let snapshot;
  try {
    snapshot = await loadProfile(db, uid);
  } catch (err) {
    console.warn('[cleanupPendingRegistration] profile check failed', {
      uidHash: hashUidForLog(uid),
      error: err?.message || String(err),
    });
    return { ok: true, cleaned: false };
  }

  if (snapshot.verified) {
    return { ok: true, cleaned: false };
  }

  let record;
  try {
    record = await authAdmin.getUser(uid);
  } catch (_) {
    return { ok: true, cleaned: false };
  }

  const createdMs = Date.parse(record.metadata?.creationTime || '');
  if (!Number.isFinite(createdMs) || nowMs - createdMs > ORPHAN_AUTH_MAX_AGE_MS) {
    return { ok: true, cleaned: false };
  }

  let cleaned = false;

  if (snapshot.exists && isFreshOrphanRegistrationProfile(snapshot, nowMs)) {
    try {
      const profileResult = await maybeDeleteFreshOrphanRegistrationProfile(db, uid, {
        nowMs,
      });
      if (profileResult.deleted) cleaned = true;
    } catch (err) {
      console.warn('[cleanupPendingRegistration] profile delete failed', {
        uidHash: hashUidForLog(uid),
        error: err?.message || String(err),
      });
      return { ok: true, cleaned: false };
    }
  }

  const authResult = await maybeDeleteOrphanRegistrationAuthUser(auth, db, {
    nowMs,
    authAdmin,
    loadProfile,
  });
  if (authResult.deleted) cleaned = true;

  console.warn('[cleanupPendingRegistration] completed', {
    uidHash: hashUidForLog(uid),
    cleaned,
  });
  return { ok: true, cleaned };
}

async function finalizePatientOtpVerification(db, data, auth) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required to finalize verification.');
  }

  try {
    const sessionId = String(data?.sessionId || '').trim();
    if (!sessionId) {
      throw new HttpsError('invalid-argument', 'sessionId is required.');
    }

    const userProfile = await readUserProfile(db, auth.uid);
    const userRole = normalizeRole(userProfile?.role);
    if (!userProfile || !['patient', 'doctor', 'lab', 'medicalStore', 'ambulance'].includes(userRole)) {
      throw new HttpsError('permission-denied', 'Supported account role required.');
    }

    const profileId = String(userProfile.profileId || '').trim();
    if (!profileId) {
      throw new HttpsError('failed-precondition', 'Patient profile not found.');
    }

    const session = await consumeOtpVerificationSessionAtomically(db, sessionId, {
      assertSession: (sessionData) => {
        // Unified phone step sessions are role-less ('auth') until the user picks a role.
        const roleOk = sessionData.role === userRole || sessionData.role === 'auth';
        if (!roleOk || sessionData.mobileVerified !== true) {
          throw new HttpsError('failed-precondition', 'OTP verification incomplete.');
        }
        // Demo numbers never register (they are pre-provisioned on the staging plane only).
        if (isDemoMobile(sessionData.mobileDigits)) {
          throw new HttpsError('permission-denied', DEMO_REGISTRATION_BLOCKED_MESSAGE);
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

    const claims = supabaseCompatibleCustomClaims(userRole);
    try {
      await getAuth().setCustomUserClaims(auth.uid, claims);
    } catch (claimErr) {
      console.warn('[finalizePatientOtpVerification] Failed to set custom claims:', claimErr?.message || claimErr);
    }

    return { ok: true, mobileVerified: true, profileId };
  } catch (err) {
    try {
      await maybeDeleteOrphanRegistrationAuthUser(auth, db);
    } catch (_) {}
    throw err;
  }
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

function ambulanceRowToProfile(row) {
  return {
    username: row.username || '',
    serviceName: row.service_name || '',
    driverName: row.driver_name || '',
    city: row.city || '',
    phone: row.phone || '',
    authUid: row.auth_uid || null,
    isAvailable: row.is_available !== false,
  };
}

/** Postgres lookup of a registered ambulance by phone (reviewer numbers -> staging plane). */
async function findAmbulanceByPhone(_db, phone) {
  const digits = normalizeMobileDigits(phone);
  if (!digits) return null;
  const { getLoginLookupClient } = require('./src/db/login_lookup');
  const client = getLoginLookupClient(digits, 'ambulance');
  const { data, error } = await client
    .from('ambulances')
    .select('ambulance_id, auth_uid, username, service_name, driver_name, city, phone, is_available')
    .in('phone', phoneLookupCandidates(digits))
    .limit(5);
  if (error) {
    throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
  }
  for (const row of data || []) {
    const profile = ambulanceRowToProfile(row);
    if (!isRegisteredAmbulanceData(profile)) continue;
    return { id: row.ambulance_id, data: profile, client };
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

  if (found.data.authUid !== auth.uid) {
    const { error } = await found.client
      .from('ambulances')
      .update({ auth_uid: auth.uid, updated_at: new Date().toISOString() })
      .eq('ambulance_id', found.id);
    if (error) {
      throw new HttpsError('unavailable', 'Authentication service temporarily unavailable.');
    }
  }

  try {
    await getAuth().setCustomUserClaims(
      auth.uid,
      supabaseCompatibleCustomClaims('ambulance'),
    );
  } catch (claimErr) {
    console.warn('[completeAmbulanceMobileOtpLogin] Failed to set custom claims:', claimErr?.message || claimErr);
  }

  const username = String(found.data.username || '').trim().toLowerCase();
  if (username) {
    await clearLoginFailureBucket(db, resolveLoginBuckets({ identifier: `ambulance:${username}` }).idBucket)
      .catch(() => {});
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
  if (newPin.length < 6 || newPin.length > 64) {
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

  const nowIso = new Date().toISOString();
  const { error: pinErr } = await found.client
    .from('ambulance_private_settings')
    .upsert({
      ambulance_id: found.id,
      pin_hash: hashAmbulancePin(newPin),
      updated_at: nowIso,
    }, { onConflict: 'ambulance_id' });
  if (pinErr) {
    throw new HttpsError('unavailable', 'Could not update PIN. Please try again.');
  }
  const { error: ambErr } = await found.client
    .from('ambulances')
    .update({ auth_uid: auth.uid, updated_at: nowIso })
    .eq('ambulance_id', found.id);
  if (ambErr) {
    throw new HttpsError('unavailable', 'Could not update PIN. Please try again.');
  }

  // A PIN reset clears any brute-force lockout for this driver.
  const username = String(found.data.username || '').trim().toLowerCase();
  if (username) {
    await clearLoginFailureBucket(db, resolveLoginBuckets({ identifier: `ambulance:${username}` }).idBucket)
      .catch(() => {});
  }

  return {
    ok: true,
    driverId: found.id,
    username: String(found.data.username || '').trim(),
  };
}

async function resetUserPasswordWithOtp(db, data, { clientIp = 'unknown' } = {}) {
  const role = normalizeRole(data?.role || '');
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
      const sessionRole = normalizeRole(session.role);
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
    const search = await findUserByMobileDigits(db, digits, role);
    if (!search.found || !search.uid) {
      throw new HttpsError('not-found', 'No account found with this mobile number.');
    }
    if (search.role && normalizeRole(search.role) !== role) {
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

/**
 * Exchanges a verified mobile OTP session for a Firebase custom token so the
 * client gets a real Auth session (request.auth) instead of a local-only profile.
 */
async function completeMobileOtpLogin(db, data, { clientIp = 'unknown' } = {}) {
  const role = normalizeRole(data?.role || '');
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
      const sessionRole = normalizeRole(session.role);
      const sessionMobile = normalizeMobileDigits(session.mobileDigits || session.identifier);
      const roleMatchesSession =
        sessionRole === role || sessionRole === 'auth';
      if (!roleMatchesSession || session.mobileVerified !== true) {
        throw new HttpsError('permission-denied', 'OTP verification incomplete.');
      }
      if (!sessionMobile || sessionMobile !== mobileDigits) {
        throw new HttpsError('permission-denied', 'OTP session does not match this mobile number.');
      }
    },
  });

  const search = await findUserByMobileDigits(db, mobileDigits, role);
  if (!search.found || !search.uid) {
    throw new HttpsError('not-found', 'No account found for this mobile number.');
  }
  if (search.role && normalizeRole(search.role) !== role) {
    console.warn('[completeAmbulanceMobileOtpLogin] Login blocked: account type mismatch', {
      mobileSuffix: mobileDigits.slice(-4),
      requestedRole: role,
      existingRole: search.role,
    });
    throw new HttpsError('failed-precondition', LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE);
  }

  const authUid = search.uid;
  try {
    await getAuth().getUser(authUid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'No Firebase account found for this mobile number.');
    } else {
      logInternalError('completeMobileOtpLogin', e, { authUid, stage: 'getUser' });
      throw new HttpsError('internal', GENERIC_MOBILE_LOGIN_FAILED);
    }
  }

  const claims = supabaseCompatibleCustomClaims(role, { loginMethod: 'mobile_otp' });
  try {
    await getAuth().setCustomUserClaims(authUid, claims);
  } catch (claimErr) {
    console.warn('[completeMobileOtpLogin] Failed to set permanent custom claims:', claimErr?.message || claimErr);
  }
  const customToken = await getAuth().createCustomToken(
    authUid,
    claims,
  );
  const registeredRole = normalizeRole(search.role) || role;
  return {
    ok: true,
    customToken,
    uid: authUid,
    exists: true,
    role: registeredRole,
  };
}

async function assertLoginAllowed(db, data, { clientIp = 'unknown' } = {}) {
  const { idBucket, ipBucket } = resolveLoginBuckets(data, clientIp);
  const [idCount, ipCount] = await Promise.all([
    readLoginFailureCount(idBucket),
    readLoginFailureCount(ipBucket),
  ]);
  for (const [count, max] of [[idCount, LOGIN_IDENTIFIER_MAX], [ipCount, LOGIN_IP_MAX]]) {
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
      error: err?.message || String(err),
    });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', 'Failed to record login failure.');
  }
}

/**
 * Clears the failed-login counter after a successful sign-in. Only the signed-in owner of the
 * identifier may clear it (previously anyone could reset any account's lockout between guesses).
 */
async function clearFailedLogins(db, data, auth = null) {
  const { idBucket, identifier } = resolveLoginBuckets(data);
  const callerEmail = String(auth?.token?.email || '').trim().toLowerCase();
  if (!auth?.uid || !callerEmail || callerEmail !== identifier) {
    throw new HttpsError('permission-denied', 'Not allowed to clear login attempts for this account.');
  }
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

/**
 * Account deletion: remove every OTP challenge, attempt counter and verified-session key for
 * a mobile number (all roles). Rate-limit buckets are intentionally kept (abuse protection).
 */
async function purgeOtpStateForMobile(mobileDigits) {
  const digits = normalizeMobileDigits(mobileDigits);
  const redis = getRateLimitRedis();
  if (!digits || !redis) return { ok: false };
  const roles = [null, 'patient', 'doctor', 'medicalStore', 'lab', 'ambulance'];
  const keys = [otpAttemptsRedisKey(digits)];
  for (const r of roles) {
    const challengeKey = otpRedisKey(r, digits);
    if (challengeKey) keys.push(challengeKey);
    if (r) keys.push(otpSessionRedisKey(mobileHash(r, digits)));
  }
  await Promise.all(keys.map((k) => withOtpRedisTimeout(redis.del(k)).catch(() => {})));
  return { ok: true, keys: keys.length };
}

/** Server-side only: clear an identifier's failure counter after credentials were verified here. */
async function clearFailedLoginsTrusted(identifier) {
  const { idBucket } = resolveLoginBuckets({ identifier });
  await clearLoginFailureBucket(null, idBucket);
  return { ok: true };
}

const recordLoginFailure = recordFailedLogin;
const resetLoginAttempts = clearFailedLogins;

/** Post-OTP only: whether mobile maps to an existing account and its role (additive verify/login fields). */
function postOtpAccountFieldsFromSearch(search) {
  const exists = Boolean(search?.found);
  const role = exists && search?.role ? normalizeRole(search.role) : null;
  return { exists, role };
}

/** Authoritative lookup: conflict flag plus whether mobile exists and registered role (main 4d9f64f, no demo bypass). */
async function lookupMobileRegistration(db, data) {
  const digits = normalizeMobileDigits(data?.mobile);
  if (!digits) {
    throw new HttpsError('invalid-argument', 'Enter a valid 10-digit mobile number.');
  }
  const intent = String(data?.intent || 'login').trim();
  if (intent !== 'login' && intent !== 'registration') {
    throw new HttpsError('invalid-argument', 'Invalid lookup intent.');
  }
  const requestedRole = normalizeRole(data?.role || '');
  const search = await findUserByMobileDigits(db, digits, requestedRole || null);
  const registeredRole = search.found ? normalizeRole(search.role) : null;
  const exists = Boolean(search.found);
  const conflict = resolveMobileLookupConflict({
    found: exists,
    registeredRole,
    requestedRole,
    intent,
  });
  return {
    ok: true,
    conflict,
    exists,
    role: exists ? registeredRole : null,
  };
}

/**
 * Supabase third-party Firebase auth requires the JWT `role` claim to be
 * `authenticated`. The app role stays in `app_role`. Firestore rules read
 * users/{uid}.role, not this claim.
 */
function supabaseCompatibleCustomClaims(appRole, extra) {
  let normalized = appRole;
  if (appRole === 'superAdmin' || appRole === 'super_admin' || appRole === 'admin') {
    normalized = 'super_admin';
  } else if (appRole === 'medicalStore' || appRole === 'medical') {
    normalized = 'pharmacy';
  }
  return {
    role: 'authenticated',
    app_role: normalized,
    user_role: normalized,
    ...(extra || {}),
  };
}

module.exports = {
  sendUserRegistrationOtp,
  consumeOtpChallengeAtomically,
  consumeOtpVerificationSessionAtomically,
  verifyUserRegistrationOtp,
  hashOtp,
  lookupMobileRegistration,
  postOtpAccountFieldsFromSearch,
  maybeDeleteOrphanRegistrationAuthUser,
  maybeDeleteFreshOrphanRegistrationProfile,
  loadRegistrationProfileSnapshot,
  isFreshOrphanRegistrationProfile,
  authUserHasPersistedProfile,
  ORPHAN_AUTH_MAX_AGE_MS,
  hashUidForLog,
  resolveMobileLookupConflict,
  REGISTRATION_MOBILE_EXISTS_MESSAGE,
  LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE,
  cleanupPendingRegistration,
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
  clearFailedLoginsTrusted,
  purgeOtpStateForMobile,
  consumeLoginAttempt,
  recordLoginFailure,
  resetLoginAttempts,
  hashAmbulancePin,
  ambulancePinMatches,
  supabaseCompatibleCustomClaims,
  normalizeRole,
  normalizeMobileDigits,
  verifyMsg91Otp,
  otpRedisKey,
  otpAttemptsRedisKey,
  otpSessionRedisKey,
  reserveOtpVerifyAttemptSlot,
  isOtpRedisMirrorEnabled,
  OTP_REDIS_TIMEOUT_MS,
  allowLegacyUnsaltedOtpHash,
  legacyHashOtp,
  verifyChallengeOtpHash,
  enforceSendOtpRateLimits,
  enforceVerifyOtpRateLimits,
  getReviewerConfig,
  isReviewerPhone,
  isStagingDemoPhone,
  resolveChallengeRole,
  assertDemoNotLockedOut,
  recordDemoOtpFailure,
  shouldSkipMsg91ForPhone,
  checkReviewerRateLimit,
  setReviewerRedisClientForTesting,
  resetReviewerRateLimitForTesting,
};
