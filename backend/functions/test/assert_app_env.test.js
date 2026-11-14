'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertAppEnvDatabaseRouting,
  assertProductionRedisTls,
  assertProductionOtpHmacOnly,
} = require('../src/db/assert_app_env');

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

describe('assertProductionRedisTls', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects REDIS_TLS=false', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_TLS = 'false';
    assert.throws(() => assertProductionRedisTls(), /REDIS_TLS/);
  });

  it('production rejects redis:// host URL', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_HOST = 'redis://cache.example:6379';
    delete process.env.REDIS_TLS;
    assert.throws(() => assertProductionRedisTls(), /plaintext|rediss/i);
  });

  it('production rejects plaintext REDIS_URL', () => {
    process.env.APP_ENV = 'production';
    delete process.env.REDIS_HOST;
    process.env.REDIS_URL = 'redis://cache.example:6379';
    process.env.REDIS_TLS = 'true';
    assert.throws(() => assertProductionRedisTls(), /REDIS_URL|plaintext/i);
  });

  it('production allows rediss:// or TLS default with hostname', () => {
    process.env.APP_ENV = 'production';
    process.env.REDIS_HOST = 'rediss://cache.example:6380';
    assert.doesNotThrow(() => assertProductionRedisTls());

    process.env.REDIS_HOST = 'cache.internal';
    process.env.REDIS_TLS = 'true';
    assert.doesNotThrow(() => assertProductionRedisTls());
  });

  it('staging skips Redis TLS enforcement', () => {
    process.env.APP_ENV = 'staging';
    process.env.REDIS_TLS = 'false';
    process.env.REDIS_HOST = 'redis://127.0.0.1:6379';
    assert.doesNotThrow(() => assertProductionRedisTls());
  });
});

describe('assertProductionOtpHmacOnly', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
  });

  afterEach(() => {
    process.env = original;
  });

  it('production rejects ALLOW_LEGACY_UNSALTED_OTP_HASH', () => {
    process.env.APP_ENV = 'production';
    process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
    assert.throws(() => assertProductionOtpHmacOnly(), /ALLOW_LEGACY_UNSALTED_OTP_HASH/);
  });

  it('staging allows legacy OTP flag', () => {
    process.env.APP_ENV = 'staging';
    process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
    assert.doesNotThrow(() => assertProductionOtpHmacOnly());
  });
});
