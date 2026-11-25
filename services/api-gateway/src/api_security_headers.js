'use strict';

/**
 * Baseline browser security headers for JSON API responses.
 */
function buildApiSecurityHeaders(extra = {}) {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'accelerometer=(), camera=(), geolocation=(), gyroscope=(), microphone=()',
    'Cache-Control': 'no-store',
    ...extra,
  };
}

module.exports = {
  buildApiSecurityHeaders,
};