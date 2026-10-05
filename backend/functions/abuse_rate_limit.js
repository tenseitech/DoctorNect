'use strict';

const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { logUnusualTraffic } = require('./security_logger');

/** Shared abuse / bot protection rate limits (Firestore-backed). */
const LIMITS = {
  api: {
    ip: { windowMs: 60 * 1000, max: 120 },
    uid: { windowMs: 60 * 1000, max: 90 },
  },
  login: {
    // Failures are counted in registration_otp; this is a pre-check envelope.
    ip: { windowMs: 15 * 60 * 1000, max: 40 },
    id: { windowMs: 15 * 60 * 1000, max: 10 },
  },
  signup: {
    ip: { windowMs: 60 * 60 * 1000, max: 5 },
    id: { windowMs: 24 * 60 * 60 * 1000, max: 3 },
  },
  otp_send: {
    ip: { windowMs: 15 * 60 * 1000, max: 30 },
    id: { windowMs: 15 * 60 * 1000, max: 6 },
  },
  ai: {
    ip: { windowMs: 60 * 60 * 1000, max: 60 },
    uid: { windowMs: 60 * 60 * 1000, max: 40 },
  },
  scrape: {
    // Directory / list-style callables
    ip: { windowMs: 60 * 1000, max: 30 },
    uid: { windowMs: 60 * 1000, max: 20 },
  },
  payment: {
    ip: { windowMs: 60 * 60 * 1000, max: 30 },
    uid: { windowMs: 60 * 60 * 1000, max: 20 },
  },
};

function hashKey(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function clientIpFromRequest(request) {
  const raw = request?.rawRequest;
  if (!raw) return 'unknown';
  const forwarded = raw.headers?.['x-forwarded-for'];
  if (forwarded) return String(forwarded).split(',')[0].trim();
  return raw.ip || raw.socket?.remoteAddress || 'unknown';
}

async function assertBucket(db, { bucket, windowMs, maxAttempts, message }) {
  const ref = db.collection('abuse_rate_limits').doc(bucket);
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
        message || 'Too many requests. Please slow down and try again later.',
      );
    }

    tx.set(ref, {
      count: count + 1,
      windowStart: withinWindow
        ? data.windowStart
        : Timestamp.fromDate(new Date(nowMs)),
      updatedAt: FieldValue.serverTimestamp(),
      category: String(bucket).split('_')[0] || 'abuse',
    }, { merge: true });
  });
}

function getRateLimitBackend() {
  return String(process.env.RATE_LIMIT_BACKEND || 'firestore').trim().toLowerCase();
}

const LUA_INCR_EXPIRE = `
local current = redis.call('INCR', KEYS[1])
if current == 1 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
else
  local ttl = redis.call('PTTL', KEYS[1])
  if ttl == -1 then
    redis.call('PEXPIRE', KEYS[1], ARGV[1])
  end
end
return current
`;

function withRedisTimeout(promise, ms = 1500) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Redis rate limit operation timed out')), ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timer));
}

async function executeRedisCounter(client, key, windowMs) {
  if (typeof client.eval === 'function') {
    const res = await withRedisTimeout(client.eval(LUA_INCR_EXPIRE, 1, key, String(windowMs)), 1500);
    return Number(res);
  }
  if (typeof client.multi === 'function') {
    const results = await withRedisTimeout(client.multi().incr(key).pexpire(key, windowMs).exec(), 1500);
    return Number(results?.[0]?.[1] ?? results?.[0] ?? 1);
  }
  const count = await withRedisTimeout(client.incr(key), 1500);
  if (count === 1 && typeof client.pexpire === 'function') {
    await withRedisTimeout(client.pexpire(key, windowMs), 1500);
  }
  return Number(count);
}

async function assertBucketRedis(redisClient, { key, windowMs, maxAttempts, message }) {
  const current = await executeRedisCounter(redisClient, key, windowMs);
  if (current > maxAttempts) {
    throw new HttpsError(
      'resource-exhausted',
      message || 'Too many requests. Please slow down and try again later.',
    );
  }
}

