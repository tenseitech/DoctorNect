'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const https = require('https');
const { EventEmitter } = require('events');

delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
delete process.env.OTP_TEST_MODE;
delete process.env.OTP_REDIS_MIRROR;
process.env.MSG91_AUTH_KEY = 'unit-test-hmac-key';
process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'unit-test-template';
process.env.MSG91_TEMPLATE_ID = 'unit-test-template';
process.env.MSG91_SENDER_ID = 'DRNECT';

const {
  sendUserRegistrationOtp,
  verifyUserRegistrationOtp,
  hashOtp,
  otpRedisKey,
  setReviewerRedisClientForTesting,
  resetReviewerRateLimitForTesting,
} = require('../registration_otp');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');

function createTestRedisMock() {
  const store = new Map();
  return {
    store,
    async eval(_script, _numKeys, key, windowMsArg) {
      const windowMs = Number(windowMsArg) || 60000;
      let entry = store.get(key);
      if (!entry || (entry.expireAt && Date.now() > entry.expireAt)) {
        entry = { val: 0, expireAt: Date.now() + windowMs };
      }
      entry.val += 1;
      entry.expireAt = Date.now() + windowMs;
      store.set(key, entry);
      return entry.val;
    },
    flushall() {
      store.clear();
    },
  };
}

let origLegacyCutover;
test.beforeEach(() => {
  origLegacyCutover = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
});

test.afterEach(() => {
  delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  if (origLegacyCutover === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacyCutover;
});

function mobileHash(role, digits) {
  return crypto.createHash('sha256').update(`${role}:${digits}`).digest('hex');
}

function createMockFirestore() {
  const docs = new Map();

  function docRef(collection, id) {
    const key = `${collection}/${id}`;
    return {
      id,
      key,
      async get() {
        const data = docs.get(key);
        return {
          exists: data != null,
          data: () => (data == null ? undefined : { ...data }),
        };
      },
      async set(data, { merge } = {}) {
        if (merge && docs.has(key)) docs.set(key, { ...docs.get(key), ...data });
        else docs.set(key, { ...data });
      },
      async delete() {
        docs.delete(key);
      },
    };
  }

  return {
    docs,
    collection(name) {
      return {
        doc(id) {
          return docRef(name, id);
        },
        where() {
          return {
            where() { return this; },
            limit() {
              return { get: async () => ({ empty: true, docs: [] }) };
            },
            get: async () => ({ empty: true, docs: [] }),
          };
        },
      };
    },
    async runTransaction(updateFn) {
      const pending = new Map();
      const tx = {
        async get(ref) {
          const existing = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
          return {
            exists: existing != null,
            data: () => (existing == null ? undefined : { ...existing }),
          };
        },
        set(ref, data, { merge } = {}) {
          const base = (pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key)) || {};
          pending.set(ref.key, merge ? { ...base, ...data } : { ...data });
        },
        delete(ref) {
          pending.set(ref.key, null);
        },
      };
      const result = await updateFn(tx);
      for (const [key, value] of pending.entries()) {
        if (value == null) docs.delete(key);
        else docs.set(key, value);
      }
      return result;
    },
  };
}

function stubSms(onCode) {
  const original = https.request;
  https.request = (options, callback) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = () => {};
    req.end = () => {
      const query = String(options.path || '').split('?')[1] || '';
      const code = new URLSearchParams(query).get('otp');
      if (code) onCode(code);
      const isVerify = String(options.path || '').includes('/otp/verify');
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = isVerify ? 400 : 200;
        callback(res);
        res.emit('data', JSON.stringify(isVerify ? { type: 'error', message: 'invalid' } : { type: 'success' }));
        res.emit('end');
      });
    };
    return req;
  };
  return () => {
    https.request = original;
  };
}

