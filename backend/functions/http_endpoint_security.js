'use strict';

const { getAppCheck } = require('firebase-admin/app-check');
const { HttpsError } = require('firebase-functions/v2/https');

const DEFAULT_AMBULANCE_HTTP_ORIGINS = [
  'https://medibond-45fad.web.app',
  'https://medibond-45fad.firebaseapp.com',
];

function parseCommaSeparatedOrigins(value) {
  return String(value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function resolveAmbulanceHttpAllowedOrigins(env = process.env) {
  const extras = parseCommaSeparatedOrigins(env.AMBULANCE_HTTP_ALLOWED_ORIGINS);
  return [...new Set([...DEFAULT_AMBULANCE_HTTP_ORIGINS, ...extras])];
}

/** Browser requests must come from an allowlisted origin; non-browser calls have no Origin header. */
function isAmbulanceHttpOriginAllowed(origin, allowedOrigins) {
  const normalized = String(origin || '').trim();
  if (!normalized) return true;
  return allowedOrigins.includes(normalized);
}

function applyAmbulanceHttpCorsHeaders(req, res, allowedOrigins) {
  const origin = String(req.headers.origin || '').trim();
  if (origin && allowedOrigins.includes(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
  }
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Firebase-AppCheck',
  );
  res.set('Access-Control-Max-Age', '3600');
}

function handleAmbulanceHttpPreflight(req, res, allowedOrigins) {
  applyAmbulanceHttpCorsHeaders(req, res, allowedOrigins);
  if (req.method !== 'OPTIONS') return false;

  if (!isAmbulanceHttpOriginAllowed(req.headers.origin, allowedOrigins)) {
    res.status(403).send('');
    return true;
  }
  res.status(204).send('');
  return true;
}

function readAppCheckToken(req) {
  return String(
    req.headers['x-firebase-appcheck'] || req.headers['X-Firebase-AppCheck'] || '',
  ).trim();
}

function isAmbulanceHttpAppCheckEnforced(env = process.env) {
  return String(env.ENFORCE_AMBULANCE_HTTP_APP_CHECK || 'false')
    .trim()
    .toLowerCase() === 'true';
}

async function assertAmbulanceHttpAppCheck(req, { enforce, verifyToken } = {}) {
  const enabled = enforce ?? isAmbulanceHttpAppCheckEnforced();
  if (!enabled) return;

  const token = readAppCheckToken(req);
  if (!token) {
    throw new HttpsError(
      'failed-precondition',
      'App integrity check required. Update the app and try again.',
    );
  }

  const verify = verifyToken || ((value) => getAppCheck().verifyToken(value));
  await verify(token);
}

/**
 * Baseline response headers for every onRequest endpoint (JSON APIs and webhooks).
 * cacheable: allow public caching for static, non-personal data (validation rules).
 */
function applyApiSecurityHeaders(res, { cacheable = false } = {}) {
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('X-Frame-Options', 'DENY');
  res.set('Referrer-Policy', 'no-referrer');
  res.set('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
  res.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.set('Cross-Origin-Resource-Policy', 'same-site');
  if (!cacheable) res.set('Cache-Control', 'no-store');
}

/** Wraps an onRequest handler so the security headers are set before any response is written. */
function withApiSecurityHeaders(handler, options = {}) {
  return (req, res) => {
    applyApiSecurityHeaders(res, options);
    return handler(req, res);
  };
}

module.exports = {
  applyApiSecurityHeaders,
  withApiSecurityHeaders,
  DEFAULT_AMBULANCE_HTTP_ORIGINS,
  parseCommaSeparatedOrigins,
  resolveAmbulanceHttpAllowedOrigins,
  isAmbulanceHttpOriginAllowed,
  applyAmbulanceHttpCorsHeaders,
  handleAmbulanceHttpPreflight,
  readAppCheckToken,
  isAmbulanceHttpAppCheckEnforced,
  assertAmbulanceHttpAppCheck,
};
