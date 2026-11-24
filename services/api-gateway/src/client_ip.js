'use strict';

/**
 * Client IP behind N trusted proxies (same contract as backend/functions/src/net/client_ip.js).
 * The gateway runs on ECS behind the AWS ALB, which appends the client address: TRUSTED_PROXY_HOPS=1.
 * Add one hop per extra trusted layer in front (e.g. CloudFront -> ALB = 2).
 */
function trustedProxyHops(env = process.env) {
  const n = Number.parseInt(String(env.TRUSTED_PROXY_HOPS || '1').trim(), 10);
  return Number.isFinite(n) && n >= 1 && n <= 10 ? n : 1;
}

function clientIpFromForwardedFor(xffHeader, socketAddress, hops = trustedProxyHops()) {
  const raw = Array.isArray(xffHeader) ? xffHeader.join(',') : xffHeader;
  if (typeof raw === 'string' && raw.trim()) {
    const parts = raw.split(',').map((h) => h.trim()).filter(Boolean);
    if (parts.length) {
      const candidate = parts[Math.max(0, parts.length - hops)];
      if (candidate && candidate.length <= 45 && /^[0-9a-fA-F:.]+$/.test(candidate)) return candidate;
    }
  }
  return socketAddress || 'unknown';
}

module.exports = { trustedProxyHops, clientIpFromForwardedFor };
