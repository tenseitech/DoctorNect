'use strict';

/**
 * Verified-OTP session (Redis) is single-use: an atomic GET+DEL means N concurrent completions
 * consume it exactly once; replays and malformed ids are rejected.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { consumeOtpVerificationSessionAtomically, otpSessionRedisKey } = require('../registration_otp');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');

let redis;
test.beforeEach(() => {
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
});

function seedSession(sessionId, overrides = {}) {
  const session = {
    role: 'patient',
    mobileDigits: '9876543210',
    mobileVerified: true,
    expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    consumed: false,
    ...overrides,
  };
  return redis.set(otpSessionRedisKey(sessionId), JSON.stringify(session), 'EX', 900);
}

const newId = () => crypto.randomBytes(16).toString('hex');

test('10 concurrent session completions consume the session exactly once', async () => {
  const sessionId = newId();
  await seedSession(sessionId);
  const results = await Promise.allSettled(
    Array.from({ length: 10 }, () => consumeOtpVerificationSessionAtomically(null, sessionId, {
      assertSession: (session) => {
        if (session.mobileVerified !== true) throw new Error('unexpected session state');
      },
    })),
  );
  const successes = results.filter((r) => r.status === 'fulfilled');
  const failures = results.filter((r) => r.status === 'rejected');
  assert.equal(successes.length, 1);
  assert.equal(failures.length, 9);
  assert.ok(failures.every((r) => r.reason?.code === 'failed-precondition'));
  assert.equal(await redis.get(otpSessionRedisKey(sessionId)), null, 'session key deleted (env-prefixed key)');
});

test('rejects replay after a session has already been consumed', async () => {
  const sessionId = newId();
  await seedSession(sessionId);
  await consumeOtpVerificationSessionAtomically(null, sessionId);
  await assert.rejects(() => consumeOtpVerificationSessionAtomically(null, sessionId), (err) => err.code === 'failed-precondition');
});

test('rejects sessions flagged consumed, expired sessions and malformed ids', async () => {
  const used = newId();
  await seedSession(used, { consumed: true });
  await assert.rejects(() => consumeOtpVerificationSessionAtomically(null, used), (err) => err.code === 'failed-precondition');

  const expired = newId();
  await seedSession(expired, { expiresAt: new Date(Date.now() - 1000).toISOString() });
  await assert.rejects(() => consumeOtpVerificationSessionAtomically(null, expired), (err) => err.code === 'deadline-exceeded');

  for (const bad of ['session-replay-race', '../x', '']) {
    await assert.rejects(() => consumeOtpVerificationSessionAtomically(null, bad), (err) => err.code === 'failed-precondition');
  }
});

test('Redis down -> fails closed', async () => {
  setRedisClientForTesting({ eval: async () => { throw new Error('down'); }, on() { return this; } });
  await assert.rejects(() => consumeOtpVerificationSessionAtomically(null, newId()), (err) => err.code === 'unavailable');
});
