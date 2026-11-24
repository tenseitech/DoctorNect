'use strict';

const { HttpsError } = require('firebase-functions/v2/https');

let _testingSupabaseClient = null;

function setSupabaseClientForTesting(client) {
  _testingSupabaseClient = client;
}

/**
 * Server-side Postgres client (service role). Pass the Firebase UID so production demo
 * accounts route to the staging plane and real users to RDS.
 */
function getSupabaseAdminClient(firebaseUid = null) {
  if (_testingSupabaseClient) return _testingSupabaseClient;
  try {
    const { getDatabaseClient } = require('./src/db/client');
    return getDatabaseClient(firebaseUid ? { firebaseUid } : {});
  } catch (_) {
    return null;
  }
}

/** Firebase UIDs are server-issued; anything else must never reach a PostgREST filter string. */
const SAFE_UID_RE = /^[A-Za-z0-9_\-:.]{1,128}$/;

/**
 * Resolves caller identity (role, profileId, verified, status, …) from Postgres public.users.
 *
 * @param {object} params
 * @param {string} params.uid Caller's Firebase UID (from a verified ID token)
 * @param {object} [params.supabaseClient] Optional client override (tests / pre-routed plane)
 * @returns {Promise<object>} Resolved user record
 */
async function resolveCallerIdentity({ uid, supabaseClient = null } = {}) {
  if (!uid || typeof uid !== 'string' || !SAFE_UID_RE.test(uid)) {
    throw new HttpsError('unauthenticated', 'User profile document not found.');
  }

  const sb = supabaseClient || getSupabaseAdminClient(uid);
  if (!sb) {
    throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
  }

  const { data, error } = await sb
    .from('users')
    .select('*')
    .or(`id.eq.${uid},firebase_uid.eq.${uid}`)
    .maybeSingle();

  if (error || !data) {
    throw new HttpsError('unauthenticated', 'User profile document not found.');
  }

  return {
    id: data.id,
    uid: data.id,
    role: data.role,
    profileId: data.profile_id,
    profile_id: data.profile_id,
    profileCompleted: data.profile_completed,
    profile_completed: data.profile_completed,
    verified: data.verified,
    deactivated: data.deactivated,
    email: data.email,
    phone: data.mobile,
    mobile: data.mobile,
    displayName: data.display_name,
    display_name: data.display_name,
    status: data.status,
    ...data,
  };
}

module.exports = {
  resolveCallerIdentity,
  setSupabaseClientForTesting,
  getSupabaseAdminClient,
};
