'use strict';

/**
 * Classify errors that are safe to retry for sync/HTTP side effects (REL-02).
 */
function isTransientSyncError(err) {
  if (!err) return false;
  const code = String(err.code || err.errno || '').toUpperCase();
  const msg = String(err.message || err).toLowerCase();

  const transientCodes = new Set([
    'ECONNRESET',
    'ECONNREFUSED',
    'ETIMEDOUT',
    'EPIPE',
    'ENOTFOUND',
    'EAI_AGAIN',
    '57P01', // admin_shutdown
    '53300', // too_many_connections
    '08006', // connection_failure
  ]);
  if (transientCodes.has(code)) return true;

  if (msg.includes('timeout') || msg.includes('timed out')) return true;
  if (msg.includes('socket hang up') || msg.includes('network')) return true;
  if (msg.includes('econnreset') || msg.includes('etimedout')) return true;

  const status = err.status || err.statusCode;
  if (status === 408 || status === 429 || status === 502 || status === 503 || status === 504) {
    return true;
  }

  return false;
}

function computeBackoffMs(attempt, { baseDelayMs = 200, maxDelayMs = 5000, jitterRatio = 0.25 } = {}) {
  const exp = baseDelayMs * Math.pow(2, Math.max(0, attempt - 1));
  const capped = Math.min(exp, maxDelayMs);
  const jitter = capped * jitterRatio * Math.random();
  return Math.round(capped + jitter);
}

module.exports = {
  isTransientSyncError,
  computeBackoffMs,
};