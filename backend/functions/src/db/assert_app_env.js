'use strict';

/**
 * Fail-fast routing guard: APP_ENV must select the correct database access layer.
 * Staging → Supabase (PostgREST). Production → Auth Gateway (PostgREST over RDS).
 */

function normalizeBaseUrl(url) {
  return String(url || '').trim().replace(/\/+$/, '').toLowerCase();
}

function assertAppEnvDatabaseRouting(options = {}) {
  const appEnv = String(process.env.APP_ENV || 'staging').trim().toLowerCase();
  const isProduction = appEnv === 'production';

  const stagingUrl = normalizeBaseUrl(
    process.env.STAGING_SUPABASE_URL || process.env.SUPABASE_URL || '',
  );
  const prodGateway = normalizeBaseUrl(process.env.PROD_GATEWAY_URL || '');
  const prodServiceKey = String(process.env.PROD_GATEWAY_SERVICE_KEY || '').trim();
  const stagingServiceKey = String(
    process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY ||
      process.env.SUPABASE_SERVICE_ROLE_KEY ||
      '',
  ).trim();

  if (isProduction) {
    const missing = [];
    if (!prodGateway) missing.push('PROD_GATEWAY_URL');
    if (!prodServiceKey) missing.push('PROD_GATEWAY_SERVICE_KEY');
    if (missing.length) {
      const err = new Error(
        `[AppEnv] APP_ENV=production requires ${missing.join(', ')}. ` +
          'Staging Supabase credentials must not be the only DB config in production.',
      );
      err.code = 'failed-precondition';
      throw err;
    }
    if (stagingUrl && prodGateway === stagingUrl) {
      const err = new Error(
        '[AppEnv] PROD_GATEWAY_URL must not equal STAGING_SUPABASE_URL / SUPABASE_URL.',
      );
      err.code = 'failed-precondition';
      throw err;
    }
    if (/\.supabase\.co$/i.test(prodGateway)) {
      const err = new Error(
        '[AppEnv] PROD_GATEWAY_URL points at supabase.co — production must use the RDS Auth Gateway, not Supabase cloud.',
      );
      err.code = 'failed-precondition';
      throw err;
    }
  } else if (options.requireStagingDb !== false) {
    if (!stagingUrl || !stagingServiceKey) {
      const missing = [];
      if (!stagingUrl) missing.push('STAGING_SUPABASE_URL (or SUPABASE_URL)');
      if (!stagingServiceKey) {
        missing.push('STAGING_SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_SERVICE_ROLE_KEY)');
      }
      const err = new Error(
        `[AppEnv] APP_ENV=staging requires ${missing.join(', ')} for Postgres access.`,
      );
      err.code = 'failed-precondition';
      throw err;
    }
  }
}

function assertStagingProductionResourceIsolation() {
  const { assertStagingProductionResourceIsolation: assertResources } = require('../config/app_resources');
  assertResources(process.env);
}

module.exports = {
  assertAppEnvDatabaseRouting,
  assertStagingProductionResourceIsolation,
  normalizeBaseUrl,
};
