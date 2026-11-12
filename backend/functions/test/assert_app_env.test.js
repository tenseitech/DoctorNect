'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { assertAppEnvDatabaseRouting } = require('../src/db/assert_app_env');

describe('assertAppEnvDatabaseRouting', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects missing PROD_GATEWAY_*', () => {
    process.env.APP_ENV = 'production';
    delete process.env.PROD_GATEWAY_URL;
    delete process.env.PROD_GATEWAY_SERVICE_KEY;
    assert.throws(() => assertAppEnvDatabaseRouting(), /PROD_GATEWAY_URL/);
  });

  it('production rejects supabase.co gateway URL', () => {
    process.env.APP_ENV = 'production';
    process.env.PROD_GATEWAY_URL = 'https://abc.supabase.co';
    process.env.PROD_GATEWAY_SERVICE_KEY = 'x'.repeat(40);
    assert.throws(() => assertAppEnvDatabaseRouting(), /supabase\.co/);
  });

  it('staging requires Supabase credentials', () => {
    process.env.APP_ENV = 'staging';
    delete process.env.STAGING_SUPABASE_URL;
    delete process.env.SUPABASE_URL;
    delete process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
    assert.throws(() => assertAppEnvDatabaseRouting(), /STAGING_SUPABASE_URL/);
  });

  it('staging passes with STAGING_* set', () => {
    process.env.APP_ENV = 'staging';
    process.env.STAGING_SUPABASE_URL = 'https://staging.example.supabase.co';
    process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY = 'staging-key-' + 'x'.repeat(32);
    assert.doesNotThrow(() => assertAppEnvDatabaseRouting());
  });
});
