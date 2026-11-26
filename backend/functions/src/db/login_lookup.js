'use strict';

const { isDemoMobile } = require('../../reviewer_otp_config');
const { getDatabaseClient } = require('./client');
const { assertDemoUidNotOnRds } = require('../../lib/rds_demo_uid_guard');

/**
 * Phone-based login lookup plane (production), decided only by the server-side demo
 * allowlist (lib/demo_accounts.js):
 * - the five demo numbers -> staging Supabase public.users ('supabase' plane), always,
 *   even when the demo OTP bypass is switched off (demo users never touch RDS)
 * - every other number -> RDS via PROD_GATEWAY_URL
 * The role argument is accepted for backward compatibility and ignored: a client-chosen
 * role can never move a lookup to another database.
 */
function resolveLoginLookupPlane(digits, _role) {
  const appEnv = String(process.env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') {
    return 'staging';
  }
  return isDemoMobile(digits) ? 'supabase' : 'rds';
}

function getLoginLookupClient(digits, role) {
  const plane = resolveLoginLookupPlane(digits, role);
  return getDatabaseClient({ loginLookupPlane: plane });
}

async function queryUserByMobile(client, digits, options = {}) {
  const plane = options.plane || 'rds';
  const candidates = [digits, `+91${digits}`, `91${digits}`, `0${digits}`];
  const { data, error } = await client
    .from('users')
    .select('id, role, mobile, profile_id')
    .in('mobile', candidates)
    .limit(1);
  if (error) {
    const err = new Error(`[LoginLookup] Postgres query failed: ${error.message}`);
    err.code = 'login_lookup_failed';
    throw err;
  }
  if (!data || !data[0]) {
    return null;
  }
  const row = data[0];
  if (plane === 'rds') {
    assertDemoUidNotOnRds(row.id);
  }
  return row;
}

module.exports = {
  resolveLoginLookupPlane,
  getLoginLookupClient,
  queryUserByMobile,
};
