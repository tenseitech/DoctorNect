'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  setAdminAuthForTesting,
  resetFirebaseAdminForTesting,
} = require('../src/firebase_revocation');
const { assertGatewayProductionRuntime } = require('../src/assert_gateway_production_runtime');

const savedEnvKeys = [
  'APP_ENV',
  'NODE_ENV',
  'DISABLE_FIREBASE_ADMIN_INIT',
  'FIREBASE_REVOCATION_CHECK',
  'RATE_LIMIT_REDIS_URL',
  'REDIS_URL',
  'SKIP_GATEWAY_PROD_ASSERT',
];

function snapshotEnv() {
  const snap = {};
  for (const key of savedEnvKeys) {
    snap[key] = process.env[key];
  }
  return snap;
}

let env0 = snapshotEnv();

beforeEach(() => {
  for (const [key, value] of Object.entries(env0)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
  resetFirebaseAdminForTesting();
});

afterEach(() => {
  env0 = snapshotEnv();
  resetFirebaseAdminForTesting();
});

describe('assertGatewayProductionRuntime (SEC-04)', () => {
  it('no-op in non-production', async () => {
    process.env.APP_ENV = 'staging';
    await assert.doesNotReject(() => assertGatewayProductionRuntime());
  });

  it('fails closed when production requires Admin but ADC unavailable', async () => {
    process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
    process.env.APP_ENV = 'production';
    process.env.FIREBASE_REVOCATION_CHECK = 'true';
    delete process.env.RATE_LIMIT_REDIS_URL;
    await assert.rejects(
      () => assertGatewayProductionRuntime(),
      /Firebase Admin is unavailable/,
    );
  });

  it('fails closed when production Redis is unreachable', async () => {
    process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
    setAdminAuthForTesting({ verifyIdToken: async () => ({}) });
    process.env.APP_ENV = 'production';
    process.env.RATE_LIMIT_REDIS_URL = 'redis://127.0.0.1:6399';
    await assert.rejects(
      () => assertGatewayProductionRuntime(),
      /RATE_LIMIT_REDIS_URL is unreachable/,
    );
  });

  it('passes when production Admin mock is available and redis check skipped', async () => {
    process.env.NODE_ENV = 'production';
    process.env.SKIP_GATEWAY_PROD_ASSERT = 'true';
    setAdminAuthForTesting({ verifyIdToken: async () => ({}) });
    await assert.doesNotReject(() => assertGatewayProductionRuntime());
  });
});