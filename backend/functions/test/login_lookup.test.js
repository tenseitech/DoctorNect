'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveLoginLookupPlane,
} = require('../src/db/login_lookup');

describe('login_lookup plane', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production reviewer phone → supabase without role hint', () => {
    process.env.APP_ENV = 'production';
    process.env.REVIEWER_OTP_ENABLED = 'true';
    process.env.REVIEW_ACCESS_UNTIL = '2099-01-01T00:00:00.000Z';
    process.env.REVIEW_FIXED_OTP = '112233';
    process.env.REVIEW_PATIENT_PHONES = '9999900001';
    assert.equal(resolveLoginLookupPlane('9999900001', null), 'supabase');
  });

  it('production normal phone → rds', () => {
    process.env.APP_ENV = 'production';
    process.env.REVIEWER_OTP_ENABLED = 'false';
    assert.equal(resolveLoginLookupPlane('9876543210', 'patient'), 'rds');
  });
});