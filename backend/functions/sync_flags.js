'use strict';

/**
 * DoctorNect: Sync Feature Flags Parser
 * 
 * Centralized, strict boolean parsing for sync enablement flags.
 * Accepts ONLY '1' and 'true' (case-insensitive, trimmed).
 * All other values (including unset, empty, '0', 'false', 'off', 'on') default to false (dormant).
 * 
 * @param {string|undefined|null} val - Environment variable value
 * @returns {boolean} - true if strictly '1' or 'true', false otherwise
 */
function isSyncFlagEnabled(val) {
  if (val === undefined || val === null) return false;
  const normalized = String(val).trim().toLowerCase();
  return normalized === '1' || normalized === 'true';
}

function isSupabaseSyncEnabled() {
  return isSyncFlagEnabled(process.env.ENABLE_SUPABASE_SYNC);
}

module.exports = {
  isSyncFlagEnabled,
  isSupabaseSyncEnabled,
};
