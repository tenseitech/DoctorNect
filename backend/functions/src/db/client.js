'use strict';

const { createClient } = require('@supabase/supabase-js');
const { assertDemoUidNotOnRds } = require('../../lib/rds_demo_uid_guard');
const { resolveRequestPlane, requestRedisNamespace, requestObjectStoragePrefix } = require('./request_plane');

/**
 * Every database request (gateway / Supabase PostgREST) gets a hard timeout so an outage fails
 * fast with an error instead of holding the function until its 60 s limit.
 */
const DB_REQUEST_TIMEOUT_MS = 15000;
let dbRequestTimeoutForTesting = null;
function dbRequestTimeoutMs() {
  return dbRequestTimeoutForTesting || DB_REQUEST_TIMEOUT_MS;
}
/** @visibleForTesting */
function setDbRequestTimeoutForTesting(ms) {
  dbRequestTimeoutForTesting = ms || null;
}

function fetchWithTimeout(input, init = {}) {
  const timeout = AbortSignal.timeout(dbRequestTimeoutMs());
  const signal = init && init.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
  return fetch(input, { ...init, signal });
}

let cachedClient = null;
let cachedKey = null;
let cachedDemoClient = null;
let cachedDemoKey = null;

/** Unit tests only: inject an in-memory PostgREST-compatible client for every plane. */
let _testingDatabaseClient = null;
function setDatabaseClientForTesting(client) {
  if (client && String(process.env.APP_ENV || '').trim().toLowerCase() === 'production'
      && (process.env.K_SERVICE || process.env.FUNCTION_TARGET)) {
    throw new Error('[DatabaseClient] test client injection is not allowed in a deployed runtime');
  }
  _testingDatabaseClient = client || null;
}

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
  if (_testingDatabaseClient) return _testingDatabaseClient;
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  const uid = options.firebaseUid || options.uid || null;
  const plane = options.loginLookupPlane
    ? options.loginLookupPlane
    : resolveRequestPlane(uid, { appEnv });

  if (plane === 'rds') {
    assertDemoUidNotOnRds(uid);
  }

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
        // Server-side plane is resolved here; never send x-data-plane (gateway forbids client routing hints).
        'x-client-source': 'medibond-cloud-functions',
      },
      fetch: fetchWithTimeout,
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
  return requestRedisNamespace(request?.auth?.uid || null, { appEnv });
}

function getObjectStoragePrefixForCallable(request) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  return requestObjectStoragePrefix(request?.auth?.uid || null, { appEnv });
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
  setDatabaseClientForTesting,
  dbRequestTimeoutMs,
  fetchWithTimeout,
  setDbRequestTimeoutForTesting,
};