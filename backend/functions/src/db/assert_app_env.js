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

function isRedisTlsExplicitlyDisabled(env = process.env) {
  const raw = String(env.REDIS_TLS || '').trim().toLowerCase();
  return raw === 'false' || raw === '0' || raw === 'off' || raw === 'no';
}

function resolveProductionRedisHostString(env = process.env) {
  return String(env.REDIS_HOST_PRODUCTION || env.REDIS_HOST || '').trim();
}

function collectProductionRedisEndpointCandidates(env = process.env) {
  const out = [];
  const push = (v) => {
    const s = String(v || '').trim();
    if (s) out.push(s);
  };
  push(env.REDIS_URL);
  push(env.REDIS_URL_PRODUCTION);
  push(resolveProductionRedisHostString(env));
  if (env.REDIS_HOST && env.REDIS_PORT) {
    push(`${env.REDIS_HOST}:${env.REDIS_PORT}`);
  }
  if (env.REDIS_HOST_PRODUCTION && env.REDIS_PORT) {
    push(`${env.REDIS_HOST_PRODUCTION}:${env.REDIS_PORT}`);
  }
  return out;
}

function assertPlaintextRedisEndpointForbidden(endpoint, envLabel) {
  const s = String(endpoint || '').trim();
  if (!s) return;
  if (/^redis:\/\//i.test(s) && !/^rediss:\/\//i.test(s)) {
    const err = new Error(
      `[AppEnv] APP_ENV=production requires TLS to Redis; plaintext redis:// in ${envLabel} is not allowed.`,
    );
    err.code = 'failed-precondition';
    throw err;
  }
}

function assertRedisClientTlsVerificationEnabled(env = process.env) {
  const { buildRedisOptions } = require('../config/redis');
  const options = buildRedisOptions();
  if (options.tls && options.tls.rejectUnauthorized === false) {
    const err = new Error(
      '[AppEnv] APP_ENV=production Redis TLS must verify the server certificate (rejectUnauthorized must not be false).',
    );
    err.code = 'failed-precondition';
    throw err;
  }
}

/**
 * Production Memorystore must not run with TLS disabled or a plaintext redis:// URL.
 */
function assertProductionRedisTls(env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;

  if (isRedisTlsExplicitlyDisabled(env)) {
    const err = new Error(
      '[AppEnv] APP_ENV=production requires TLS to Redis (REDIS_TLS must not be false).',
    );
    err.code = 'failed-precondition';
    throw err;
  }

  const labels = [
    ['REDIS_URL', env.REDIS_URL],
    ['REDIS_URL_PRODUCTION', env.REDIS_URL_PRODUCTION],
    ['REDIS_HOST / REDIS_HOST_PRODUCTION', resolveProductionRedisHostString(env)],
  ];
  for (const [label, value] of labels) {
    assertPlaintextRedisEndpointForbidden(value, label);
  }
  for (const endpoint of collectProductionRedisEndpointCandidates(env)) {
    assertPlaintextRedisEndpointForbidden(endpoint, 'Redis endpoint configuration');
  }

  assertRedisClientTlsVerificationEnabled(env);
}

function isLegacyUnsaltedOtpHashEnabled(env = process.env) {
  const raw = String(env.ALLOW_LEGACY_UNSALTED_OTP_HASH || '').trim().toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'on' || raw === 'yes';
}

/**
 * Production must not accept plain SHA-256 OTP challenges (HMAC-only).
 */
function assertProductionOtpHmacOnly(env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;

  if (isLegacyUnsaltedOtpHashEnabled(env)) {
    const err = new Error(
      '[AppEnv] APP_ENV=production must not set ALLOW_LEGACY_UNSALTED_OTP_HASH (OTP must use HMAC only).',
    );
    err.code = 'failed-precondition';
    throw err;
  }
}

function isTruthyEnvFlag(value) {
  const raw = String(value || '').trim().toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'on' || raw === 'yes';
}

/**
 * Warn (do not fail) when production relies on MSG91 without OTP HMAC pepper configured.
 */
function warnProductionOtpHmacFallback(env = process.env, logFn = console.warn) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;

  const hmac = String(env.OTP_HMAC_SECRET || '').trim();
  const msg91 = String(env.MSG91_AUTH_KEY || '').trim();
  if (!hmac && msg91) {
    logFn(
      '[AppEnv] WARNING: APP_ENV=production has MSG91_AUTH_KEY but OTP_HMAC_SECRET is unset. '
        + 'Configure OTP_HMAC_SECRET (32+ bytes, Secret Manager) before relying on OTP verification.',
    );
  }
}

/**
 * Hard fail when review / fixed OTP backdoors are enabled in production routing.
 */
function assertProductionReviewOtpDisabled(env = process.env) {
  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') return;

  const violations = [];
  if (isTruthyEnvFlag(env.REVIEWER_OTP_ENABLED)) {
    violations.push('REVIEWER_OTP_ENABLED=true');
  }
  if (String(env.REVIEW_FIXED_OTP || '').trim()) {
    violations.push('REVIEW_FIXED_OTP is set');
  }
  if (violations.length) {
    const err = new Error(
      `[AppEnv] APP_ENV=production must not enable reviewer OTP bypass (${violations.join(', ')}).`,
    );
    err.code = 'failed-precondition';
    throw err;
  }
}

module.exports = {
  assertAppEnvDatabaseRouting,
  assertStagingProductionResourceIsolation,
  assertProductionRedisTls,
  isRedisTlsExplicitlyDisabled,
  resolveProductionRedisHostString,
  collectProductionRedisEndpointCandidates,
  assertPlaintextRedisEndpointForbidden,
  assertRedisClientTlsVerificationEnabled,
  assertProductionOtpHmacOnly,
  warnProductionOtpHmacFallback,
  assertProductionReviewOtpDisabled,
  isTruthyEnvFlag,
  isLegacyUnsaltedOtpHashEnabled,
  normalizeBaseUrl,
};
