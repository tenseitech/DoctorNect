'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const { isDoctorPatientSupabasePrimary } = require('./sync_flags');

let _testingSupabaseClient = null;

function setSupabaseClientForTesting(client) {
  _testingSupabaseClient = client;
}

function getSupabaseAdminClient() {
  if (_testingSupabaseClient) return _testingSupabaseClient;
  try {
    const { getDatabaseClient } = require('./src/db/client');
    return getDatabaseClient();
  } catch (_) {
    return null;
  }
}

/**
 * Resolves caller identity (role, profileId, verified, status, etc.)
 * from Supabase `users` when cutover flag is ON, or from Firestore `users/{uid}` when OFF.
 *
 * @param {object} params
 * @param {object} [params.db] Firestore instance (used when cutover is OFF)
 * @param {string} params.uid Caller's Firebase UID / Auth ID
 * @param {object} [params.supabaseClient] Optional Supabase client override
 * @param {boolean} [params.forceSupabase] Force Supabase query regardless of flag
 * @returns {Promise<object>} Resolved user record
 */
async function resolveCallerIdentity({ db, uid, supabaseClient = null, forceSupabase = false } = {}) {
  if (!uid || typeof uid !== 'string') {
    throw new HttpsError('unauthenticated', 'User profile document not found.');
  }

  const useSupabase =
    forceSupabase === true
      ? true
      : forceSupabase === false
        ? false
        : await isDoctorPatientSupabasePrimary();

  if (useSupabase) {
    const sb = supabaseClient || getSupabaseAdminClient();
    if (!sb) {
      throw new HttpsError('internal', 'Supabase admin client not configured.');
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

  if (!db) {
    const { getLegacyFirestoreDb } = require('./legacy_db');
    db = getLegacyFirestoreDb();
    if (!db) {
      throw new HttpsError('failed-precondition', 'Firestore profile lookup is disabled (Postgres-only).');
    }
  }

  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError('unauthenticated', 'User profile document not found.');
  }

  const data = userSnap.data() || {};
  return {
    id: userSnap.id,
    uid: userSnap.id,
    ...data,
  };
}

module.exports = {
  resolveCallerIdentity,
  setSupabaseClientForTesting,
  getSupabaseAdminClient,
};
