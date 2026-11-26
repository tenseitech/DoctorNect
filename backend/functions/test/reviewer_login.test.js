'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getReviewerConfig,
  isReviewerPhone,
  checkReviewerRateLimit,
  setReviewerRedisClientForTesting,
  resetReviewerRateLimitForTesting,
  consumeOtpChallengeAtomically,
} = require('../registration_otp');

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

test.describe('Play Store Server-Side Reviewer Login Gating', () => {
  const origReviewOtp = process.env.REVIEW_FIXED_OTP;
  const origReviewUntil = process.env.REVIEW_ACCESS_UNTIL;
  const origReviewerOtpEnabled = process.env.REVIEWER_OTP_ENABLED;
  const origReviewDoctorPhones = process.env.REVIEW_DOCTOR_PHONES;
  const origReviewPatientPhones = process.env.REVIEW_PATIENT_PHONES;

  test.afterEach(() => {
    if (origReviewOtp === undefined) delete process.env.REVIEW_FIXED_OTP;
    else process.env.REVIEW_FIXED_OTP = origReviewOtp;

    if (origReviewUntil === undefined) delete process.env.REVIEW_ACCESS_UNTIL;
    else process.env.REVIEW_ACCESS_UNTIL = origReviewUntil;

    if (origReviewerOtpEnabled === undefined) delete process.env.REVIEWER_OTP_ENABLED;
    else process.env.REVIEWER_OTP_ENABLED = origReviewerOtpEnabled;

    if (origReviewDoctorPhones === undefined) delete process.env.REVIEW_DOCTOR_PHONES;
    else process.env.REVIEW_DOCTOR_PHONES = origReviewDoctorPhones;

    if (origReviewPatientPhones === undefined) delete process.env.REVIEW_PATIENT_PHONES;
    else process.env.REVIEW_PATIENT_PHONES = origReviewPatientPhones;

    delete process.env.ENABLE_REVIEW_DEMO;

    resetReviewerRateLimitForTesting();
    setReviewerRedisClientForTesting(null);
  });

  test('Case 1: REVIEWER_OTP_ENABLED unset -> fail closed', () => {
    delete process.env.REVIEWER_OTP_ENABLED;
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(getReviewerConfig('patient'), null);
    assert.equal(isReviewerPhone('9999900001', 'patient'), false);
  });

  test('Case 2: missing or expired REVIEW_ACCESS_UNTIL -> disabled', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';

    delete process.env.REVIEW_ACCESS_UNTIL;
    assert.equal(getReviewerConfig('patient'), null);

    process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z';
    assert.equal(getReviewerConfig('patient'), null);
    assert.equal(isReviewerPhone('9999900001', 'patient'), false);
  });

  test('Case 3: missing REVIEW_FIXED_OTP -> disabled', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';
    delete process.env.REVIEW_FIXED_OTP;

    assert.equal(getReviewerConfig('patient'), null);
    assert.equal(isReviewerPhone('9999900001', 'patient'), false);
  });

  test('Case 4: role comes from the fixed allowlist; a wrong client role never matches', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(getReviewerConfig(undefined), null);
    // 9999900001 is the demo DOCTOR.
    assert.equal(isReviewerPhone('9999900001'), true, 'no role: allowlist decides');
    assert.equal(isReviewerPhone('9999900001', 'doctor'), true);
    assert.equal(isReviewerPhone('9999900001', 'patient'), false, 'client role cannot re-map a demo number');
    assert.equal(isReviewerPhone('9999900002', 'patient'), true);
  });

  test('Case 5: numbers are fixed in code; REVIEW_*_PHONES env lists cannot add numbers', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9876543210,9999900002';
    process.env.REVIEW_DOCTOR_PHONES = '9888800001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.deepEqual(getReviewerConfig('patient').testNumbers, ['9999900002']);
    assert.deepEqual(getReviewerConfig('doctor').testNumbers, ['9999900001']);
    assert.equal(isReviewerPhone('9876543210', 'patient'), false);
    assert.equal(isReviewerPhone('9888800001', 'doctor'), false);
  });

  test('Case 6: ENABLE_REVIEW_DEMO alias removed (no effect)', () => {
    process.env.ENABLE_REVIEW_DEMO = 'true';
    delete process.env.REVIEWER_OTP_ENABLED;
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(getReviewerConfig('patient'), null);
  });

  test('Case 7: Reviewer rate limit locks out after exceeding max attempts', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';
    setReviewerRedisClientForTesting(createTestRedisMock());

    const digits = '9999900001';
    for (let i = 1; i <= 5; i++) {
      assert.equal(await checkReviewerRateLimit(digits), true, `Attempt ${i} within limit must be allowed`);
    }
    assert.equal(await checkReviewerRateLimit(digits), false, '6th attempt must be rejected by rate limiter');
  });

  test('Case 8: Full OTP verification flow with reviewer bypass', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '654321';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';
    setReviewerRedisClientForTesting(createTestRedisMock());

    // Reviewer challenge in Redis (no document DB); the stored hash is for a different code.
    const { enableOtpRedisTestEnv, seedOtpChallenge } = require('./helpers/otp_test_redis');
    const otpRedis = enableOtpRedisTestEnv();
    seedOtpChallenge(otpRedis, { otpCode: '999999', role: 'patient', mobileDigits: '9999900001', extra: { reviewerAccount: true } });
    const mockDb = null;
    const challengeKey = 'unused_with_redis';

    await assert.rejects(
      consumeOtpChallengeAtomically(mockDb, {
        challengeKey,
        otp: '000000',
        isDemoAccount: false,
        mobileDigits: '9999900001',
        role: 'patient',
      }),
      /Invalid OTP/
    );

    const correctRes = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey,
      otp: '654321',
      isDemoAccount: false,
      mobileDigits: '9999900001',
      role: 'patient',
    });
    assert.equal(correctRes.consumed, true);
  });

  test('Case 9: Fail-closed when Redis is unavailable or broken', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    const brokenRedis = {
      async eval() { throw new Error('ECONNREFUSED 127.0.0.1:6379'); },
      async incr() { throw new Error('ECONNREFUSED 127.0.0.1:6379'); },
    };
    setReviewerRedisClientForTesting(brokenRedis);

    try {
      await assert.rejects(
        async () => {
          await checkReviewerRateLimit('9999900001');
        },
        (err) => {
          assert.equal(err.code, 'unavailable');
          return true;
        }
      );
    } finally {
      setReviewerRedisClientForTesting(null);
    }
  });
});
