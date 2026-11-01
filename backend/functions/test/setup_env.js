'use strict';

/**
 * Default `npm test` harness: isolated from deploy/local `.env` (Firebase deploy loads
 * that file; unit tests must not inherit live Redis, Supabase, S3, or Auth credentials).
 */

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.APP_ENV = process.env.APP_ENV || 'test';

const TEST_DEFAULTS = {
  S3_BUCKET: 'unit-test-s3-bucket',
  OTP_REDIS_MIRROR: 'off',
  USE_S3_STORAGE: 'false',
  ENABLE_SUPABASE_SYNC: '0',
  FORCE_ENABLE_SUPABASE_SYNC_IN_PROD: '0',
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
  'GCLOUD_PROJECT',
  'GCP_PROJECT',
];

for (const key of STRIP_KEYS) {
  delete process.env[key];
}

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
