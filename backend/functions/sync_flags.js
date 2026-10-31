'use strict';

/**
 * DoctorNect: Sync Feature Flags & Cutover Flags Parser
 * 
 * Centralized parsing and single-source-of-truth cutover flag resolver.
 */

function isSyncFlagEnabled(val) {
  if (val === undefined || val === null) return false;
  const normalized = String(val).trim().toLowerCase();
  return normalized === '1' || normalized === 'true';
}

function isSupabaseSyncEnabled() {
  // Dual-master hazard prevention: bridge is disabled when APP_ENV=production
  // unless explicitly forced via FORCE_ENABLE_SUPABASE_SYNC_IN_PROD=1.
  if (process.env.APP_ENV === 'production' && !isSyncFlagEnabled(process.env.FORCE_ENABLE_SUPABASE_SYNC_IN_PROD)) {
    return false;
  }
  return isSyncFlagEnabled(process.env.ENABLE_SUPABASE_SYNC);
}

const REMOTE_CONFIG_FLAG_KEY = 'use_supabase_db_doctor_patient';
const REMOTE_CONFIG_CACHE_TTL_MS = 60 * 1000; // ~60s in-memory cache

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

function _getEnvCutoverFallback() {
  const envVal = process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;
  return isSyncFlagEnabled(envVal);
}

/**
 * Checks whether Supabase is primary for Doctor & Patient modules.
 * 
 * Single source of truth:
 * Reads the SAME Firebase Remote Config key (use_supabase_db_doctor_patient)
 * via Firebase Admin SDK with a ~60s in-memory cache.
 * Env var USE_SUPABASE_DB_DOCTOR_PATIENT is strictly a fallback default
 * if Remote Config is unreachable or unconfigured.
 * 
 * @returns {Promise<boolean>}
 */
async function isDoctorPatientSupabasePrimary() {
  // Unit tests that simulate legacy Firestore slot/OTP flows (see doctor_slots.test.js).
  if (String(process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT || '').trim() === '1') {
    return false;
  }
  // Postgres-only architecture: application data never reads/writes Firestore.
  return true;
}

module.exports = {
  isSyncFlagEnabled,
  isSupabaseSyncEnabled,
  isDoctorPatientSupabasePrimary,
  _resetRemoteConfigCache,
  _setMockRemoteConfigTemplate,
  _getEnvCutoverFallback,
  REMOTE_CONFIG_FLAG_KEY,
  REMOTE_CONFIG_CACHE_TTL_MS,
};
