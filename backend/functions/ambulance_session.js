'use strict';

/**
 * Groundwork for ambulance drivers on real accounts (docs/AMBULANCE_REAL_ACCOUNT_SIGNIN.md, H3 b).
 * OFF: nothing reads the switch yet except tests; the app still uses anonymous sessions and
 * completeAmbulanceMobileOtpLogin behaves exactly as before.
 */
const AMBULANCE_REAL_ACCOUNT_SIGNIN = false;

/**
 * @param {{ uid?: string, token?: object } | null | undefined} auth verified request.auth
 * @param {string | null | undefined} ownerUid users.id of the account whose profile_id is the ambulance
 * @returns {'anonymous' | 'owner' | 'other' | 'none'}
 */
function classifyAmbulanceSession(auth, ownerUid) {
  const uid = String((auth && auth.uid) || '').trim();
  if (!uid) return 'none';
  const provider = String((auth.token && auth.token.firebase && auth.token.firebase.sign_in_provider) || '');
  if (provider === 'anonymous') return 'anonymous';
  const owner = String(ownerUid || '').trim();
  return owner && owner === uid ? 'owner' : 'other';
}

module.exports = { AMBULANCE_REAL_ACCOUNT_SIGNIN, classifyAmbulanceSession };
