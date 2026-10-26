'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { getDatabaseClient, resetDatabaseClientForTesting } = require('../src/db/client');

describe('DatabaseClient Abstraction (Cloud Functions)', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    resetDatabaseClientForTesting();
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    resetDatabaseClientForTesting();
    process.env = { ...originalEnv };
  });

  it('throws helpful error if required staging environment variables are missing', () => {
    process.env.APP_ENV = 'staging';
    delete process.env.STAGING_SUPABASE_URL;
    delete process.env.SUPABASE_URL;
    delete process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;

    assert.throws(
      () => getDatabaseClient(),
      /Missing required credentials for APP_ENV="staging": STAGING_SUPABASE_URL, STAGING_SUPABASE_SERVICE_ROLE_KEY/
    );
  });

  it('throws helpful error if required production environment variables are missing', () => {
    process.env.APP_ENV = 'production';
    delete process.env.PROD_GATEWAY_URL;
    delete process.env.PROD_GATEWAY_SERVICE_KEY;

    assert.throws(
      () => getDatabaseClient(),
      /Missing required credentials for APP_ENV="production": PROD_GATEWAY_URL, PROD_GATEWAY_SERVICE_KEY/
    );
  });

  it('initializes staging client using STAGING_SUPABASE_* variables', () => {
    process.env.APP_ENV = 'staging';
    process.env.STAGING_SUPABASE_URL = 'https://staging.supabase.co';
    process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY = 'test-staging-service-key-at-least-thirty-two-chars-long';

    const client = getDatabaseClient();
    assert.ok(client);
    assert.strictEqual(typeof client.from, 'function');
    assert.strictEqual(typeof client.rpc, 'function');

    // Verify singleton caching
    const client2 = getDatabaseClient();
    assert.strictEqual(client, client2);
  });

  it('initializes production client using PROD_GATEWAY_* variables', () => {
    process.env.APP_ENV = 'production';
    process.env.PROD_GATEWAY_URL = 'https://api.doctornect.com';
    process.env.PROD_GATEWAY_SERVICE_KEY = 'test-prod-service-key-at-least-thirty-two-chars-long';

    const client = getDatabaseClient();
    assert.ok(client);
    assert.strictEqual(typeof client.from, 'function');
    assert.strictEqual(typeof client.rpc, 'function');
  });

  it('switches client when APP_ENV changes after cache reset', () => {
    process.env.APP_ENV = 'staging';
    process.env.STAGING_SUPABASE_URL = 'https://staging.supabase.co';
    process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY = 'staging-key-test-value-12345678901234567890';
    const stagingClient = getDatabaseClient();

    resetDatabaseClientForTesting();
    process.env.APP_ENV = 'production';
    process.env.PROD_GATEWAY_URL = 'https://gateway.doctornect.com';
    process.env.PROD_GATEWAY_SERVICE_KEY = 'prod-key-test-value-12345678901234567890';
    const prodClient = getDatabaseClient();

    assert.notStrictEqual(stagingClient, prodClient);
  });
});
