'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { verifyProductionConfig } = require('../../scripts/verify_production_build_config');

test('verify_production_build_config: stale staging ref detection test suite (CFG-01)', async (t) => {
  await t.test('fails when SUPABASE_URL contains stale staging reference irpkyedfmdsuvapfnrim', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: false,
      SUPABASE_URL: 'https://irpkyedfmdsuvapfnrim.supabase.co',
      SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_valid_length_key_for_testing_purposes_only_1234567890',
    });

    assert.equal(result.success, false, 'Expected configuration check to fail on staging ref');
    const hasStagingError = result.errors.some(e => e.includes('irpkyedfmdsuvapfnrim') || e.includes('staging'));
    assert.ok(hasStagingError, 'Expected an error message specifically mentioning staging reference');
  });

  await t.test('passes when SUPABASE_URL points to valid production project ref', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: false,
      SUPABASE_URL: 'https://rnltknemwnjrjxthtull.supabase.co',
      SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_valid_length_key_for_testing_purposes_only_1234567890',
    });

    assert.equal(result.success, true, 'Expected configuration check to pass with production ref');
    assert.equal(result.errors.length, 0);
  });

  await t.test('allows staging URL when allowStaging is explicitly true', () => {
    const result = verifyProductionConfig({
      clientOnly: true,
      allowStaging: true,
      SUPABASE_URL: 'https://irpkyedfmdsuvapfnrim.supabase.co',
      SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_valid_length_key_for_testing_purposes_only_1234567890',
    });

    assert.equal(result.success, true, 'Expected configuration check to pass when allowStaging is true');
  });
});
