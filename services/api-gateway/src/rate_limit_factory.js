'use strict';

const { RateLimiter } = require('./security');

let IORedis = null;
try {
  // eslint-disable-next-line global-require, import/no-extraneous-dependencies
  IORedis = require('ioredis');
} catch (_) {
  IORedis = null;
}

/**
 * Redis-backed sliding window counter (fixed window per key via TTL).
 */
class RedisRateLimiter {
  constructor(options = {}) {
    this.windowMs = options.windowMs || 60000;
    this.maxRequests = options.maxRequests || 120;
    this.keyPrefix = options.keyPrefix || 'gw:rl:';
    this.redis = options.redis || null;
    this.ownsClient = false;

    if (!this.redis && options.redisUrl) {
      if (!IORedis) {
        throw new Error('ioredis is required when RATE_LIMIT_REDIS_URL is set.');
      }
      this.redis = new IORedis(options.redisUrl, {
        maxRetriesPerRequest: 2,
        enableReadyCheck: true,
        lazyConnect: true,
        connectTimeout: 3_000,
      });
      this.ownsClient = true;
    }
  }

  async connect() {
    if (this.redis && this.redis.status === 'wait') {
      await this.redis.connect();
    }
  }

  bucketKey(key) {
    const bucket = Math.floor(Date.now() / this.windowMs);
    return `${this.keyPrefix}${key}:${bucket}`;
  }

  async currentCount(key) {
    if (!this.redis) return 0;
    const val = await this.redis.get(this.bucketKey(key));
    return parseInt(val || '0', 10);
  }

  async isAllowed(key) {
    if (!this.redis) return true;
    const redisKey = this.bucketKey(key);
    try {
      const count = await this.redis.incr(redisKey);
      if (count === 1) {
        await this.redis.pexpire(redisKey, this.windowMs);
      }
      return count <= this.maxRequests;
    } catch (_) {
      return false;
    }
  }

  async isBlocked(key) {
    if (!this.redis) return false;
    try {
      return (await this.currentCount(key)) >= this.maxRequests;
    } catch (_) {
      return true;
    }
  }

  async recordFailure(key) {
    return this.isBlocked(key);
  }

  async ping() {
    if (!this.redis) return false;
    try {
      const res = await this.redis.ping();
      return res === 'PONG';
    } catch (_) {
      return false;
    }
  }

  reset() {
    /* Redis counters expire by window; in-memory test reset is a no-op. */
  }

  dispose() {
    if (this.ownsClient && this.redis) {
      this.redis.disconnect();
    }
  }
}

/**
 * Boot-time Redis reachability probe (does not log URL or credentials).
 */
async function assertRateLimitRedisReachable(redisUrl) {
  const limiter = new RedisRateLimiter({
    redisUrl,
    maxRequests: 1,
    windowMs: 60_000,
    keyPrefix: 'gw:boot:',
  });
  try {
    await limiter.connect();
    const ok = await limiter.ping();
    if (!ok) {
      throw new Error('Production gateway: RATE_LIMIT_REDIS_URL did not respond to PING.');
    }
  } catch (err) {
    const msg = String(err?.message || err || '');
  if (msg.includes('did not respond to PING')) {
      throw err;
    }
    throw new Error('Production gateway: RATE_LIMIT_REDIS_URL is unreachable.');
  } finally {
    limiter.dispose();
  }
}

function createRateLimiter(options = {}) {
  const redisUrl = String(
    options.redisUrl || process.env.RATE_LIMIT_REDIS_URL || process.env.REDIS_URL || '',
  ).trim();

  if (redisUrl) {
    return new RedisRateLimiter({ ...options, redisUrl });
  }

  return new RateLimiter(options);
}

module.exports = {
  createRateLimiter,
  RedisRateLimiter,
  assertRateLimitRedisReachable,
};