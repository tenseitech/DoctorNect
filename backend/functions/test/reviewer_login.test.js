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

test.describe('Play Store Server-Side Reviewer Login Gating', () => {
  const origReviewNumbers = process.env.REVIEW_TEST_NUMBERS;
  const origReviewOtp = process.env.REVIEW_FIXED_OTP;
  const origReviewUntil = process.env.REVIEW_ACCESS_UNTIL;
  const origReviewerOtpEnabled = process.env.REVIEWER_OTP_ENABLED;
  const origReviewDoctorPhones = process.env.REVIEW_DOCTOR_PHONES;
  const origReviewPatientPhones = process.env.REVIEW_PATIENT_PHONES;

  test.afterEach(() => {
    if (origReviewNumbers === undefined) delete process.env.REVIEW_TEST_NUMBERS;
    else process.env.REVIEW_TEST_NUMBERS = origReviewNumbers;

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
  });

  test('Case 1: REVIEWER_OTP_ENABLED unset -> fail closed', () => {
    delete process.env.REVIEWER_OTP_ENABLED;
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
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

  test('Case 4: role required for match; undefined role never matches', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(getReviewerConfig(undefined), null);
    assert.equal(isReviewerPhone('9999900001'), false);
    assert.equal(isReviewerPhone('9999900001', undefined), false);
    assert.equal(isReviewerPhone('9999900001', 'patient'), true);
  });

  test('Case 5: per-role phone lists max 2', () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001,9999900002,9999900003';
    process.env.REVIEW_DOCTOR_PHONES = '9888800001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.deepEqual(getReviewerConfig('patient').testNumbers, ['9999900001', '9999900002']);
    assert.equal(isReviewerPhone('9999900001', 'doctor'), false);
    assert.equal(isReviewerPhone('9888800001', 'doctor'), true);
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

    const challenges = new Map();
    const mockDb = {
      collection: (colName) => ({
        doc: (docId) => ({
          get: async () => ({
            exists: challenges.has(`${colName}/${docId}`),
            data: () => challenges.get(`${colName}/${docId}`),
          }),
          set: async (data, opts) => {
            const key = `${colName}/${docId}`;
            if (opts && opts.merge) {
              challenges.set(key, { ...(challenges.get(key) || {}), ...data });
            } else {
              challenges.set(key, data);
            }
          },
          delete: async () => {
            challenges.delete(`${colName}/${docId}`);
          },
        }),
      }),
      runTransaction: async (fn) => {
        const tx = {
          get: async (ref) => ref.get(),
          set: async (ref, data, opts) => ref.set(data, opts),
          delete: async (ref) => ref.delete(),
        };
        return fn(tx);
      },
    };

    const challengeKey = 'test_reviewer_challenge';
    await mockDb.collection('otp_challenges').doc(challengeKey).set({
      role: 'patient',
      mobileDigits: '9999900001',
      attempts: 0,
      reviewerAccount: true,
      expiresAt: { toDate: () => new Date(Date.now() + 600000) },
    });

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
