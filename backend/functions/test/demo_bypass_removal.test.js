'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const registrationOtp = require('../registration_otp');
const {
  getReviewerConfig,
  isReviewerPhone,
  checkReviewerRateLimit,
  setReviewerRedisClientForTesting,
  resetReviewerRateLimitForTesting,
  consumeOtpChallengeAtomically,
} = registrationOtp;

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

test.describe('P0 Demo Bypass Removal & Reviewer-Only Fixed OTP Guard', () => {
  const origReviewerEnabled = process.env.REVIEWER_OTP_ENABLED;
  const origReviewPatientPhones = process.env.REVIEW_PATIENT_PHONES;
  const origReviewOtp = process.env.REVIEW_FIXED_OTP;
  const origReviewUntil = process.env.REVIEW_ACCESS_UNTIL;
  let origLegacyCutover;

  test.beforeEach(() => {
    origLegacyCutover = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}
  });

  test.afterEach(() => {
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    if (origLegacyCutover === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacyCutover;
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}

    if (origReviewerEnabled === undefined) delete process.env.REVIEWER_OTP_ENABLED;
    else process.env.REVIEWER_OTP_ENABLED = origReviewerEnabled;

    if (origReviewPatientPhones === undefined) delete process.env.REVIEW_PATIENT_PHONES;
    else process.env.REVIEW_PATIENT_PHONES = origReviewPatientPhones;

    if (origReviewOtp === undefined) delete process.env.REVIEW_FIXED_OTP;
    else process.env.REVIEW_FIXED_OTP = origReviewOtp;

    if (origReviewUntil === undefined) delete process.env.REVIEW_ACCESS_UNTIL;
    else process.env.REVIEW_ACCESS_UNTIL = origReviewUntil;

    resetReviewerRateLimitForTesting();
    setReviewerRedisClientForTesting(null);
  });

  test('1. Legacy demo functions and constants are completely removed from module exports', () => {
    assert.equal(registrationOtp.isDemoPhone, undefined, 'isDemoPhone must not exist');
    assert.equal(registrationOtp.isDemoMobileInput, undefined, 'isDemoMobileInput must not exist');
    assert.equal(registrationOtp.isPlayReviewMobileInput, undefined, 'isPlayReviewMobileInput must not exist');
    assert.equal(registrationOtp.getDemoConfig, undefined, 'getDemoConfig must not exist');
    assert.equal(registrationOtp.setDemoConfigDocForTesting, undefined, 'setDemoConfigDocForTesting must not exist');
    assert.equal(registrationOtp.DEFAULT_DEMO_CONFIG, undefined, 'DEFAULT_DEMO_CONFIG must not exist');
    assert.equal(registrationOtp.DEV_TEST_OTP, undefined, 'DEV_TEST_OTP must not exist');
    assert.equal(registrationOtp.isTestMode, undefined, 'isTestMode must not exist');
  });

  test('2. When REVIEW_* env is unset: reviewer config is null (production default is OFF)', () => {
    delete process.env.REVIEWER_OTP_ENABLED;
    delete process.env.REVIEW_PATIENT_PHONES;
    delete process.env.REVIEW_FIXED_OTP;
    delete process.env.REVIEW_ACCESS_UNTIL;

    assert.equal(getReviewerConfig('patient'), null, 'getReviewerConfig must return null when env is unset');
  });

  test('3. When REVIEW_* env is unset: a formerly-demo number can NOT log in with any fixed OTP', async () => {
    delete process.env.REVIEWER_OTP_ENABLED;
    delete process.env.REVIEW_PATIENT_PHONES;
    delete process.env.REVIEW_FIXED_OTP;
    delete process.env.REVIEW_ACCESS_UNTIL;

    // Use a formerly-demo test number
    const testPhone = '9999900001';

    assert.equal(isReviewerPhone(testPhone, 'patient'), false, 'Must not be recognized as reviewer phone');

    // Attempting fixed OTP 000000 or 123456 against challenge must fail
    const mockDb = {
      collection: () => ({
        doc: () => ({
          get: async () => ({
            exists: true,
            data: () => ({
              role: 'patient',
              mobileDigits: testPhone,
              otpHash: 'some_real_msg91_hmac_hash',
              expiresAt: { toDate: () => new Date(Date.now() + 600000) },
              attempts: 0,
            }),
          }),
        }),
      }),
      runTransaction: async (fn) => {
        return fn({
          get: async () => ({
            exists: true,
            data: () => ({
              role: 'patient',
              mobileDigits: testPhone,
              otpHash: 'some_real_msg91_hmac_hash',
              expiresAt: { toDate: () => new Date(Date.now() + 600000) },
              attempts: 0,
            }),
          }),
          set: () => {},
          delete: () => {},
        });
      },
    };

    // Neither '000000' nor '123456' can be consumed
    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(mockDb, {
          challengeKey: 'mock_key',
          otp: '000000',
          mobileDigits: testPhone,
          role: 'patient',
        });
      },
      (err) => {
        assert.equal(err.code, 'permission-denied', 'Fixed OTP 000000 must be rejected');
        return true;
      },
    );

    await assert.rejects(
      async () => {
        await consumeOtpChallengeAtomically(mockDb, {
          challengeKey: 'mock_key',
          otp: '123456',
          mobileDigits: testPhone,
          role: 'patient',
        });
      },
      (err) => {
        assert.equal(err.code, 'permission-denied', 'Dev OTP 123456 must be rejected');
        return true;
      },
    );
  });

  test('4. Active reviewer bypass: only allowlisted numbers accept fixed OTP', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001,9999900002';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-01-01T00:00:00Z'; // Future
    setReviewerRedisClientForTesting(createTestRedisMock());

    assert.equal(isReviewerPhone('9999900001', 'patient'), true, 'Allowlisted number must match');
    assert.equal(isReviewerPhone('9999900002', 'patient'), true, 'Allowlisted number must match');
    assert.equal(isReviewerPhone('9999900003', 'patient'), false, 'Non-allowlisted number must NOT match');

    const mockDb = {
      collection: () => ({
        doc: () => ({
          get: async () => ({
            exists: true,
            data: () => ({
              role: 'patient',
              mobileDigits: '9999900001',
              otpHash: 'dummy_hash',
              expiresAt: { toDate: () => new Date(Date.now() + 600000) },
              attempts: 0,
            }),
          }),
        }),
      }),
      runTransaction: async (fn) => {
        return fn({
          get: async () => ({
            exists: true,
            data: () => ({
              role: 'patient',
              mobileDigits: '9999900001',
              otpHash: 'dummy_hash',
              expiresAt: { toDate: () => new Date(Date.now() + 600000) },
              attempts: 0,
            }),
          }),
          set: () => {},
          delete: () => {},
        });
      },
    };

    // Reviewer number with valid fixed OTP succeeds
    const res = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey: 'mock_key',
      otp: '112233',
      mobileDigits: '9999900001',
      role: 'patient',
    });
    assert.equal(res.consumed, true, 'Reviewer with valid fixed OTP must succeed');
  });

  test('5. Expired REVIEW_ACCESS_UNTIL shuts down reviewer bypass immediately', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z'; // Past date

    assert.equal(getReviewerConfig('patient'), null, 'Reviewer config must be null when access date is expired');
    assert.equal(isReviewerPhone('9999900001', 'patient'), false, 'isReviewerPhone must be false when expired');
  });

  test('6. Reviewer rate limit enforces maximum 5 attempts', async () => {
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_ACCESS_UNTIL = '2099-01-01T00:00:00Z';
    setReviewerRedisClientForTesting(createTestRedisMock());

    const phone = '9999900001';
    for (let i = 1; i <= 5; i++) {
      assert.equal(await checkReviewerRateLimit(phone), true, `Attempt ${i} must be allowed`);
    }
    assert.equal(await checkReviewerRateLimit(phone), false, 'Attempt 6 must be blocked by rate limit');
  });
});
