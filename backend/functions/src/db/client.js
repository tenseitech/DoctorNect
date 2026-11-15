'use strict';

const { createClient } = require('@supabase/supabase-js');
const {
  resolveDataPlane,
  redisKeyNamespace,
  objectStoragePrefix,
} = require('../../../../scripts/lib/demo_routing');

let cachedClient = null;
let cachedKey = null;
let cachedDemoClient = null;
let cachedDemoKey = null;

/**
 * Returns a configured database client (Supabase-compatible) based on APP_ENV and optional Firebase UID.
 * - Staging: Supabase staging only.
 * - Production + demo UID (allowlist): Supabase staging plane (server credentials).
 * - Production + real / unknown UID: PROD_GATEWAY_URL (RDS PostgREST).
 *
 * @param {Object} [options]
 * @param {boolean} [options.forceNew=false]
 * @param {string} [options.firebaseUid] Authenticated user for per-request routing (production).
 * @returns {import('@supabase/supabase-js').SupabaseClient}
 */
function getDatabaseClient(options = {}) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  const uid = options.firebaseUid || options.uid || null;
  const plane = resolveDataPlane({ appEnv, firebaseUid: uid });

  let url;
  let serviceKey;
  if (plane === 'staging' || plane === 'supabase') {
    url = process.env.DEMO_SUPABASE_URL
      || process.env.STAGING_SUPABASE_URL
      || process.env.SUPABASE_URL
      || '';
    serviceKey = process.env.DEMO_SUPABASE_SERVICE_ROLE_KEY
      || process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY
      || process.env.SUPABASE_SERVICE_ROLE_KEY
      || '';
  } else {
    url = process.env.PROD_GATEWAY_URL || '';
    serviceKey = process.env.PROD_GATEWAY_SERVICE_KEY || '';
  }

  if (!url || !serviceKey) {
    const missing = [];
    if (!url) {
      missing.push(
        plane === 'rds' ? 'PROD_GATEWAY_URL' : 'STAGING_SUPABASE_URL / DEMO_SUPABASE_URL',
      );
    }
    if (!serviceKey) {
      missing.push(
        plane === 'rds' ? 'PROD_GATEWAY_SERVICE_KEY' : 'STAGING_SUPABASE_SERVICE_ROLE_KEY',
      );
    }
    throw new Error(
      `[DatabaseClient] Missing credentials for APP_ENV="${appEnv}" plane="${plane}": ${missing.join(', ')}`,
    );
  }

  const cacheLookupKey = `${appEnv}::${plane}::${url}`;
  if (!options.forceNew) {
    if (plane === 'supabase' && cachedDemoClient && cachedDemoKey === cacheLookupKey) {
      return cachedDemoClient;
    }
    if (plane !== 'supabase' && cachedClient && cachedKey === cacheLookupKey) {
      return cachedClient;
    }
  }

  const client = createClient(url, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      headers: {
        'x-app-env': appEnv,
        'x-data-plane': plane,
        'x-client-source': 'medibond-cloud-functions',
      },
    },
  });

  if (!options.forceNew) {
    if (plane === 'supabase') {
      cachedDemoClient = client;
      cachedDemoKey = cacheLookupKey;
    } else {
      cachedClient = client;
      cachedKey = cacheLookupKey;
    }
  }

  return client;
}

function getDatabaseClientForCallable(request, options = {}) {
  const uid = request?.auth?.uid || null;
  return getDatabaseClient({ ...options, firebaseUid: uid });
}

function getRedisNamespaceForCallable(request) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  return redisKeyNamespace({ appEnv, firebaseUid: request?.auth?.uid || null });
}

function getObjectStoragePrefixForCallable(request) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  return objectStoragePrefix({ appEnv, firebaseUid: request?.auth?.uid || null });
}

function resetDatabaseClientForTesting() {
  cachedClient = null;
  cachedKey = null;
  cachedDemoClient = null;
  cachedDemoKey = null;
}

module.exports = {
  getDatabaseClient,
  getDatabaseClientForCallable,
  getRedisNamespaceForCallable,
  getObjectStoragePrefixForCallable,
  resetDatabaseClientForTesting,
};