'use strict';

const { redisKey } = require('./src/config/redis_keys');

/** Keys aligned with main-app / gateway cache conventions (env-prefixed). */
function promotedAdsCacheKeys() {
  return [
    redisKey('cache:promoted_ads:active'),
    redisKey('cache:promoted_ads:all'),
    redisKey('cache:system_config:promoted_ads'),
    redisKey('cache:banner_config'),
  ];
}

/**
 * Best-effort Redis invalidation after banner/config mutations.
 * No-op when OTP Redis mirror is off or client unavailable.
 */
async function invalidatePromotedAdsCache() {
  if (String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() !== 'on') {
    return { invalidated: 0, skipped: 'redis_mirror_off' };
  }
  try {
    const { getRedisClient } = require('./redis');
    const redis = getRedisClient();
    if (!redis || typeof redis.del !== 'function') {
      return { invalidated: 0, skipped: 'no_redis_client' };
    }
    const keys = promotedAdsCacheKeys();
    let count = 0;
    for (const key of keys) {
      try {
        const n = await redis.del(key);
        if (n) count += 1;
      } catch (_) {}
    }
    return { invalidated: count, keys };
  } catch (e) {
    return { invalidated: 0, error: e?.message || String(e) };
  }
}

module.exports = {
  invalidatePromotedAdsCache,
  promotedAdsCacheKeys,
};
