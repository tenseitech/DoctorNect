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
  const origAppEnv = process.env.APP_ENV;
  const origEnableReviewDemo = process.env.ENABLE_REVIEW_DEMO;
  let origCutover;

  test.beforeEach(() => {
    origCutover = process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = '0';
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}
  });

  test.afterEach(() => {
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    if (origCutover === undefined) delete process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;
    else process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = origCutover;
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}

    if (origReviewNumbers === undefined) delete process.env.REVIEW_TEST_NUMBERS;
    else process.env.REVIEW_TEST_NUMBERS = origReviewNumbers;

    if (origReviewOtp === undefined) delete process.env.REVIEW_FIXED_OTP;
    else process.env.REVIEW_FIXED_OTP = origReviewOtp;

    if (origReviewUntil === undefined) delete process.env.REVIEW_ACCESS_UNTIL;
    else process.env.REVIEW_ACCESS_UNTIL = origReviewUntil;

    if (origAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = origAppEnv;

    if (origEnableReviewDemo === undefined) delete process.env.ENABLE_REVIEW_DEMO;
    else process.env.ENABLE_REVIEW_DEMO = origEnableReviewDemo;

    resetReviewerRateLimitForTesting();
  });

  test('Case 1: Production Default is OFF (unset env vars disables reviewer bypass)', () => {
    delete process.env.REVIEW_TEST_NUMBERS;
    delete process.env.REVIEW_FIXED_OTP;
    delete process.env.REVIEW_ACCESS_UNTIL;

    assert.equal(getReviewerConfig(), null, 'Reviewer config must be null when env vars are unset');
    assert.equal(isReviewerPhone('9999900001'), false, 'Allowlist check must return false when env is unset');
    assert.equal(isReviewerPhone('9999900003'), false, 'Non-reviewer number must return false');
  });

  test('Case 2: Expired REVIEW_ACCESS_UNTIL disables reviewer bypass', () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001,9999900002';
    process.env.REVIEW_FIXED_OTP = '112233';
    // Set expiry in the past (e.g. 2020)
    process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z';

    assert.equal(getReviewerConfig(), null, 'Reviewer config must be null when access date has expired');
    assert.equal(isReviewerPhone('9999900001'), false, 'Expired reviewer number must not be recognized');
  });

  test('Case 3: Active allowlisted numbers recognized before expiry date', () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001, 9999900002';
    process.env.REVIEW_FIXED_OTP = '112233';
    // Set expiry in the future
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    const config = getReviewerConfig();
    assert.ok(config, 'Reviewer config must be active');
    assert.equal(config.fixedOtp, '112233');
    assert.deepEqual(config.testNumbers, ['9999900001', '9999900002']);

    assert.equal(isReviewerPhone('9999900001'), true, 'Allowlisted number 1 must be active');
    assert.equal(isReviewerPhone('+91 9999900002'), true, 'Allowlisted number 2 with formatting must be active');
    assert.equal(isReviewerPhone('9999999999'), false, 'Non-allowlisted number must be rejected');
  });

  test('Case 4: Non-allowlisted number cannot use fixed OTP bypass', () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(isReviewerPhone('9888800001'), false);
    const config = getReviewerConfig();
    assert.ok(!config.testNumbers.includes('9888800001'));
  });

  test('Case 5: Reviewer rate limit locks out after exceeding max attempts', async () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    const digits = '9999900001';
    for (let i = 1; i <= 5; i++) {
      assert.equal(await checkReviewerRateLimit(digits), true, `Attempt ${i} within limit must be allowed`);
    }
    // 6th attempt must be blocked
    assert.equal(await checkReviewerRateLimit(digits), false, '6th attempt must be rejected by rate limiter');
    // Different allowlisted number is not locked out
    assert.equal(await checkReviewerRateLimit('9999900002'), true, 'Independent number must not be affected by lockout');
  });

  test('Case 6: Full OTP verification flow with reviewer bypass', async () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
    process.env.REVIEW_FIXED_OTP = '654321';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    // Mock Firestore db
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

    // Pre-seed a challenge
    const challengeKey = 'test_reviewer_challenge';
    await mockDb.collection('otp_challenges').doc(challengeKey).set({
      role: 'patient',
      mobileDigits: '9999900001',
      attempts: 0,
      reviewerAccount: true,
      expiresAt: { toDate: () => new Date(Date.now() + 600000) },
    });

    // 1. Wrong OTP should throw permission-denied (Invalid OTP)
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

    // 2. Correct fixed OTP should succeed and consume challenge
    const correctRes = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey,
      otp: '654321',
      isDemoAccount: false,
      mobileDigits: '9999900001',
      role: 'patient',
    });
    assert.equal(correctRes.consumed, true, 'Fixed OTP must consume challenge for allowlisted reviewer');
  });

  test('Case 7: Fail-closed when Redis is unavailable or broken', async () => {
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
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

  test('Case 8: APP_ENV=production disables reviewer bypass unless ENABLE_REVIEW_DEMO=true', () => {
    process.env.APP_ENV = 'production';
    delete process.env.ENABLE_REVIEW_DEMO;
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    assert.equal(getReviewerConfig(), null, 'Must return null in production when ENABLE_REVIEW_DEMO is not true');
    assert.equal(getReviewerConfig('patient'), null);
    assert.equal(isReviewerPhone('9999900001', 'patient'), false);
  });

  test('Case 9: APP_ENV=production with ENABLE_REVIEW_DEMO=true is strictly limited to patient role', () => {
    process.env.APP_ENV = 'production';
    process.env.ENABLE_REVIEW_DEMO = 'true';
    process.env.REVIEW_TEST_NUMBERS = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-12-31T23:59:59Z';

    // Patient role should succeed
    const patientCfg = getReviewerConfig('patient');
    assert.ok(patientCfg, 'Reviewer config must be active for patient role in prod when ENABLE_REVIEW_DEMO=true');
    assert.equal(isReviewerPhone('9999900001', 'patient'), true);

    // Doctor or other roles must be blocked
    assert.equal(getReviewerConfig('doctor'), null, 'Doctor role must be rejected in prod even if ENABLE_REVIEW_DEMO=true');
    assert.equal(isReviewerPhone('9999900001', 'doctor'), false);
    assert.equal(getReviewerConfig('ambulance'), null, 'Ambulance role must be rejected in prod');
    assert.equal(isReviewerPhone('9999900001', 'ambulance'), false);
    assert.equal(getReviewerConfig('medical'), null, 'Medical role must be rejected in prod');
    assert.equal(isReviewerPhone('9999900001', 'medical'), false);
  });
});

