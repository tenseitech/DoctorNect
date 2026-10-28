'use strict';

const crypto = require('node:crypto');

/**
 * Constant-time string comparison to defend against timing attacks.
 */
function secureCompare(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Deterministic hash of UID to protect PHI/PII in log streams.
 */
function hashUid(uid) {
  if (!uid || typeof uid !== 'string') return null;
  return crypto.createHash('sha256').update(uid).digest('hex').slice(0, 16);
}

/**
 * Sliding window in-memory rate limiter.
 */
class RateLimiter {
  constructor(options = {}) {
    this.windowMs = options.windowMs || 60000;
    this.maxRequests = options.maxRequests || 120;
    this.requests = new Map(); // key -> [timestamps]

    // Periodic cleanup of expired buckets every 60s
    this.cleanupTimer = setInterval(() => this.cleanup(), 60000);
    if (this.cleanupTimer.unref) {
      this.cleanupTimer.unref();
    }
  }

  isAllowed(key) {
    const now = Date.now();
    const windowStart = now - this.windowMs;
    let timestamps = this.requests.get(key) || [];

    // Filter out timestamps outside window
    timestamps = timestamps.filter((t) => t > windowStart);

    if (timestamps.length >= this.maxRequests) {
      this.requests.set(key, timestamps);
      return false;
    }

    timestamps.push(now);
    this.requests.set(key, timestamps);
    return true;
  }

  isBlocked(key) {
    const now = Date.now();
    const windowStart = now - this.windowMs;
    let timestamps = this.requests.get(key) || [];
    timestamps = timestamps.filter((t) => t > windowStart);
    this.requests.set(key, timestamps);
    return timestamps.length >= this.maxRequests;
  }

  recordFailure(key) {
    const now = Date.now();
    const windowStart = now - this.windowMs;
    let timestamps = this.requests.get(key) || [];
    timestamps = timestamps.filter((t) => t > windowStart);
    timestamps.push(now);
    this.requests.set(key, timestamps);
    return timestamps.length >= this.maxRequests;
  }

  cleanup() {
    const now = Date.now();
    const windowStart = now - this.windowMs;
    for (const [key, timestamps] of this.requests.entries()) {
      const active = timestamps.filter((t) => t > windowStart);
      if (active.length === 0) {
        this.requests.delete(key);
      } else {
        this.requests.set(key, active);
      }
    }
  }

  reset() {
    this.requests.clear();
  }

  dispose() {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
    }
  }
}

/**
 * Emits redacted structured audit log entry to stdout.
 * NEVER logs tokens, full query strings, or PHI.
 */
function emitAuditLog({
  method,
  path,
  status,
  latencyMs,
  uidHash = null,
  role = 'anon',
  ip = null,
}) {
  const cleanPath = (path || '/').split('?')[0];
  const logEntry = {
    timestamp: new Date().toISOString(),
    event: 'api_request',
    method: method || 'GET',
    path: cleanPath,
    status: status || 200,
    latency_ms: Math.round(latencyMs * 10) / 10,
    role: role || 'anon',
    uid_hash: uidHash,
    ip: ip ? ip.replace(/^.*:/, '') : null,
  };
  process.stdout.write(JSON.stringify(logEntry) + '\n');
}

module.exports = {
  secureCompare,
  hashUid,
  RateLimiter,
  emitAuditLog,
};
