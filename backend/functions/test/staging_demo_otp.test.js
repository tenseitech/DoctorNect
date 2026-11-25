'use strict';

/**
 * The staging-only DEMO_PHONE_NUMBERS / DEMO_FIXED_OTP bypass was removed: only the five
 * numbers in lib/demo_accounts.js may skip SMS, in every environment.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isStagingDemoPhone,
  shouldSkipMsg91ForPhone,
} = require('../registration_otp');

for (const appEnv of ['production', 'staging']) {
  test(`DEMO_PHONE_NUMBERS grants nothing when APP_ENV=${appEnv}`, () => {
    const prev = { ...process.env };
    try {
      process.env.APP_ENV = appEnv;
      process.env.DEMO_PHONE_NUMBERS = '9876543210,9123456789';
      process.env.DEMO_FIXED_OTP = '000000';
      assert.equal(isStagingDemoPhone('9876543210'), false);
      assert.equal(shouldSkipMsg91ForPhone('9876543210', 'patient'), false);
      assert.equal(shouldSkipMsg91ForPhone('9123456789'), false);
    } finally {
      process.env = prev;
    }
  });
}

test('only the five fixed demo numbers skip SMS (regardless of role or env lists)', () => {
  for (const d of ['9999900001', '9999900002', '9999900003', '9999900004', '9999900005']) {
    assert.equal(shouldSkipMsg91ForPhone(d, 'patient'), true, d);
  }
  assert.equal(shouldSkipMsg91ForPhone('9999900006', 'patient'), false);
  assert.equal(shouldSkipMsg91ForPhone('09999900001', 'patient'), false);
});
