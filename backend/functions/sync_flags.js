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
  const envVal =
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT ||
    process.env.CUTOVER_DOCTOR_PATIENT;
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
  const now = Date.now();
  if (
    _remoteConfigCache.value !== null &&
    (now - _remoteConfigCache.cachedAt) < REMOTE_CONFIG_CACHE_TTL_MS
  ) {
    return _remoteConfigCache.value;
  }

  try {
    let template;
    if (typeof _mockRemoteConfigTemplate === 'function') {
      template = await _mockRemoteConfigTemplate();
    } else {
      const admin = require('firebase-admin');
      if (!admin.apps.length) {
        admin.initializeApp();
      }
      const { getRemoteConfig } = require('firebase-admin/remote-config');
      template = await getRemoteConfig().getTemplate();
    }

    const parameter = template?.parameters && template.parameters[REMOTE_CONFIG_FLAG_KEY];
    if (parameter && parameter.defaultValue && typeof parameter.defaultValue.value === 'string') {
      const isPrimary = isSyncFlagEnabled(parameter.defaultValue.value);
      _remoteConfigCache = {
        value: isPrimary,
        cachedAt: now,
      };
      return isPrimary;
    }

    // Parameter missing or lacks defaultValue in template -> fallback to env
    const fallback = _getEnvCutoverFallback();
    _remoteConfigCache = {
      value: fallback,
      cachedAt: now,
    };
    return fallback;
  } catch (err) {
    // Remote Config is unreachable or threw an error -> fallback to env var
    // Do not cache the failure so subsequent calls can retry Remote Config
    return _getEnvCutoverFallback();
  }
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
