'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const { RateLimiter } = require('../src/security');

describe('RateLimiter memory cap (PERF-12)', () => {
  it('evicts oldest keys when maxTrackedKeys would be exceeded', () => {
    const limiter = new RateLimiter({
      windowMs: 60_000,
      maxRequests: 1000,
      maxTrackedKeys: 3,
    });

    assert.strictEqual(limiter.isAllowed('k1'), true);
    assert.strictEqual(limiter.isAllowed('k2'), true);
    assert.strictEqual(limiter.isAllowed('k3'), true);
    assert.strictEqual(limiter.requests.size, 3);

    assert.strictEqual(limiter.isAllowed('k4'), true);
    assert.ok(limiter.requests.size <= 3);
    assert.ok(!limiter.requests.has('k1'));
  });

  it('handles 10k distinct keys within cap with acceptable overhead', () => {
    const limiter = new RateLimiter({
      windowMs: 60_000,
      maxRequests: 5,
      maxTrackedKeys: 500,
    });
    const start = performance.now();
    for (let i = 0; i < 10_000; i++) {
      limiter.isAllowed(`ip:${i}`);
    }
    const elapsedMs = performance.now() - start;
    assert.ok(limiter.requests.size <= 500);
    assert.ok(elapsedMs < 2000, `expected <2s, got ${elapsedMs.toFixed(1)}ms`);
    limiter.dispose();
  });
});