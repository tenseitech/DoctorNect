'use strict';

const { isProductionLike } = require('./validate_production_config');
const { probeFirebaseAdminAvailable } = require('./firebase_revocation');
const { assertRateLimitRedisReachable } = require('./rate_limit_factory');

/**
 * Runtime probes after static config validation (production gateway boot only).
 * Fails closed when mandatory checks are unavailable.
 */
async function assertGatewayProductionRuntime(env = process.env) {
  if (!isProductionLike(env)) return;
  if (String(env.SKIP_GATEWAY_PROD_ASSERT || '').trim().toLowerCase() === 'true') {
    return;
  }

  const revocationEnabled =
    String(env.FIREBASE_REVOCATION_CHECK || 'true').trim().toLowerCase() !== 'false';
  if (revocationEnabled) {
    const adminReady = await probeFirebaseAdminAvailable();
    if (!adminReady) {
      throw new Error(
        'Production gateway: Firebase Admin is unavailable; token revocation cannot be enforced.',
      );
    }
  }

  const redisUrl = String(env.RATE_LIMIT_REDIS_URL || env.REDIS_URL || '').trim();
  if (redisUrl) {
    await assertRateLimitRedisReachable(redisUrl);
  }
}

module.exports = {
  assertGatewayProductionRuntime,
};