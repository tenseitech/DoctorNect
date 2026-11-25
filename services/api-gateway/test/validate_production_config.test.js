'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertGatewayProductionConfig,
  KNOWN_DEFAULT_JWT_SECRET,
} = require('../src/validate_production_config');

const env0 = { ...process.env };

beforeEach(() => {
  process.env = { ...env0 };
  delete process.env.RATE_LIMIT_ALLOW_IN_MEMORY;
  process.env.FIREBASE_REVOCATION_CHECK = 'true';
});

afterEach(() => {
  process.env = env0;
});

describe('validate_production_config (SEC-03, SEC-12, SEC-08)', () => {
  it('rejects default JWT secret in production', () => {
    process.env.APP_ENV = 'production';
    process.env.PGRST_JWT_SECRET = KNOWN_DEFAULT_JWT_SECRET;
    process.env.SERVICE_ROLE_KEY = 'prod-service-key-32chars-minimum-ok';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6379';
    assert.throws(() => assertGatewayProductionConfig(), /PGRST_JWT_SECRET/);
  });

  it('accepts unique secrets and redis in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.PGRST_JWT_SECRET = 'unique-prod-jwt-secret-minimum-32-chars';
    process.env.SERVICE_ROLE_KEY = 'prod-service-key-32chars-minimum-ok';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6379';
    assert.doesNotThrow(() => assertGatewayProductionConfig());
  });

  it('rejects RATE_LIMIT_ALLOW_IN_MEMORY in production', () => {
    process.env.APP_ENV = 'production';
    process.env.FIREBASE_REVOCATION_CHECK = 'true';
    process.env.PGRST_JWT_SECRET = 'unique-prod-jwt-secret-minimum-32-chars';
    process.env.SERVICE_ROLE_KEY = 'prod-service-key-32chars-minimum-ok';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6379';
    process.env.RATE_LIMIT_ALLOW_IN_MEMORY = 'true';
    assert.throws(() => assertGatewayProductionConfig(), /RATE_LIMIT_ALLOW_IN_MEMORY/);
  });

  it('rejects FIREBASE_REVOCATION_CHECK=false in production', () => {
    process.env.APP_ENV = 'production';
    process.env.PGRST_JWT_SECRET = 'unique-prod-jwt-secret-minimum-32-chars';
    process.env.SERVICE_ROLE_KEY = 'prod-service-key-32chars-minimum-ok';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6379';
    process.env.FIREBASE_REVOCATION_CHECK = 'false';
    assert.throws(() => assertGatewayProductionConfig(), /FIREBASE_REVOCATION_CHECK/);
  });

  it('rejects demo UID prefix routing in production', () => {
    process.env.APP_ENV = 'production';
    process.env.PGRST_JWT_SECRET = 'unique-prod-jwt-secret-minimum-32-chars';
    process.env.SERVICE_ROLE_KEY = 'prod-service-key-32chars-minimum-ok';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6379';
    process.env.DEMO_UID_PREFIX_ROUTING = '1';
    assert.throws(() => assertGatewayProductionConfig(), /DEMO_UID_PREFIX_ROUTING/);
  });
});