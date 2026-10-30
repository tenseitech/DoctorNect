'use strict';

const crypto = require('node:crypto');
const config = require('./config');

function base64UrlEncode(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(input, 'utf8');
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Builds the exact PostgREST claims payload.
 *
 * @param {Object} params
 * @param {'authenticated'|'service_role'|'anon'} params.role
 * @param {string} [params.sub]
 * @param {string} [params.appRole]
 * @param {boolean} [params.verified]
 * @param {string} [params.jwtAud]
 * @returns {Object} JSON-serializable claims payload
 */
function buildPostgrestPayload({
  role,
  sub = null,
  appRole = null,
  verified = false,
  phoneNumber = null,
  jwtAud = config.postgrestJwtAud,
}) {
  if (!['authenticated', 'service_role', 'anon'].includes(role)) {
    throw new Error(`Invalid role for PostgREST token: "${role}".`);
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    role,
    iss: 'doctornect-gateway',
    aud: jwtAud,
    iat: nowSec,
    exp: nowSec + 60, // Strictly 60-second lifetime
    jti: crypto.randomUUID(),
  };

  if (role === 'authenticated') {
    if (!sub) {
      throw new Error('Authenticated PostgREST token requires a valid "sub".');
    }
    payload.sub = sub;
    if (appRole) {
      payload.app_role = appRole;
      payload.user_role = appRole;
    }
    payload.verified = Boolean(verified);
    if (phoneNumber) {
      payload.phone_number = phoneNumber;
    }
  } else if (role === 'service_role') {
    payload.sub = 'service_role_internal';
    payload.app_role = 'admin';
    payload.user_role = 'admin';
    payload.verified = true;
  } else if (role === 'anon') {
    payload.sub = 'anon';
    payload.app_role = 'anon';
    payload.user_role = 'anon';
    payload.verified = false;
  }

  return payload;
}

/**
 * Mints a short-lived (60s) HS256 JWT for PostgREST consumption.
 *
 * @param {Object} params
 * @param {'authenticated'|'service_role'|'anon'} params.role
 * @param {string} [params.sub]
 * @param {string} [params.appRole]
 * @param {boolean} [params.verified]
 * @param {string} [params.jwtSecret]
 * @param {string} [params.jwtAud]
 * @returns {string} Compact HS256 JWT
 */
function mintPostgrestJwt({
  role,
  sub = null,
  appRole = null,
  verified = false,
  phoneNumber = null,
  jwtSecret = config.postgrestJwtSecret,
  jwtAud = config.postgrestJwtAud,
}) {
  const payload = buildPostgrestPayload({
    role,
    sub,
    appRole,
    verified,
    phoneNumber,
    jwtAud,
  });

  const header = {
    alg: 'HS256',
    typ: 'JWT',
  };

  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${headerB64}.${payloadB64}`;

  const signature = crypto
    .createHmac('sha256', jwtSecret)
    .update(signatureInput)
    .digest();

  const signatureB64 = base64UrlEncode(signature);
  return `${signatureInput}.${signatureB64}`;
}

module.exports = {
  buildPostgrestPayload,
  mintPostgrestJwt,
  base64UrlEncode,
};
