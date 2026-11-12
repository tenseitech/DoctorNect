'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const https = require('https');
const { EventEmitter } = require('events');
const { HttpsError } = require('firebase-functions/v2/https');
const { setRedisClientForTesting } = require('../redis');
const {
  sendUserRegistrationOtp,
  consumeOtpChallengeAtomically,
  hashOtp,
} = require('../registration_otp');
const { redisKey: envRedisKey } = require('../src/config/redis_keys');

process.env.MSG91_AUTH_KEY = 'test_msg91_authkey_pure_redis';
process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'test_template_reg_pure_redis';
process.env.MSG91_SENDER_ID = 'DRNECT';
delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
process.env.FIRESTORE_FORBIDDEN = '1';
process.env.OTP_REDIS_MIRROR = 'on';
process.env.APP_ENV = 'staging';

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
      if (code && onCode) onCode(code);
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = 200;
        callback(res);
        res.emit('data', JSON.stringify({ type: 'success' }));
        res.emit('end');
      });
    };
    return req;
  };
  return () => {
    https.request = original;
  };
}

function createMockRedisStore() {
  const store = new Map();
  return {
    store,
    async get(key) {
      const item = store.get(key);
      if (!item) return null;
      return item.val;
    },
    async set(key, val, mode, ttlSec) {
      const expiresAt = (mode === 'EX' && ttlSec) ? Date.now() + (ttlSec * 1000) : null;
      store.set(key, { val: String(val), expiresAt });
      return 'OK';
    },
    async del(key) {
      if (store.has(key)) {
        store.delete(key);
        return 1;
      }
      return 0;
    },
    async incr(key) {
      const item = store.get(key);
      const curr = item ? Number(item.val) || 0 : 0;
      const next = curr + 1;
      store.set(key, { val: String(next), expiresAt: item?.expiresAt || null });
      return next;
    },
    async pexpire(key, ms) {
      const item = store.get(key);
      if (item) {
        item.expiresAt = Date.now() + ms;
      }
      return 1;
    },
    async eval() {
      return 1;
    },
  };
}

// Dummy db that throws if touched (guaranteed by FIRESTORE_FORBIDDEN=1)
const dummyDb = {};

test('1. Redis UP: OTP send and verify succeed with zero Firestore access', async () => {
  const mockRedis = createMockRedisStore();
  setRedisClientForTesting(mockRedis);
  let capturedCode = null;
  const restoreSms = stubSms((c) => { capturedCode = c; });

  try {
    const mobile = '9876543210';
    const role = 'patient';
    const clientIp = '10.0.0.1';

    // 1. Send OTP
    const sendRes = await sendUserRegistrationOtp(dummyDb, {
      mobile,
      role,
      otpType: 'registration',
    }, { clientIp });

    assert.equal(sendRes.ok, true);

    // Verify Redis has challenge
    const keys = Array.from(mockRedis.store.keys());
    const challengeKey = keys.find((k) => k.includes('otp:challenge:'));
    assert.ok(challengeKey, 'Challenge must be stored in Redis');
    const challengeData = JSON.parse(mockRedis.store.get(challengeKey).val);

    // 2. Set known hash to test verification
    const testCode = capturedCode || '654321';
    challengeData.otpHash = hashOtp(testCode, { role, digits: mobile, purpose: 'create' });
    mockRedis.store.set(challengeKey, { val: JSON.stringify(challengeData), expiresAt: challengeData.expiresAt });

    // 3. Verify OTP
    const verifyRes = await consumeOtpChallengeAtomically(dummyDb, {
      role,
      mobileDigits: mobile,
      otp: testCode,
      challengeKey: 'not_used_in_cutover',
    });

    assert.equal(verifyRes.consumed, true);
  } finally {
    restoreSms();
    setRedisClientForTesting(null);
  }
});

test('2. Redis DOWN: sendUserRegistrationOtp fails closed with unavailable error', async () => {
  const brokenRedis = {
    async get() { throw new Error('ECONNREFUSED'); },
    async set() { throw new Error('ECONNREFUSED'); },
    async del() { throw new Error('ECONNREFUSED'); },
    async incr() { throw new Error('ECONNREFUSED'); },
    async pexpire() { throw new Error('ECONNREFUSED'); },
  };
  setRedisClientForTesting(brokenRedis);

  try {
    await assert.rejects(
      async () => {
        await sendUserRegistrationOtp(dummyDb, {
          mobile: '9876543211',
          role: 'patient',
          otpType: 'registration',
        }, { clientIp: '10.0.0.2' });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'unavailable');
        return true;
      }
    );
  } finally {
    setRedisClientForTesting(null);
  }
});

test('3. Redis DOWN: consumeOtpChallengeAtomically fails closed with unavailable error', async () => {
  const brokenRedis = {
    async get() { throw new Error('ECONNREFUSED'); },
    async del() { throw new Error('ECONNREFUSED'); },
  };
  setRedisClientForTesting(brokenRedis);

  try {
    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(dummyDb, {
          role: 'patient',
          mobileDigits: '9876543212',
          otp: '123456',
        });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'unavailable');
        return true;
      }
    );
  } finally {
    setRedisClientForTesting(null);
  }
});

