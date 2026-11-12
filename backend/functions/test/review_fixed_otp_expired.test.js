'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { consumeOtpChallengeAtomically } = require('../registration_otp');

test('fixed REVIEW OTP rejected when OTP_TEST_MODE is off and REVIEW_ACCESS_UNTIL is past', async () => {
  delete process.env.OTP_TEST_MODE;
  process.env.OTP_TEST_MODE = 'false';
  process.env.REVIEWER_OTP_ENABLED = 'true';
  process.env.REVIEW_PATIENT_PHONES = '9999900001';
  process.env.REVIEW_FIXED_OTP = '112233';
  process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z';

  const mockDb = {
    collection: () => ({
      doc: () => ({
        get: async () => ({
          exists: true,
          data: () => ({
            role: 'patient',
            mobileDigits: '9999900001',
            otpHash: 'stored_hmac_hash',
            expiresAt: { toDate: () => new Date(Date.now() + 600000) },
            attempts: 0,
          }),
        }),
      }),
    }),
    runTransaction: async (fn) => fn({
      get: async () => ({
        exists: true,
        data: () => ({
          role: 'patient',
          mobileDigits: '9999900001',
          otpHash: 'stored_hmac_hash',
          expiresAt: { toDate: () => new Date(Date.now() + 600000) },
          attempts: 0,
        }),
      }),
      set: () => {},
      delete: () => {},
    }),
  };

  await assert.rejects(
    () => consumeOtpChallengeAtomically(mockDb, {
      challengeKey: 'mock_key',
      otp: '112233',
      mobileDigits: '9999900001',
      role: 'patient',
    }),
    (err) => {
      assert.equal(err.code, 'permission-denied');
      return true;
    },
    'Expired reviewer window must not accept fixed OTP',
  );
});
