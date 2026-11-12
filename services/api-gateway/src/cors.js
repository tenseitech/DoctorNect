'use strict';

function parseAllowedOrigins(raw) {
  return String(raw || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * @param {import('http').IncomingMessage} req
 * @param {string[]} allowedOrigins
 * @returns {string|null} Value for Access-Control-Allow-Origin or null to omit
 */
function resolveCorsOrigin(req, allowedOrigins) {
  if (!allowedOrigins.length) {
    return null;
  }
  const origin = req.headers.origin;
  if (!origin || typeof origin !== 'string') {
    return allowedOrigins.length === 1 ? allowedOrigins[0] : null;
  }
  if (allowedOrigins.includes(origin)) {
    return origin;
  }
  return null;
}

module.exports = {
  parseAllowedOrigins,
  resolveCorsOrigin,
};
