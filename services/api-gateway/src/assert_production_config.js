'use strict';

const config = require('./config');

/** Documented dev/test fallbacks — must not run in production. */
const DEFAULT_POSTGREST_JWT_SECRET = 'doctornect-secure-postgrest-jwt-secret-min32chars';
const DEFAULT_ANON_KEY = 'doctornect-anon-public-key';

function isProductionRuntime(env = process.env) {
  const appEnv = String(env.APP_ENV || '').trim().toLowerCase();
  const nodeEnv = String(env.NODE_ENV || '').trim().toLowerCase();
  return appEnv === 'production' || nodeEnv === 'production';
}

/**
 * Fail closed before listening: no default JWT, anon key, or missing service role in production.
 */
function assertProductionGatewayConfig(options = {}, env = process.env) {
  if (!isProductionRuntime(env)) return;

  const jwtSecret = String(
    options.postgrestJwtSecret ?? env.PGRST_JWT_SECRET ?? config.postgrestJwtSecret ?? '',
  ).trim();
  const anonKey = String(options.anonKey ?? env.ANON_KEY ?? config.anonKey ?? '').trim();
  const serviceRoleKey = String(
    options.serviceRoleKey ?? env.SERVICE_ROLE_KEY ?? config.serviceRoleKey ?? '',
  ).trim();

  const problems = [];
  if (!jwtSecret || jwtSecret === DEFAULT_POSTGREST_JWT_SECRET || jwtSecret.length < 32) {
    problems.push('PGRST_JWT_SECRET (min 32 chars, not default)');
  }
  if (!anonKey || anonKey === DEFAULT_ANON_KEY) {
    problems.push('ANON_KEY (must not use default placeholder)');
  }
  if (!serviceRoleKey || serviceRoleKey.length < 32) {
    problems.push('SERVICE_ROLE_KEY (min 32 chars)');
  }

  if (problems.length) {
    const err = new Error(
      `[Auth Gateway] Production startup blocked — invalid or missing: ${problems.join(', ')}`,
    );
    err.code = 'GATEWAY_PRODUCTION_CONFIG_INVALID';
    throw err;
  }
}

module.exports = {
  assertProductionGatewayConfig,
  DEFAULT_POSTGREST_JWT_SECRET,
  DEFAULT_ANON_KEY,
  isProductionRuntime,
};