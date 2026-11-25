'use strict';

/**
 * Resolve the client IP behind a reverse proxy / load balancer.
 * Uses the rightmost X-Forwarded-For hop as the trusted client address
 * (ALB/appends the connecting client; leftmost values may be spoofed).
 */

function normalizeIp(ip) {
  const raw = String(ip || '').trim();
  if (!raw) return 'unknown';
  if (raw.startsWith('::ffff:')) return raw.slice(7);
  return raw;
}

/**
 * @param {import('http').IncomingMessage} req
 * @param {{ trustProxy?: boolean }} [options]
 */
function resolveClientIpFromRequest(req, options = {}) {
  const trustProxy = options.trustProxy !== false;
  if (!req) return 'unknown';

  const xff = req.headers['x-forwarded-for'] || req.headers['X-Forwarded-For'];
  if (trustProxy && typeof xff === 'string' && xff.trim()) {
    const hops = xff.split(',').map((h) => h.trim()).filter(Boolean);
    if (hops.length > 0) {
      return normalizeIp(hops[hops.length - 1]);
    }
  }

  const direct =
    (req.socket && req.socket.remoteAddress) ||
    (req.connection && req.connection.remoteAddress) ||
    req.ip;
  return normalizeIp(direct);
}

module.exports = {
  resolveClientIpFromRequest,
  normalizeIp,
};