async function roundTrip({ role, mobile, demo }) {
  // OTP challenges live only in Redis (env-prefixed, HMAC-keyed); no document database.
  const db = null;
  const redis = createMemoryRedis();
  setRedisClientForTesting(redis);
  const readChallenge = async () => JSON.parse((await redis.get(otpRedisKey(role, mobile))) || 'null');
  let sentCode = null;
  const restoreSms = stubSms((code) => {
    sentCode = code;
  });
  try {
    if (demo) {
      process.env.REVIEWER_OTP_ENABLED = 'true';
      process.env.REVIEW_DOCTOR_PHONES = mobile;
      process.env.REVIEW_FIXED_OTP = '111111';
      process.env.REVIEW_ACCESS_UNTIL = '2099-01-01T00:00:00Z';
      setReviewerRedisClientForTesting(createTestRedisMock());
      resetReviewerRateLimitForTesting();
    }

    const sent = await sendUserRegistrationOtp(db, {
      mobile,
      role,
      otpType: 'registration',
    }, { clientIp: '127.0.0.1' });
    assert.equal(sent.ok, true);

    const stored = await readChallenge();
    assert.ok(stored, 'send must store a Redis OTP challenge');
    assert.ok((await redis.pttl(otpRedisKey(role, mobile))) <= 5 * 60 * 1000, 'challenge TTL <= 5 minutes');
    assert.equal(stored.role, role);
    assert.equal(stored.mobileDigits, mobile);
    const expectedCode = demo ? '111111' : sentCode;
    assert.ok(expectedCode, 'the sent code must be known to the test');
    assert.equal(
      stored.otpHash,
      hashOtp(expectedCode, { role, digits: mobile, purpose: 'create' }),
    );
    assert.notEqual(stored.otpHash.length, 0);

    await assert.rejects(
      () => verifyUserRegistrationOtp(db, {
        mobile,
        role,
        otp: '000001',
        otpType: 'registration',
      }, null, { clientIp: '127.0.0.1' }),
      { code: 'permission-denied' },
    );
    assert.ok(await readChallenge(), 'a wrong code must leave the challenge in place');

    const verified = await verifyUserRegistrationOtp(db, {
      mobile,
      role,
      otp: expectedCode,
      otpType: 'registration',
    }, null, { clientIp: '127.0.0.1' });
    assert.equal(verified.ok, true);
    assert.equal(verified.mobileVerified, true);
    assert.equal(verified.exists, false);
    assert.equal(verified.role, null);
    assert.equal(await readChallenge(), null, 'challenge is single-use');
    await assert.rejects(
      () => verifyUserRegistrationOtp(db, { mobile, role, otp: expectedCode, otpType: 'registration' }, null, { clientIp: '127.0.0.1' }),
      { code: 'failed-precondition' },
    );
  } finally {
    restoreSms();
    delete process.env.REVIEWER_OTP_ENABLED;
    delete process.env.REVIEW_DOCTOR_PHONES;
    delete process.env.REVIEW_FIXED_OTP;
    delete process.env.REVIEW_ACCESS_UNTIL;
    setReviewerRedisClientForTesting(null);
    resetReviewerRateLimitForTesting();
  }
}

test('patient send then verify accepts the stored HMAC and rejects a wrong code', async () => {
  assert.equal(process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH, undefined);
  await roundTrip({ role: 'patient', mobile: '9000000001', demo: false });
});

test('a non-allowlisted number configured as REVIEW_DOCTOR_PHONES gets a normal SMS OTP (no fixed code)', async () => {
  // Demo/reviewer numbers are fixed in lib/demo_accounts.js; env phone lists no longer add
  // bypass numbers. Full demo coverage: test/demo_otp_policy.test.js.
  assert.equal(process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH, undefined);
  process.env.REVIEW_DOCTOR_PHONES = '9000000002';
  await roundTrip({ role: 'doctor', mobile: '9000000002', demo: false });
});

test.after(() => {
  delete process.env.REVIEWER_OTP_ENABLED;
  delete process.env.REVIEW_DOCTOR_PHONES;
  delete process.env.REVIEW_FIXED_OTP;
  delete process.env.REVIEW_ACCESS_UNTIL;
  setReviewerRedisClientForTesting(null);
});