test('4. Expired OTP: past TTL throws deadline-exceeded', async () => {
  const mockRedis = createMockRedisStore();
  setRedisClientForTesting(mockRedis);

  try {
    const mobile = '9876543213';
    const role = 'patient';
    const testCode = '654321';

    const secret = process.env.MSG91_AUTH_KEY;
    const hashed = crypto.createHmac('sha256', secret).update(mobile).digest('hex');
    const keyNull = envRedisKey(`otp:challenge:${hashed}`);
    const keyRole = envRedisKey(`otp:challenge:${role}:${hashed}`);

    const payload = JSON.stringify({
      otpHash: hashOtp(testCode, { role, digits: mobile, purpose: 'create' }),
      role,
      mobileDigits: mobile,
      expiresAt: Date.now() - 5000, // Expired 5 seconds ago
    });
    mockRedis.store.set(keyNull, { val: payload, expiresAt: Date.now() + 60000 });
    mockRedis.store.set(keyRole, { val: payload, expiresAt: Date.now() + 60000 });

    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(dummyDb, {
          role,
          mobileDigits: mobile,
          otp: testCode,
        });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'deadline-exceeded');
        assert.match(err.message, /expired/i);
        return true;
      }
    );
  } finally {
    setRedisClientForTesting(null);
  }
});

test('5. 5 failed attempts lockout: wrong OTP 5 times locks out and deletes challenge', async () => {
  const mockRedis = createMockRedisStore();
  setRedisClientForTesting(mockRedis);

  try {
    const mobile = '9876543214';
    const role = 'patient';
    const correctCode = '654321';
    const wrongCode = '000000';

    const secret = process.env.MSG91_AUTH_KEY;
    const hashed = crypto.createHmac('sha256', secret).update(mobile).digest('hex');
    const keyNull = envRedisKey(`otp:challenge:${hashed}`);
    const keyRole = envRedisKey(`otp:challenge:${role}:${hashed}`);

    const payload = JSON.stringify({
      otpHash: hashOtp(correctCode, { role, digits: mobile, purpose: 'create' }),
      role,
      mobileDigits: mobile,
      expiresAt: Date.now() + 600000,
    });
    mockRedis.store.set(keyNull, { val: payload, expiresAt: Date.now() + 600000 });
    mockRedis.store.set(keyRole, { val: payload, expiresAt: Date.now() + 600000 });

    // Fail 4 times: throws invalid-argument
    for (let i = 1; i <= 4; i++) {
      await assert.rejects(
        async () => {
          await consumeOtpChallengeAtomically(dummyDb, {
            role,
            mobileDigits: mobile,
            otp: wrongCode,
          });
        },
        (err) => {
          assert.ok(err instanceof HttpsError);
          assert.equal(err.code, 'invalid-argument');
          return true;
        }
      );
    }

    // 5th failed attempt: throws resource-exhausted (lockout!)
    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(dummyDb, {
          role,
          mobileDigits: mobile,
          otp: wrongCode,
        });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'resource-exhausted');
        assert.match(err.message, /Too many failed attempts/i);
        return true;
      }
    );

    // Challenge must be deleted from Redis
    assert.equal(mockRedis.store.has(keyNull), false);
    assert.equal(mockRedis.store.has(keyRole), false);

    // 6th attempt with correct OTP must fail because challenge was deleted
    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(dummyDb, {
          role,
          mobileDigits: mobile,
          otp: correctCode,
        });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.ok(err.code === 'resource-exhausted' || err.code === 'failed-precondition');
        return true;
      }
    );
  } finally {
    setRedisClientForTesting(null);
  }
});

test('6. Concurrent verify race: exactly one request succeeds and the other fails', async () => {
  const mockRedis = createMockRedisStore();
  setRedisClientForTesting(mockRedis);

  try {
    const mobile = '9876543215';
    const role = 'patient';
    const testCode = '654321';

    const secret = process.env.MSG91_AUTH_KEY;
    const hashed = crypto.createHmac('sha256', secret).update(mobile).digest('hex');
    const keyNull = envRedisKey(`otp:challenge:${hashed}`);
    const keyRole = envRedisKey(`otp:challenge:${role}:${hashed}`);

    const payload = JSON.stringify({
      otpHash: hashOtp(testCode, { role, digits: mobile, purpose: 'create' }),
      role,
      mobileDigits: mobile,
      expiresAt: Date.now() + 600000,
    });
    mockRedis.store.set(keyNull, { val: payload, expiresAt: Date.now() + 600000 });
    mockRedis.store.set(keyRole, { val: payload, expiresAt: Date.now() + 600000 });

    // Race two simultaneous verify requests
    const p1 = consumeOtpChallengeAtomically(dummyDb, {
      role,
      mobileDigits: mobile,
      otp: testCode,
    }).then(
      (res) => ({ status: 'fulfilled', value: res }),
      (err) => ({ status: 'rejected', reason: err })
    );

    const p2 = consumeOtpChallengeAtomically(dummyDb, {
      role,
      mobileDigits: mobile,
      otp: testCode,
    }).then(
      (res) => ({ status: 'fulfilled', value: res }),
      (err) => ({ status: 'rejected', reason: err })
    );

    const [r1, r2] = await Promise.all([p1, p2]);

    const successes = [r1, r2].filter((r) => r.status === 'fulfilled');
    const failures = [r1, r2].filter((r) => r.status === 'rejected');

    assert.equal(successes.length, 1, 'Exactly one concurrent verification must succeed');
    assert.equal(failures.length, 1, 'The other concurrent verification must fail');
    assert.equal(successes[0].value.consumed, true);
    assert.equal(failures[0].reason.code, 'failed-precondition');
  } finally {
    setRedisClientForTesting(null);
  }
});
