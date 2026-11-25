'use strict';

/**
 * Firebase Admin verifyIdToken(idToken, checkRevoked=true) after JWKS signature verification.
 * Production (APP_ENV=production) requires ADC / service account unless FIREBASE_REVOCATION_CHECK=false.
 */

let adminAuth = null;
let initAttempted = false;
let adminAuthOverride = null;

/** @visibleForTesting */
function setAdminAuthForTesting(auth) {
  adminAuthOverride = auth;
  adminAuth = auth;
  initAttempted = true;
}

function resolveAdminAuth() {
  if (adminAuthOverride !== null && adminAuthOverride !== undefined) {
    return adminAuthOverride;
  }
  if (String(process.env.DISABLE_FIREBASE_ADMIN_INIT || '').trim() === '1') {
    initAttempted = true;
    return null;
  }
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
  adminAuthOverride = null;
  initAttempted = false;
}

/** Returns whether Firebase Admin Auth is available (ADC / credentials). Never logs secrets. */
async function probeFirebaseAdminAvailable() {
  const auth = resolveAdminAuth();
  return Boolean(auth);
}

module.exports = {
  assertFirebaseTokenNotRevoked,
  probeFirebaseAdminAvailable,
  resetFirebaseAdminForTesting,
  setAdminAuthForTesting,
};
