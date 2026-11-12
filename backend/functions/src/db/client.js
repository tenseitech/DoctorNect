'use strict';

const { createClient } = require('@supabase/supabase-js');

let cachedClient = null;
let cachedKey = null;

/**
 * Returns a configured database client (Supabase-compatible) based on APP_ENV.
 * - Staging: Connects to Supabase using STAGING_SUPABASE_URL and STAGING_SUPABASE_SERVICE_ROLE_KEY.
 * - Production: Connects to AWS Auth Gateway / PostgREST using PROD_GATEWAY_URL and PROD_GATEWAY_SERVICE_KEY.
 *
 * @param {Object} [options]
 * @param {boolean} [options.forceNew=false]
 * @returns {import('@supabase/supabase-js').SupabaseClient}
 */
function getDatabaseClient(options = {}) {
  const appEnv = (process.env.APP_ENV || 'staging').toLowerCase();
  const isProduction = appEnv === 'production';

  const url = isProduction
    ? (process.env.PROD_GATEWAY_URL || '')
    : (process.env.STAGING_SUPABASE_URL || process.env.SUPABASE_URL || '');

  const serviceKey = isProduction
    ? (process.env.PROD_GATEWAY_SERVICE_KEY || '')
    : (process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '');

  if (!url || !serviceKey) {
    const missing = [];
    if (!url) missing.push(isProduction ? 'PROD_GATEWAY_URL' : 'STAGING_SUPABASE_URL');
    if (!serviceKey) missing.push(isProduction ? 'PROD_GATEWAY_SERVICE_KEY' : 'STAGING_SUPABASE_SERVICE_ROLE_KEY');
    throw new Error(`[DatabaseClient] Missing required credentials for APP_ENV="${appEnv}": ${missing.join(', ')}`);
  }

  const cacheLookupKey = `${appEnv}::${url}`;
  if (!options.forceNew && cachedClient && cachedKey === cacheLookupKey) {
    return cachedClient;
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
        'x-client-source': 'medibond-cloud-functions',
      },
    },
  });

  if (!options.forceNew) {
    cachedClient = client;
    cachedKey = cacheLookupKey;
  }

  return client;
}

function resetDatabaseClientForTesting() {
  cachedClient = null;
  cachedKey = null;
}

module.exports = {
  getDatabaseClient,
  resetDatabaseClientForTesting,
};
