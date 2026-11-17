'use strict';

const { getSupabaseAdminClient } = require('../../caller_identity');

/**
 * Load user row by Firebase uid from Postgres (service_role / gateway admin client).
 */
async function readUserProfileFromPostgres(uid) {
  if (!uid) return null;
  const sb = getSupabaseAdminClient();
  if (!sb) return null;
  const { data, error } = await sb
    .from('users')
    .select('*')
    .or(`id.eq.${uid},firebase_uid.eq.${uid}`)
    .maybeSingle();
  if (error || !data) return null;
  return {
    profileId: data.profile_id,
    role: data.role,
    mobile: data.mobile,
    mobileVerified: data.mobile_verified === true,
    emailVerified: data.email_verified === true,
    profileCompleted: data.profile_completed === true,
    createdAt: data.created_at,
    updatedAt: data.updated_at,
    ...data,
  };
}

module.exports = {
  readUserProfileFromPostgres,
};