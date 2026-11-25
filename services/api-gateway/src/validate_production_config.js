'use strict';

const KNOWN_DEFAULT_JWT_SECRET = 'doctornect-secure-postgrest-jwt-secret-min32chars';
const KNOWN_DEFAULT_ANON_KEY = 'doctornect-anon-public-key';

const { assertDemoPrefixRoutingSafeForProduction } = require('../../../scripts/lib/demo_routing');

function isProductionLike(env = process.env) {
  const app = String(env.APP_ENV || '').trim().toLowerCase();
  const node = String(env.NODE_ENV || '').trim().toLowerCase();
  return app === 'production' || node === 'production';
}

function assertGatewayProductionConfig(env = process.env) {
  if (!isProductionLike(env)) return;
  if (String(env.SKIP_GATEWAY_PROD_ASSERT || '').trim().toLowerCase() === 'true') {
    return;
  }

  const jwtSecret = String(env.PGRST_JWT_SECRET || '').trim();
  if (!jwtSecret || jwtSecret === KNOWN_DEFAULT_JWT_SECRET) {
    throw new Error(
      'Production gateway misconfiguration: set a unique PGRST_JWT_SECRET (not the repository default).',
    );
  }

  const anonKey = String(env.ANON_KEY || '').trim();
  if (anonKey && anonKey === KNOWN_DEFAULT_ANON_KEY) {
    throw new Error(
      'Production gateway misconfiguration: set a unique ANON_KEY (not the repository default).',
    );
  }

  const serviceRoleKey = String(env.SERVICE_ROLE_KEY || '').trim();
  if (!serviceRoleKey) {
    throw new Error('Production gateway misconfiguration: SERVICE_ROLE_KEY is required.');
  }

  assertDemoPrefixRoutingSafeForProduction(env);

  if (String(env.FIREBASE_REVOCATION_CHECK || 'true').trim().toLowerCase() === 'false') {
    throw new Error(
      'Production gateway misconfiguration: FIREBASE_REVOCATION_CHECK=false is not permitted.',
    );
  }

  const redisUrl = String(env.RATE_LIMIT_REDIS_URL || env.REDIS_URL || '').trim();
  if (String(env.RATE_LIMIT_ALLOW_IN_MEMORY || '').trim().toLowerCase() === 'true') {
    throw new Error(
      'Production gateway misconfiguration: RATE_LIMIT_ALLOW_IN_MEMORY is not permitted in production.',
    );
  }
  if (!redisUrl) {
    throw new Error(
      'Production gateway misconfiguration: set RATE_LIMIT_REDIS_URL for distributed rate limiting.',
    );
  }
}

module.exports = {
  isProductionLike,
  assertGatewayProductionConfig,
  KNOWN_DEFAULT_JWT_SECRET,
  KNOWN_DEFAULT_ANON_KEY,
};