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

/**
 * Enforce category limits for IP (+ uid when authenticated).
 * @param {'api'|'login'|'signup'|'ai'|'scrape'|'payment'} category
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

  try {
    if (limits.ip) {
      await assertBucket(db, {
        bucket: `${category}_ip_${hashKey(ip)}`,
        windowMs: limits.ip.windowMs,
        maxAttempts: limits.ip.max,
        message,
      });
    }
    if (limits.uid && uid) {
      await assertBucket(db, {
        bucket: `${category}_uid_${hashKey(uid)}`,
        windowMs: limits.uid.windowMs,
        maxAttempts: limits.uid.max,
        message,
      });
    }
    if (limits.id && identifier) {
      await assertBucket(db, {
        bucket: `${category}_id_${hashKey(String(identifier).toLowerCase())}`,
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
  enforceAbuseLimit,
  assertAppCheck,
  withAbuseProtection,
};
