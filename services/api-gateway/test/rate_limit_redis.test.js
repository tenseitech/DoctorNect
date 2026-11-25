'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { RedisRateLimiter, assertRateLimitRedisReachable } = require('../src/rate_limit_factory');

function createMockRedis() {
  const store = new Map();
  const expirations = new Map();
  return {
    status: 'ready',
    store,
    async connect() {},
    disconnect() {},
    async ping() {
      return 'PONG';
    },
    async get(key) {
      const val = store.get(key);
      return val === undefined ? null : String(val);
    },
    async incr(key) {
      const next = (store.get(key) || 0) + 1;
      store.set(key, next);
      return next;
    },
    async pexpire(key, ms) {
      expirations.set(key, ms);
      return 1;
    },
  };
}

describe('RedisRateLimiter (SEC-08)', () => {
  it('enforces max requests within a window', async () => {
    const redis = createMockRedis();
    const limiter = new RedisRateLimiter({
      redis,
      windowMs: 60_000,
      maxRequests: 3,
      keyPrefix: 'test:',
    });
    assert.equal(await limiter.isAllowed('ip:1.2.3.4'), true);
    assert.equal(await limiter.isAllowed('ip:1.2.3.4'), true);
    assert.equal(await limiter.isAllowed('ip:1.2.3.4'), true);
    assert.equal(await limiter.isAllowed('ip:1.2.3.4'), false);
    limiter.dispose();
  });

  it('shares counters across logical gateway instances', async () => {
    const redis = createMockRedis();
    const a = new RedisRateLimiter({ redis, maxRequests: 2, windowMs: 60_000, keyPrefix: 'gw:' });
    const b = new RedisRateLimiter({ redis, maxRequests: 2, windowMs: 60_000, keyPrefix: 'gw:' });
    assert.equal(await a.isAllowed('uid:shared'), true);
    assert.equal(await b.isAllowed('uid:shared'), true);
    assert.equal(await a.isAllowed('uid:shared'), false);
    a.dispose();
    b.dispose();
  });

  it('fails closed on Redis command errors during isAllowed', async () => {
    const redis = {
      status: 'ready',
      async connect() {},
      disconnect() {},
      async incr() {
        throw new Error('connection reset');
      },
    };
    const limiter = new RedisRateLimiter({ redis, maxRequests: 5, windowMs: 60_000 });
    assert.equal(await limiter.isAllowed('k'), false);
    limiter.dispose();
  });

  it('ping returns false when Redis client errors', async () => {
    const limiter = new RedisRateLimiter({
      redis: { async ping() { throw new Error('down'); }, disconnect() {} },
      maxRequests: 1,
      windowMs: 60_000,
    });
    assert.equal(await limiter.ping(), false);
    limiter.dispose();
  });

  it('assertRateLimitRedisReachable rejects unreachable endpoints (integration: no live Redis)', async () => {
    await assert.rejects(
      () => assertRateLimitRedisReachable('redis://127.0.0.1:6399'),
      /unreachable|did not respond to PING/,
    );
  }, { timeout: 15_000 });
});