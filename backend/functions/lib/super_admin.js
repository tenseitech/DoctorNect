'use strict';

/**
 * Super-admin authorization for non-admin-module callables (promoted ads review, S3 access).
 *
 * A caller is a super admin only when ALL of these hold:
 *   1. the Firebase ID token has email_verified === true,
 *   2. the token email is listed in SUPER_ADMIN_EMAILS (comma-separated, case-insensitive),
 *   3. the token carries the server-set admin custom claim (app_role / user_role = super_admin
 *      or admin; set only by the backend via setCustomUserClaims).
 *
 * There is no hard-coded fallback address: an empty SUPER_ADMIN_EMAILS means nobody is a super
 * admin through these paths. A users-table role alone is never sufficient.
 */

const ADMIN_CLAIM_VALUES = new Set(['super_admin', 'superadmin', 'admin']);

function superAdminEmails(env = process.env) {
  return new Set(
    String(env.SUPER_ADMIN_EMAILS || '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean),
  );
}

function hasAdminClaim(token) {
  if (!token) return false;
  return [token.app_role, token.user_role].some(
    (v) => ADMIN_CLAIM_VALUES.has(String(v || '').trim().toLowerCase()),
  );
}

function isSuperAdmin(auth, _userDoc = null, env = process.env) {
  const token = auth?.token;
  if (!token || token.email_verified !== true) return false;
  const email = String(token.email || '').trim().toLowerCase();
  if (!email || !superAdminEmails(env).has(email)) return false;
  return hasAdminClaim(token);
}

module.exports = { isSuperAdmin, superAdminEmails, hasAdminClaim };
