'use strict';

const { setRedisClientForTesting } = require('../../redis');
const { hashOtp, otpRedisKey } = require('../../registration_otp');
const { createMemoryRedis } = require('./memory_redis');

/** Back-compat name: OTP tests share the full in-memory Redis double. */
function createOtpRedisStore() {
  return createMemoryRedis();
}

function seedOtpChallenge(redis, {
  otpCode = '654321',
  role = 'patient',
  mobileDigits = '9876543210',
  useLegacyHash = false,
  sentAt = Date.now(),
  expiresAt = Date.now() + 5 * 60 * 1000,
  extra = {},
} = {}) {
  const { legacyHashOtp } = require('../../registration_otp');
  const payload = {
    role,
    mobileDigits,
    otpHash: useLegacyHash
      ? legacyHashOtp(otpCode)
      : hashOtp(otpCode, { role, digits: mobileDigits, purpose: 'create' }),
    sentAt,
    expiresAt,
    attempts: 0,
    ...extra,
  };
  const raw = JSON.stringify(payload);
  const keyRole = otpRedisKey(role, mobileDigits);
  const keyNull = otpRedisKey(null, mobileDigits);
  if (keyRole) redis.store.set(keyRole, { val: raw, expireAt: null });
  if (keyNull) redis.store.set(keyNull, { val: raw, expireAt: null });
  return payload;
}

function enableOtpRedisTestEnv({ authKey = 'otp_unit_test_msg91_key' } = {}) {
  process.env.OTP_REDIS_MIRROR = 'on';
  process.env.MSG91_AUTH_KEY = authKey;
  const redis = createMemoryRedis();
  setRedisClientForTesting(redis);
  return redis;
}

function disableOtpRedisTestEnv() {
  // Restore a fresh in-memory Redis (never a real connection) for subsequent tests.
  setRedisClientForTesting(createMemoryRedis());
  delete process.env.OTP_REDIS_MIRROR;
  delete process.env.MSG91_AUTH_KEY;
}

const EMPTY_LEGACY_DB = {};

module.exports = {
  createOtpRedisStore,
  seedOtpChallenge,
  enableOtpRedisTestEnv,
  disableOtpRedisTestEnv,
  EMPTY_LEGACY_DB,
};