async function assertBucketUnified({ db, redisClient, useRedis, bucket, redisKey, windowMs, maxAttempts, message }) {
  if (useRedis && redisClient) {
    try {
      await assertBucketRedis(redisClient, {
        key: redisKey,
        windowMs,
        maxAttempts,
        message,
      });
      return;
    } catch (err) {
      if (err instanceof HttpsError && err.code === 'resource-exhausted') {
        throw err;
      }
      console.warn(`[abuse_rate_limit] Redis rate limit check failed (${err?.message || err}), falling back to Firestore`);
    }
  }
  await assertBucket(db, { bucket, windowMs, maxAttempts, message });
}

/**
 * Enforce category limits for IP (+ uid when authenticated).
 * @param {'api'|'login'|'signup'|'otp_send'|'ai'|'scrape'|'payment'} category
 */
async function enforceAbuseLimit(db, request, category, {
  identifier,
  message,
} = {}) {
  const limits = LIMITS[category];
  if (!limits) {
    throw new HttpsError('internal', `Unknown abuse category: ${category}`);
  }

  const ip = clientIpFromRequest(request);
  const uid = request?.auth?.uid || '';
  const useRedis = getRateLimitBackend() === 'redis';
  let redisClient = null;
  if (useRedis) {
    try {
      const { redis } = require('./redis');
      redisClient = redis;
    } catch (_) {}
  }

  try {
    if (limits.ip) {
      await assertBucketUnified({
        db,
        redisClient,
        useRedis,
        bucket: `${category}_ip_${hashKey(ip)}`,
        redisKey: `ratelimit:${category}:${hashKey(`ip:${ip}`)}`,
        windowMs: limits.ip.windowMs,
        maxAttempts: limits.ip.max,
        message,
      });
    }
    if (limits.uid && uid) {
      await assertBucketUnified({
        db,
        redisClient,
        useRedis,
        bucket: `${category}_uid_${hashKey(uid)}`,
        redisKey: `ratelimit:${category}:${hashKey(`uid:${uid}`)}`,
        windowMs: limits.uid.windowMs,
        maxAttempts: limits.uid.max,
        message,
      });
    }
    if (limits.id && identifier) {
      await assertBucketUnified({
        db,
        redisClient,
        useRedis,
        bucket: `${category}_id_${hashKey(String(identifier).toLowerCase())}`,
        redisKey: `ratelimit:${category}:${hashKey(String(identifier).toLowerCase())}`,
        windowMs: limits.id.windowMs,
        maxAttempts: limits.id.max,
        message,
      });
    }
  } catch (err) {
    if (err?.code === 'resource-exhausted') {
      logUnusualTraffic(request, {
        pattern: 'rate_limit',
        detail: `abuse:${category}`,
        identifier: identifier || uid || ip,
      });
    }
    throw err;
  }

  return { ok: true };
}

/**
 * Require a valid App Check token when enforcement is enabled.
 */
function assertAppCheck(request, { enforce = true } = {}) {
  const enabled = enforce
    && String(process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true')
      .trim()
      .toLowerCase() !== 'false';

  if (!enabled) return;
  if (request.app) return;

  logUnusualTraffic(request, {
    pattern: 'app_check_missing',
    detail: 'callable_missing_app_check',
  });
  throw new HttpsError(
    'failed-precondition',
    'App integrity check required. Update the app and try again.',
  );
}

/**
 * Wrap an onCall handler with App Check + category rate limits.
 */
function withAbuseProtection(dbFactory, {
  category = 'api',
  enforceAppCheck = true,
  identifierFromRequest,
  message,
} = {}, handler) {
  return async (request) => {
    assertAppCheck(request, { enforce: enforceAppCheck });
    const db = typeof dbFactory === 'function' ? dbFactory() : dbFactory;
    const identifier = typeof identifierFromRequest === 'function'
      ? identifierFromRequest(request)
      : undefined;
    await enforceAbuseLimit(db, request, category, { identifier, message });
    return handler(request);
  };
}

module.exports = {
  LIMITS,
  hashKey,
  clientIpFromRequest,
  assertBucket,
  assertBucketRedis,
  assertBucketUnified,
  enforceAbuseLimit,
  assertAppCheck,
  withAbuseProtection,
  getRateLimitBackend,
};
