'use strict';

/**
 * Live Redis integration (SEC-08).
 * Uses REDIS_INTEGRATION_URL when set; otherwise ephemeral redis-memory-server (REDIS_INTEGRATION_AUTO=1 default).
 */
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { RedisRateLimiter, assertRateLimitRedisReachable } = require('../src/rate_limit_factory');
const {
  startRedisIntegrationServer,
  stopRedisIntegrationServer,
} = require('./helpers/redis_integration_server');

const autoRedis = String(process.env.REDIS_INTEGRATION_AUTO || '1').trim() !== '0';
let redisUrl = String(process.env.REDIS_INTEGRATION_URL || '').trim();
const describeIntegration = autoRedis ? describe : describe.skip;

describeIntegration('Redis rate limit integration (SEC-08)', () => {
  before(async () => {
    if (!redisUrl) {
      redisUrl = await startRedisIntegrationServer();
    }
  });

  after(async () => {
    if (!process.env.REDIS_INTEGRATION_URL) {
      await stopRedisIntegrationServer();
    }
  });

  it('shared counter enforces limit across two limiter instances', async () => {
    const shared = new RedisRateLimiter({
      redisUrl,
      maxRequests: 2,
      windowMs: 60_000,
      keyPrefix: 'gw:integ:',
    });
    const peer = new RedisRateLimiter({
      redisUrl,
      maxRequests: 2,
      windowMs: 60_000,
      keyPrefix: 'gw:integ:',
    });
    await shared.connect();
    await peer.connect();
    const key = `uid:integration_${Date.now()}`;
    assert.equal(await shared.isAllowed(key), true);
    assert.equal(await peer.isAllowed(key), true);
    assert.equal(await shared.isAllowed(key), false);
    shared.dispose();
    peer.dispose();
  });

  it('assertRateLimitRedisReachable succeeds against live Redis', async () => {
    await assert.doesNotReject(() => assertRateLimitRedisReachable(redisUrl));
  });
});