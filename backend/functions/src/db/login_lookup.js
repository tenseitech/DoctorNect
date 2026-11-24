'use strict';

const { isReviewerPhone, isAnyReviewerPhone, normalizeRole } = require('../../reviewer_otp_config');
const { getDatabaseClient } = require('./client');
const { assertDemoUidNotOnRds } = require('../../../../scripts/lib/rds_demo_uid_guard');

/**
 * Phone-based login lookup plane (production):
 * - Reviewer / Play Store phones → staging Supabase public.users
 * - All others → RDS via PROD_GATEWAY_URL
 */
function resolveLoginLookupPlane(digits, role) {
  const appEnv = String(process.env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') {
    return 'staging';
  }
  const normalizedRole = role ? normalizeRole(role) : null;
  if (normalizedRole && isReviewerPhone(digits, normalizedRole)) {
    return 'supabase';
  }
  if (!normalizedRole && isAnyReviewerPhone(digits)) {
    return 'supabase';
  }
  return 'rds';
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