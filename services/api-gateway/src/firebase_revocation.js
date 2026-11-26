'use strict';

/**
 * Firebase Admin verifyIdToken(idToken, checkRevoked=true) after JWKS signature verification.
 * Production (APP_ENV=production) requires ADC / service account unless FIREBASE_REVOCATION_CHECK=false.
 */

let adminAuth = null;
let initAttempted = false;

/**
 * Credential for Firebase Admin. On AWS ECS there are no Google Application Default
 * Credentials, so the task injects a dedicated service-account key from AWS Secrets Manager as
 * FIREBASE_SERVICE_ACCOUNT_JSON (role: Firebase Authentication Viewer only). Elsewhere (local,
 * GCP) Application Default Credentials are used. The JSON is never logged; a malformed value
 * throws a message without its content.
 */
function resolveCredential(env = process.env) {
  const { applicationDefault, cert } = require('firebase-admin/app');
  const raw = String(env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim();
  if (!raw) return applicationDefault();
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON (value not shown).');
  }
  if (parsed.type !== 'service_account' || !parsed.client_email || !parsed.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not a service-account key (value not shown).');
  }
  const project = String(env.FIREBASE_PROJECT_ID || 'medibond-45fad').trim();
  if (parsed.project_id && parsed.project_id !== project) {
    throw new Error(`FIREBASE_SERVICE_ACCOUNT_JSON belongs to another project (expected ${project}).`);
  }
  return cert(parsed);
}

function resolveAdminAuth() {
  if (initAttempted) {
    return adminAuth;
  }
  initAttempted = true;
  try {
    const { initializeApp, getApps } = require('firebase-admin/app');
    const { getAuth } = require('firebase-admin/auth');
    if (!getApps().length) {
      initializeApp({
        credential: resolveCredential(process.env),
        projectId: process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
      });
    }
    adminAuth = getAuth();
  } catch (_) {
    adminAuth = null;
  }
  return adminAuth;
}

/**
 * @param {string} idToken Raw Firebase ID token (same string sent by client)
 * @param {{ required?: boolean }} [options]
 */
async function assertFirebaseTokenNotRevoked(idToken, options = {}) {
  const required = options.required === true;
  const auth = resolveAdminAuth();
  if (!auth) {
    if (required) {
      throw new Error('Firebase Admin unavailable; cannot verify token revocation.');
    }
    return;
  }
  try {
    await auth.verifyIdToken(idToken, true);
  } catch (err) {
    if (err.code === 'auth/id-token-revoked') {
      throw new Error('Token has been revoked.');
    }
    throw new Error(err.message || 'Firebase token revocation check failed.');
  }
}

/** @visibleForTesting */
function resetFirebaseAdminForTesting() {
  adminAuth = null;
  initAttempted = false;
}

module.exports = {
  assertFirebaseTokenNotRevoked,
  resetFirebaseAdminForTesting,
  resolveCredential,
};
