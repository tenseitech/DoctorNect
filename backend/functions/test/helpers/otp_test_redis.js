'use strict';

const { setRedisClientForTesting } = require('../../redis');
const { hashOtp, otpRedisKey } = require('../../registration_otp');

function createOtpRedisStore() {
  const store = new Map();
  const redis = {
    store,
    clearStore() {
      store.clear();
    },
    async get(key) {
      const item = store.get(key);
      if (!item) return null;
      if (item.expiresAt != null && Date.now() > item.expiresAt) {
        store.delete(key);
        return null;
      }
      return item.val;
    },
    async set(key, val, mode, ttlSec) {
      store.set(key, {
        val: String(val),
        expiresAt: mode === 'EX' && ttlSec ? Date.now() + ttlSec * 1000 : null,
      });
      return 'OK';
    },
    async del(key) {
      return store.delete(key) ? 1 : 0;
    },
    async incr(key) {
      const item = store.get(key);
      const next = (item ? Number(item.val) : 0) + 1;
      store.set(key, { val: String(next), expiresAt: item?.expiresAt || null });
      return next;
    },
    async pexpire() {
      return 1;
    },
    async eval(_script, _numKeys, key, windowMsArg) {
      const windowMs = Number(windowMsArg) || 60000;
      let entry = store.get(key);
      if (!entry || (entry.expireAt && Date.now() > entry.expireAt)) {
        entry = { val: '0', expireAt: Date.now() + windowMs };
      }
      const next = (Number(entry.val) || 0) + 1;
      entry.val = String(next);
      entry.expireAt = Date.now() + windowMs;
      store.set(key, entry);
      return next;
    },
  };
  return redis;
}

function seedOtpChallenge(redis, {
  otpCode = '654321',
  role = 'patient',
  mobileDigits = '9876543210',
  useLegacyHash = false,
  sentAt = Date.now(),
  expiresAt = Date.now() + 10 * 60 * 1000,
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
  if (keyRole) redis.store.set(keyRole, { val: raw });
  if (keyNull) redis.store.set(keyNull, { val: raw });
  return payload;
}

function enableOtpRedisTestEnv({ authKey = 'otp_unit_test_msg91_key' } = {}) {
  process.env.OTP_REDIS_MIRROR = 'on';
  process.env.MSG91_AUTH_KEY = authKey;
  delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  try {
    const { _resetRemoteConfigCache } = require('../../sync_flags');
    _resetRemoteConfigCache();
  } catch (_) {}
  const redis = createOtpRedisStore();
  setRedisClientForTesting(redis);
  return redis;
}

function disableOtpRedisTestEnv() {
  setRedisClientForTesting(null);
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