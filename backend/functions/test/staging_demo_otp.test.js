'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isStagingDemoPhone,
  isStagingDemoOtpEnabled,
  shouldSkipMsg91ForPhone,
} = require('../registration_otp');

test('staging DEMO_PHONE_NUMBERS disabled when APP_ENV=production', () => {
  const prev = { ...process.env };
  process.env.APP_ENV = 'production';
  process.env.DEMO_PHONE_NUMBERS = '9999900001';
  assert.equal(isStagingDemoOtpEnabled(), false);
  assert.equal(isStagingDemoPhone('9999900001'), false);
  process.env = prev;
});

test('staging DEMO_PHONE_NUMBERS active when APP_ENV=staging', () => {
  const prev = { ...process.env };
  process.env.APP_ENV = 'staging';
  process.env.DEMO_PHONE_NUMBERS = '9999900001,9999900002';
  assert.equal(isStagingDemoOtpEnabled(), true);
  assert.equal(isStagingDemoPhone('9999900001'), true);
  assert.equal(shouldSkipMsg91ForPhone('9999900001', 'patient'), true);
  process.env = prev;
});