'use strict';

const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const crypto = require('crypto');

/**
 * Structured security logging for Cloud Logging + optional Firestore audit trail.
 * Search in Google Cloud Logging with: jsonPayload.securityEvent="true"
 */

const SEVERITY = {
  INFO: 'INFO',
  WARNING: 'WARNING',
  ERROR: 'ERROR',
  CRITICAL: 'CRITICAL',
};

function hashIdentifier(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex').slice(0, 16);
}

function baseFields(request, extra = {}) {
  const ip = (() => {
    try {
      const raw = request?.rawRequest;
      if (!raw) return 'unknown';
      const forwarded = raw.headers?.['x-forwarded-for'];
      if (forwarded) return String(forwarded).split(',')[0].trim();
      return raw.ip || raw.socket?.remoteAddress || 'unknown';
    } catch (_) {
      return 'unknown';
    }
  })();

  return {
    securityEvent: true,
    timestamp: new Date().toISOString(),
    uid: request?.auth?.uid || null,
    emailHash: request?.auth?.token?.email
      ? hashIdentifier(String(request.auth.token.email).toLowerCase())
      : null,
    clientIpHash: hashIdentifier(ip),
    appCheckPresent: Boolean(request?.app?.appId || request?.app),
    ...extra,
  };
}

function emit(severity, category, action, fields) {
  const payload = {
    severity,
    category,
    action,
    ...fields,
  };
  // Cloud Logging structured log (single JSON line).
  const line = JSON.stringify(payload);
  if (severity === SEVERITY.ERROR || severity === SEVERITY.CRITICAL) {
    console.error(line);
  } else if (severity === SEVERITY.WARNING) {
    console.warn(line);
  } else {
    console.info(line);
  }
  return payload;
}

/**
 * Persist high-signal events for dashboards (Admin SDK only; clients denied).
 * Failures are swallowed so logging never breaks the request path.
 */
async function persistSecurityEvent(payload) {
  try {
    const db = getFirestore();
    await db.collection('security_events').add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
    });
  } catch (_) {
    // Non-fatal
  }
}

function logAuthAttempt(request, {
  outcome, // success | failure | blocked
  method, // email_password | mobile_otp | ambulance | super_admin | password_reset
  identifier,
  reason,
} = {}) {
  const payload = emit(
    outcome === 'success' ? SEVERITY.INFO : SEVERITY.WARNING,
    'auth',
    `auth.${outcome}`,
    baseFields(request, {
      method: method || 'unknown',
      identifierHash: hashIdentifier(identifier),
      reason: reason || null,
    }),
  );
  if (outcome !== 'success') {
    // Persist failures/blocks for anomaly review.
    persistSecurityEvent(payload).catch(() => {});
  }
  return payload;
}

function logApiError(request, {
  callable,
  code,
  message,
} = {}) {
  return emit(
    SEVERITY.ERROR,
    'api',
    'api.error',
    baseFields(request, {
      callable: callable || 'unknown',
      errorCode: code || 'internal',
      errorMessage: String(message || '').slice(0, 300),
    }),
  );
}

function logUnusualTraffic(request, {
  pattern, // rate_limit | burst | app_check_missing | forbidden_resource
  detail,
  identifier,
} = {}) {
  const payload = emit(
    SEVERITY.WARNING,
    'traffic',
    'traffic.anomaly',
    baseFields(request, {
      pattern: pattern || 'unknown',
      detail: detail || null,
      identifierHash: hashIdentifier(identifier),
    }),
  );
  persistSecurityEvent(payload).catch(() => {});
  return payload;
}

/**
 * Wraps an onCall handler to log unhandled errors and rate-limit / permission denials.
 */
function withSecurityLogging(callableName, handler) {
  return async (request) => {
    try {
      if (!request.app && String(process.env.ENFORCE_OTP_APP_CHECK || 'true').toLowerCase() !== 'false') {
        // Soft signal only when App Check token is absent on production-enforced callables.
        if (request.data && request.data.__skipAppCheckLog !== true) {
          // Logged selectively by callers that enforce App Check.
        }
      }
      return await handler(request);
    } catch (err) {
      const code = err?.code || 'internal';
      const message = err?.message || String(err);
      logApiError(request, { callable: callableName, code, message });

      if (code === 'resource-exhausted') {
        logUnusualTraffic(request, {
          pattern: 'rate_limit',
          detail: `${callableName} exhausted`,
          identifier: request.data?.identifier || request.data?.email || request.data?.mobile,
        });
      }
      if (code === 'permission-denied' || code === 'unauthenticated') {
        logUnusualTraffic(request, {
          pattern: 'forbidden_resource',
          detail: `${callableName}:${code}`,
        });
      }
      throw err;
    }
  };
}

module.exports = {
  SEVERITY,
  hashIdentifier,
  logAuthAttempt,
  logApiError,
  logUnusualTraffic,
  withSecurityLogging,
  persistSecurityEvent,
};
