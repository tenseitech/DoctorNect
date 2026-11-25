'use strict';

/**
 * Concurrent OTP verification on the Redis-only path (atomic attempt slot + atomic multi-key DEL).
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  consumeOtpChallengeAtomically,
  allowLegacyUnsaltedOtpHash,
  otpRedisKey,
} = require('../registration_otp');
const { enableOtpRedisTestEnv, seedOtpChallenge, disableOtpRedisTestEnv } = require('./helpers/otp_test_redis');

const PHONE = '9876543210';
let redis;
test.beforeEach(() => { redis = enableOtpRedisTestEnv(); });
test.afterEach(() => disableOtpRedisTestEnv());

const verify = (otp, role = 'patient', mobileDigits = PHONE) =>
  consumeOtpChallengeAtomically(null, { otp, mobileDigits, role, isDemoAccount: false });
const hasChallenge = async (role = 'patient') => Boolean(await redis.get(otpRedisKey(role, PHONE)));

test('10 concurrent invalid OTP attempts lock out after 5 and remove the challenge', async () => {
  seedOtpChallenge(redis, { otpCode: '654321' });
  const results = await Promise.allSettled(Array.from({ length: 10 }, () => verify('000000')));
  const code = (c) => results.filter((r) => r.status === 'rejected' && r.reason?.code === c).length;
  assert.equal(code('permission-denied') + code('resource-exhausted') + code('failed-precondition'), 10);
  assert.ok(code('permission-denied') <= 5, 'at most 5 guesses are evaluated');
  assert.ok(code('resource-exhausted') >= 1, 'lockout is reported');
  assert.equal(await hasChallenge(), false, 'challenge deleted on lockout');
});

test('10 concurrent valid OTP attempts consume the challenge exactly once', async () => {
  seedOtpChallenge(redis, { otpCode: '654321' });
  const results = await Promise.allSettled(Array.from({ length: 10 }, () => verify('654321')));
  const ok = results.filter((r) => r.status === 'fulfilled');
  const failed = results.filter((r) => r.status === 'rejected');
  assert.equal(ok.length, 1);
  assert.ok(failed.every((r) => ['failed-precondition', 'resource-exhausted'].includes(r.reason?.code)));
  assert.equal(await hasChallenge(), false);
});

test('legacy unsalted SHA-256 challenge is rejected unless ALLOW_LEGACY_UNSALTED_OTP_HASH is true', async () => {
  const prev = process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
  delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
  try {
    assert.equal(allowLegacyUnsaltedOtpHash(), false);
    seedOtpChallenge(redis, { otpCode: '849201', useLegacyHash: true });
    await assert.rejects(verify('849201'), { code: 'permission-denied' });
    assert.equal(await hasChallenge(), true);
  } finally {
    if (prev === undefined) delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH; else process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = prev;
  }
});

test('in-flight legacy unsalted challenge is accepted when the rollback flag is on', async () => {
  const prev = process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
  process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
  try {
    seedOtpChallenge(redis, { otpCode: '849201', useLegacyHash: true });
    const res = await verify('849201');
    assert.equal(res.consumed, true);
    assert.equal(await hasChallenge(), false);
  } finally {
    if (prev === undefined) delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH; else process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = prev;
  }
});

test('a challenge issued for another role on the same number is not usable', async () => {
  seedOtpChallenge(redis, { otpCode: '445566', role: 'doctor' });
  await assert.rejects(verify('445566', 'patient'), { code: 'failed-precondition' });
  assert.equal(await hasChallenge('doctor'), true, 'doctor challenge untouched');
});

test('HMAC verification binds the code to role and mobile', async () => {
  seedOtpChallenge(redis, { otpCode: '789012' });
  assert.equal((await verify('789012')).consumed, true);

  seedOtpChallenge(redis, { otpCode: '789012' });
  await assert.rejects(verify('789012', 'doctor'), (e) => e.code === 'failed-precondition' || e.code === 'permission-denied');
  await assert.rejects(verify('789012', 'patient', '9876543211'), (e) => e.code === 'failed-precondition');
  assert.equal(await hasChallenge(), true);
});
