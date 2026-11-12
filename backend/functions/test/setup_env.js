'use strict';

/**
 * Default `npm test` harness: isolated from deploy/local `.env` (Firebase deploy loads
 * that file; unit tests must not inherit live Redis, Supabase, S3, or Auth credentials).
 */

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.APP_ENV = process.env.APP_ENV || 'test';

const TEST_DEFAULTS = {
  S3_BUCKET: 'unit-test-s3-bucket',
  S3_BUCKET_STAGING: 'unit-test-s3-bucket',
  REDIS_HOST_STAGING: '127.0.0.1',
  OTP_REDIS_MIRROR: 'off',
  USE_S3_STORAGE: 'false',
  ENABLE_SUPABASE_SYNC: '0',
  FORCE_ENABLE_SUPABASE_SYNC_IN_PROD: '0',
  FIRESTORE_FORBIDDEN: '1',
};

for (const [key, value] of Object.entries(TEST_DEFAULTS)) {
  if (process.env[key] === undefined || String(process.env[key]).trim() === '') {
    process.env[key] = value;
  }
}

// Strip deploy credentials if the shell inherited them (do not load backend/functions/.env).
const STRIP_KEYS = [
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_PASSWORD',
  'REDIS_TLS',
  'REDIS_CA_CERT',
  'REDIS_CA_PATH',
  'MSG91_AUTH_KEY',
  'MSG91_AUTHKEY',
  'AUTH_KEY',
  'RAZORPAY_KEY_SECRET',
  'RAZORPAY_WEBHOOK_SECRET',
  'SUPABASE_SECRET_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_SERVICE_KEY',
  'SUPABASE_URL',
  'SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_ANON_KEY',
  'SUPABASE_JWKS_URL',
  'SUPABASE_DB_URL',
  'DATABASE_URL',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'STAGING_SUPABASE_DB_URL',
  'PROD_GATEWAY_URL',
  'PROD_GATEWAY_SERVICE_KEY',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'FIREBASE_CONFIG',
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'GCLOUD_PROJECT',
  'GCP_PROJECT',
  'GOOGLE_CLOUD_PROJECT',
];

for (const key of STRIP_KEYS) {
  delete process.env[key];
}

/** Fake Firebase / GCP project for unit tests (never medibond-45fad). */
const TEST_GCP_PROJECT = 'demo-doctornect-test';
process.env.GCLOUD_PROJECT = TEST_GCP_PROJECT;
process.env.GOOGLE_CLOUD_PROJECT = TEST_GCP_PROJECT;
process.env.GCP_PROJECT = TEST_GCP_PROJECT;
// Auth emulator target only — do not set FIRESTORE_EMULATOR_HOST (default npm test skips emulator-heavy suites).
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
delete process.env.FIRESTORE_EMULATOR_HOST;
delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;

const PRODUCTION_PROJECT_ID = 'medibond-45fad';

function assertTestEnvIsolated() {
  const violations = [];
  const haystack = Object.entries(process.env)
    .filter(([k, v]) => v && typeof v === 'string')
    .map(([k, v]) => `${k}=${v}`)
    .join('\n');

  if (haystack.includes(PRODUCTION_PROJECT_ID)) {
    violations.push(`production Firebase project id (${PRODUCTION_PROJECT_ID})`);
  }

  const supabaseUrl = String(process.env.SUPABASE_URL || process.env.STAGING_SUPABASE_URL || '').trim();
  if (supabaseUrl && !/example\.supabase\.co/i.test(supabaseUrl)) {
    violations.push('non-fixture SUPABASE_URL');
  }

  const redisHost = String(process.env.REDIS_HOST || '').trim();
  if (redisHost && redisHost !== '127.0.0.1' && redisHost !== 'localhost') {
    violations.push('non-local REDIS_HOST');
  }

  const bucket = String(process.env.S3_BUCKET || '').trim();
  if (bucket && bucket !== 'unit-test-s3-bucket' && /doctornect/i.test(bucket)) {
    violations.push('production-like S3_BUCKET name');
  }

  if (process.env.AWS_ACCESS_KEY_ID || process.env.AWS_SECRET_ACCESS_KEY) {
    violations.push('AWS access keys in environment');
  }

  if (violations.length) {
    const err = new Error(
      `Test harness refused to start: live deploy targets detected (${violations.join(', ')}). ` +
        'Unset shell/.env inheritance or fix test/setup_env.js stripping.',
    );
    err.code = 'TEST_ENV_CONTAMINATION';
    throw err;
  }
}

assertTestEnvIsolated();

/** In-memory Redis stub so registration_otp / rate-limit paths never open TCP. */
const noopRedis = {
  get: async () => null,
  set: async () => 'OK',
  del: async () => 0,
  incr: async () => 1,
  pexpire: async () => 1,
  quit: async () => {},
  disconnect() {},
  on() {
    return this;
  },
};

try {
  const { setRedisClientForTesting } = require('../redis');
  setRedisClientForTesting(noopRedis);
} catch (_) {
  // redis module optional during early bootstrap
}
