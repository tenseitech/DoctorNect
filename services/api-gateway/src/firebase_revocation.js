'use strict';

/**
 * Firebase Admin verifyIdToken(idToken, checkRevoked=true) after JWKS signature verification.
 * Production (APP_ENV=production) requires ADC / service account unless FIREBASE_REVOCATION_CHECK=false.
 */

let adminAuth = null;
let initAttempted = false;

function resolveAdminAuth() {
  if (initAttempted) {
    return adminAuth;
  }
  initAttempted = true;
  try {
    const { initializeApp, applicationDefault, getApps } = require('firebase-admin/app');
    const { getAuth } = require('firebase-admin/auth');
    if (!getApps().length) {
      initializeApp({
        credential: applicationDefault(),
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
};
