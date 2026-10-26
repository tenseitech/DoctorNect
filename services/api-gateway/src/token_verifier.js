'use strict';

const crypto = require('node:crypto');
const config = require('./config');
const { defaultJwksClient } = require('./jwks');

function base64UrlDecode(str) {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  return Buffer.from(base64, 'base64').toString('utf8');
}

/**
 * Parses and verifies a Firebase ID token.
 *
 * @param {string} token
 * @param {Object} [options]
 * @param {import('./jwks').JwksClient} [options.jwksClient]
 * @param {string} [options.projectId]
 * @param {number} [options.clockSkewSec]
 * @returns {Promise<Object>} Verified token payload
 */
async function verifyFirebaseIdToken(token, options = {}) {
  if (!token || typeof token !== 'string') {
    throw new Error('Token is missing or not a string.');
  }

  const parts = token.trim().split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed JWT: must contain exactly 3 segments.');
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  // 1. Decode and check header
  let header;
  try {
    header = JSON.parse(base64UrlDecode(headerB64));
  } catch (_) {
    throw new Error('Invalid JWT header: JSON parse error.');
  }

  if (header.alg !== 'RS256') {
    throw new Error(`Invalid token algorithm: expected RS256, got "${header.alg}".`);
  }

  if (!header.kid || typeof header.kid !== 'string') {
    throw new Error('Token header missing "kid".');
  }

  // 2. Decode payload
  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(payloadB64));
  } catch (_) {
    throw new Error('Invalid JWT payload: JSON parse error.');
  }

  const projectId = options.projectId || config.firebaseProjectId;
  const expectedIssuer = `https://securetoken.google.com/${projectId}`;
  const clockSkew = options.clockSkewSec !== undefined ? options.clockSkewSec : 30;
  const nowSec = Math.floor(Date.now() / 1000);

  // 3. Claims verification
  if (payload.iss !== expectedIssuer) {
    throw new Error(`Invalid token issuer: expected "${expectedIssuer}", got "${payload.iss}".`);
  }

  if (payload.aud !== projectId) {
    throw new Error(`Invalid token audience: expected "${projectId}", got "${payload.aud}".`);
  }

  if (!payload.sub || typeof payload.sub !== 'string' || payload.sub.trim() === '') {
    throw new Error('Invalid token subject: "sub" must be a non-empty string.');
  }

  if (typeof payload.exp !== 'number' || payload.exp < (nowSec - clockSkew)) {
    throw new Error('Token has expired.');
  }

  if (typeof payload.iat === 'number' && payload.iat > (nowSec + clockSkew)) {
    throw new Error('Token issued in the future.');
  }

  // 4. Cryptographic signature verification
  const jwks = options.jwksClient || defaultJwksClient;
  const publicKey = await jwks.getSigningKey(header.kid);

  const dataToVerify = Buffer.from(`${headerB64}.${payloadB64}`, 'utf8');
  const signatureBuf = Buffer.from(signatureB64.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

  const isVerified = crypto.verify('RSA-SHA256', dataToVerify, publicKey, signatureBuf);
  if (!isVerified) {
    throw new Error('Token signature verification failed.');
  }

  // 5. Return sanitized verified claims
  return {
    uid: payload.sub,
    email: payload.email || null,
    // Extract verified role strictly from token payload (never trust caller headers)
    appRole: payload.app_role || payload.user_role || payload.role || 'patient',
    verified: Boolean(payload.verified),
    rawPayload: payload,
  };
}

module.exports = {
  verifyFirebaseIdToken,
  base64UrlDecode,
};
