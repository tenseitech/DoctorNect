'use strict';

/**
 * OTP send abuse buckets (Redis-only). Login / forgot-password OTPs use the otp_send category,
 * registration uses signup; formats of the same number share one bucket; demo numbers get no bypass.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { LIMITS } = require('../abuse_rate_limit');
const { enforceSendUserRegistrationOtpRateLimit } = require('../index');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');

let redis;
test.beforeEach(() => {
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
});
test.afterEach(() => {
  setRedisClientForTesting(createMemoryRedis());
});

const keysFor = (category) => [...redis.store.keys()].filter((k) => k.includes(`ratelimit:${category}:`));
const count = async (key) => Number(await redis.get(key));

test('LIMITS contains otp_send configuration', () => {
  assert.deepEqual(LIMITS.otp_send, {
    ip: { windowMs: 15 * 60 * 1000, max: 30 },
    id: { windowMs: 15 * 60 * 1000, max: 6 },
  });
});

test('a. login OTP uses otp_send buckets only; number formats share one bucket', async () => {
  const req = (mobile) => ({ data: { otpType: 'login', mobile, role: 'doctor' }, rawRequest: { ip: '203.0.113.1' } });
  await enforceSendUserRegistrationOtpRateLimit(null, req('+919876500001'));
  assert.equal(keysFor('signup').length, 0, 'login OTP must not touch signup buckets');
  const otpKeys = keysFor('otp_send');
  assert.equal(otpKeys.length, 2, 'one ip + one id bucket');

  await enforceSendUserRegistrationOtpRateLimit(null, req('9876500001'));
  await enforceSendUserRegistrationOtpRateLimit(null, req('09876500001'));
  assert.equal(keysFor('otp_send').length, 2, 'all formats of one number share the id bucket');
  for (const k of otpKeys) assert.equal(await count(k), 3);
  assert.equal(keysFor('signup').length, 0);
});

test('b. registration OTP increments signup buckets and blocks after the limit', async () => {
  const req = () => ({ data: { otpType: 'registration', mobile: '+919876500002', role: 'patient' }, rawRequest: { ip: '203.0.113.2' } });
  for (let i = 0; i < 3; i++) await enforceSendUserRegistrationOtpRateLimit(null, req());
  assert.ok(keysFor('signup').length >= 1);
  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(null, req()),
    (err) => err.code === 'resource-exhausted'
      && err.message === 'Too many account creation attempts. Please try again later.',
  );
});

test('c. otp_send blocks the 7th request for one number; forgot_password shares the bucket', async () => {
  const req = (i, otpType = 'login') => ({
    data: { otpType, mobile: '9876500003', role: 'doctor' },
    rawRequest: { ip: `203.0.113.${10 + i}` },
  });
  for (let i = 1; i <= 6; i++) await enforceSendUserRegistrationOtpRateLimit(null, req(i));
  const reject = (err) => err.code === 'resource-exhausted'
    && err.message === 'Too many OTP requests. Please try again in a few minutes.';
  await assert.rejects(() => enforceSendUserRegistrationOtpRateLimit(null, req(7)), reject);
  await assert.rejects(() => enforceSendUserRegistrationOtpRateLimit(null, req(99, 'forgot_password')), reject);
});

test('d. formerly-demo phone gets no bypass', async () => {
  const req = () => ({ data: { otpType: 'registration', mobile: '9999900001', role: 'patient' }, rawRequest: { ip: '198.51.100.99' } });
  for (let i = 0; i < 3; i++) await enforceSendUserRegistrationOtpRateLimit(null, req());
  await assert.rejects(() => enforceSendUserRegistrationOtpRateLimit(null, req()), (err) => err.code === 'resource-exhausted');
});

test('e. Redis unavailable -> fails closed (unavailable), never unlimited', async () => {
  setRedisClientForTesting({
    eval: async () => { throw new Error('ECONNREFUSED'); },
    on() { return this; },
  });
  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(null, { data: { otpType: 'login', mobile: '9876500004' }, rawRequest: { ip: '203.0.113.5' } }),
    (err) => err.code === 'unavailable',
  );
});
