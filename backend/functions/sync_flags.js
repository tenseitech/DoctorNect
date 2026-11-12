'use strict';

/**
 * DoctorNect: Sync Feature Flags & Cutover Flags Parser
 */

function isSyncFlagEnabled(val) {
  if (val === undefined || val === null) return false;
  const normalized = String(val).trim().toLowerCase();
  return normalized === '1' || normalized === 'true';
}

function isSupabaseSyncEnabled() {
  if (process.env.APP_ENV === 'production' && !isSyncFlagEnabled(process.env.FORCE_ENABLE_SUPABASE_SYNC_IN_PROD)) {
    return false;
  }
  return isSyncFlagEnabled(process.env.ENABLE_SUPABASE_SYNC);
}

const REMOTE_CONFIG_FLAG_KEY = 'use_supabase_db_doctor_patient';
const REMOTE_CONFIG_CACHE_TTL_MS = 60 * 1000;

let _remoteConfigCache = {
  value: null,
  cachedAt: 0,
};

let _mockRemoteConfigTemplate = null;

function _resetRemoteConfigCache() {
  _remoteConfigCache = {
    value: null,
    cachedAt: 0,
  };
}

function _setMockRemoteConfigTemplate(mockFn) {
  _mockRemoteConfigTemplate = mockFn;
}

/**
 * Supabase is primary for Doctor & Patient modules (Postgres app data).
 * Tests may set __TEST_FORCE_LEGACY_DOCTOR_PATIENT=1 to exercise Firestore-only paths.
 *
 * @returns {Promise<boolean>}
 */
async function isDoctorPatientSupabasePrimary() {
  if (String(process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT || '').trim() === '1') {
    return false;
  }
  return true;
}

module.exports = {
  isSyncFlagEnabled,
  isSupabaseSyncEnabled,
  isDoctorPatientSupabasePrimary,
  _resetRemoteConfigCache,
  _setMockRemoteConfigTemplate,
  REMOTE_CONFIG_FLAG_KEY,
  REMOTE_CONFIG_CACHE_TTL_MS,
};
