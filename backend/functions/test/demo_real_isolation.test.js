'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  getDatabaseClient,
  resetDatabaseClientForTesting,
  getRedisNamespaceForCallable,
} = require('../src/db/client');

const env0 = { ...process.env };

beforeEach(() => {
  resetDatabaseClientForTesting();
  process.env = {
    ...env0,
    APP_ENV: 'production',
    DEMO_REAL_ROUTING_ENABLED: '1',
    DEMO_FIREBASE_UID_ALLOWLIST: 'demo_patient_uid',
    PROD_GATEWAY_URL: 'https://gateway.example.com',
    PROD_GATEWAY_SERVICE_KEY: 'gateway-service-key-min-20-chars',
    DEMO_SUPABASE_URL: 'https://demo-project.supabase.co',
    DEMO_SUPABASE_SERVICE_ROLE_KEY: 'demo-supabase-service-key-min20',
    STAGING_SUPABASE_URL: 'https://staging-project.supabase.co',
    STAGING_SUPABASE_SERVICE_ROLE_KEY: 'staging-key-should-not-be-used',
  };
});

afterEach(() => {
  resetDatabaseClientForTesting();
  process.env = env0;
});

test('real user callable routes to PROD_GATEWAY client', () => {
  const client = getDatabaseClient({ firebaseUid: 'real_firebase_uid' });
  assert.match(client.supabaseUrl, /gateway\.example\.com/);
});

test('demo allowlisted uid routes to DEMO_SUPABASE_URL', () => {
  const client = getDatabaseClient({ firebaseUid: 'demo_patient_uid' });
  assert.match(client.supabaseUrl, /demo-project\.supabase\.co/);
});

test('ambiguous uid routes to RDS (fail-closed default)', () => {
  const client = getDatabaseClient({ firebaseUid: null });
  assert.match(client.supabaseUrl, /gateway\.example\.com/);
});

test('redis namespace segregates demo vs real', () => {
  const demoNs = getRedisNamespaceForCallable({ auth: { uid: 'demo_patient_uid' } });
  const realNs = getRedisNamespaceForCallable({ auth: { uid: 'real_uid' } });
  assert.equal(demoNs, 'demo:');
  assert.equal(realNs, 'real:');
});