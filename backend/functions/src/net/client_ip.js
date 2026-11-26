'use strict';

/**
 * Client IP extraction behind N trusted reverse proxies.
 *
 * Each trusted proxy APPENDS the address it received the connection from to X-Forwarded-For,
 * so with N trusted hops the real client is the N-th entry from the RIGHT. Everything to the
 * left of that is client-supplied and must never be trusted (it can be spoofed to dodge
 * per-IP rate limits).
 *
 * TRUSTED_PROXY_HOPS (default 1):
 *   - Cloud Functions gen2 / Cloud Run callables (Google Front End appends the client): 1
 *   - Firebase Hosting rewrite -> function (Hosting CDN + GFE): 2
 *   - API gateway on ECS behind the AWS ALB: 1 (set on the gateway task)
 */
function trustedProxyHops(env = process.env) {
  const n = Number.parseInt(String(env.TRUSTED_PROXY_HOPS || '1').trim(), 10);
  return Number.isFinite(n) && n >= 1 && n <= 10 ? n : 1;
}

function isPlausibleIp(value) {
  const v = String(value || '').trim();
  if (!v || v.length > 45) return false;
  return /^[0-9a-fA-F:.]+$/.test(v);
}

/**
 * @param {string|string[]|undefined} xffHeader raw X-Forwarded-For header value
 * @param {string|undefined} socketAddress fallback peer address
 * @param {number} hops number of trusted proxies in front of this service
 */
function clientIpFromForwardedFor(xffHeader, socketAddress, hops = trustedProxyHops()) {
  const raw = Array.isArray(xffHeader) ? xffHeader.join(',') : xffHeader;
  if (typeof raw === 'string' && raw.trim()) {
    const parts = raw.split(',').map((h) => h.trim()).filter(Boolean);
    if (parts.length) {
      // Fewer entries than trusted hops: use the leftmost entry a trusted proxy wrote.
      const idx = Math.max(0, parts.length - hops);
      const candidate = parts[idx];
      if (isPlausibleIp(candidate)) return candidate;
    }
  }
  return socketAddress || 'unknown';
}

function clientIpFromRawRequest(raw, env = process.env) {
  if (!raw) return 'unknown';
  return clientIpFromForwardedFor(
    raw.headers?.['x-forwarded-for'],
    raw.ip || raw.socket?.remoteAddress,
    trustedProxyHops(env),
  );
}

module.exports = {
  trustedProxyHops,
  clientIpFromForwardedFor,
  clientIpFromRawRequest,
};
