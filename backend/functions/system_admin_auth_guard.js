'use strict';

const { getAuth } = require('firebase-admin/auth');
const { HttpsError } = require('firebase-functions/v2/https');

const SYSTEM_ADMIN_EMAIL = 'admin@doctornect.com';

function isSystemAdminEmail(email) {
  return String(email || '').trim().toLowerCase() === SYSTEM_ADMIN_EMAIL;
}

function isSystemAdminAuthUser(userRecord) {
  if (!userRecord) return false;
  if (isSystemAdminEmail(userRecord.email)) return true;
  const claims = userRecord.customClaims || {};
  return claims.is_system_admin === true || claims.app_role === 'super_admin';
}

/**
 * Blocks disable/delete/email/password mutations on Firebase Auth for the platform admin.
 * Limitation: email change / password reset initiated only in Firebase Console bypasses this.
 */
async function assertFirebaseAuthUserMutable(uid, { action = 'modify' } = {}) {
  const id = String(uid || '').trim();
  if (!id) return;
  let user;
  try {
    user = await getAuth().getUser(id);
  } catch (e) {
    if (e?.code === 'auth/user-not-found') return;
    throw e;
  }
  if (isSystemAdminAuthUser(user)) {
    throw new HttpsError(
      'permission-denied',
      `SYSTEM_ADMIN_PROTECTED: Firebase Auth ${action} blocked for platform admin.`,
    );
  }
}

module.exports = {
  SYSTEM_ADMIN_EMAIL,
  isSystemAdminEmail,
  isSystemAdminAuthUser,
  assertFirebaseAuthUserMutable,
};
