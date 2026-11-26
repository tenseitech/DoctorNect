'use strict';

/**
 * Hermetic Node test harness: scrub inherited shell / CI env and block repo-root `.env`
 * bootstrap (`bootstrap_root_env.js` no-ops when DOCTORNECT_TEST_HARNESS=1).
 *
 * Loaded via `node --require` before any application code or test files.
 */

const HARNESS_FLAG = 'DOCTORNECT_TEST_HARNESS';

/** Prefixes for deploy/runtime keys that must never leak into unit tests. */
const SCRUB_PREFIXES = [
  'DEMO_',
  'REVIEW_',
  'STAGING_',
  'PROD_',
  'REDIS_',
  'S3_',
  'AWS_',
  'SUPABASE_',
  'FIREBASE_',
  'RAZORPAY_',
  'MSG91_',
  'OTP_',
  'SUPER_ADMIN_',
  'FIRESTORE_',
  'PG_POOL_',
  'PGRST_',
  'DATABASE_',
  'REPLAY_',
  'LOCAL_FRESH_',
  'FRESH_LOCAL_',
  'VPC_',
  'RATE_LIMIT_',
  'ENABLE_',
  'ENFORCE_',
  'FORCE_',
  'SKIP_',
  'ALLOW_',
  'USE_S3',
  'USE_SUPABASE',
];

/** Exact keys (no prefix) to scrub before applying test defaults. */
const SCRUB_EXACT = new Set([
  'APP_ENV',
  'DATABASE_URL',
  'TRUSTED_PROXY_HOPS',
  'NODE_EXTRA_CA_CERTS',
  'AWS_PROFILE',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_SESSION_TOKEN',
  'AWS_REGION',
  'AWS_DEFAULT_REGION',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'FIREBASE_CONFIG',
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'RUNTIME_DOCUMENT_DB_FORBIDDEN',
  'GCLOUD_PROJECT',
  'GCP_PROJECT',
  'GOOGLE_CLOUD_PROJECT',
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_PASSWORD',
  'REDIS_TLS',
  'REDIS_CA_CERT',
  'REDIS_CA_PATH',
  'MSG91_AUTH_KEY',
  'MSG91_AUTHKEY',
  'AUTH_KEY',
  'S3_BUCKET',
  'S3_URL_CACHE',
]);

const PRODUCTION_PROJECT_ID = 'medibond-45fad';
const TEST_GCP_PROJECT = 'demo-doctornect-test';

const TEST_DEFAULTS = {
  S3_BUCKET: 'unit-test-s3-bucket',
  S3_BUCKET_STAGING: 'unit-test-s3-bucket',
  S3_BUCKET_PRODUCTION: 'unit-test-s3-bucket-production',
  REDIS_HOST_STAGING: '127.0.0.1',
  OTP_REDIS_MIRROR: 'off',
  USE_S3_STORAGE: 'false',
  ENABLE_SUPABASE_SYNC: '0',
  FORCE_ENABLE_SUPABASE_SYNC_IN_PROD: '0',
  FIRESTORE_FORBIDDEN: '1',
};

function shouldScrubKey(name) {
  if (SCRUB_EXACT.has(name)) return true;
  if (name === HARNESS_FLAG) return false;
  return SCRUB_PREFIXES.some((prefix) => name.startsWith(prefix));
}

function scrubInheritedEnv() {
  for (const key of Object.keys(process.env)) {
    if (shouldScrubKey(key)) {
      delete process.env[key];
    }
  }
}

function applyTestDefaults() {
  process.env[HARNESS_FLAG] = '1';
  process.env.NODE_ENV = 'test';
  process.env.APP_ENV = 'test';
  for (const [key, value] of Object.entries(TEST_DEFAULTS)) {
    process.env[key] = value;
  }
  process.env.GCLOUD_PROJECT = TEST_GCP_PROJECT;
  process.env.GOOGLE_CLOUD_PROJECT = TEST_GCP_PROJECT;
  process.env.GCP_PROJECT = TEST_GCP_PROJECT;
  process.env.FIREBASE_AUTH_EMULATOR_HOST =
    process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  delete process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;
}

function assertHermeticAppEnv() {
  const appEnv = String(process.env.APP_ENV || '').trim().toLowerCase();
  if (appEnv !== 'test') {
    const err = new Error(
      `Test harness: APP_ENV must be "test" during unit tests (saw "${appEnv || '(empty)'}"). ` +
        'Shell or .env pollution bypassed scrub — fix test_harness_env.js.',
    );
    err.code = 'TEST_APP_ENV_LEAK';
    throw err;
  }
}

function assertNoLiveDeployTargets() {
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

  if (process.env.AWS_ACCESS_KEY_ID || process.env.AWS_SECRET_ACCESS_KEY || process.env.AWS_PROFILE) {
    violations.push('AWS credentials/profile in environment');
  }

  if (process.env.NODE_EXTRA_CA_CERTS) {
    violations.push('NODE_EXTRA_CA_CERTS inherited from shell');
  }

  if (violations.length) {
    const err = new Error(
      `Test harness refused to start: live deploy targets detected (${violations.join(', ')}). ` +
        'Unset shell/.env inheritance or extend test_harness_env.js scrub rules.',
    );
    err.code = 'TEST_ENV_CONTAMINATION';
    throw err;
  }
}

/**
 * Full hermetic activation for Node test runners (`--require` entry).
 */
function activateTestHarness() {
  scrubInheritedEnv();
  applyTestDefaults();
  assertHermeticAppEnv();
  assertNoLiveDeployTargets();
}

module.exports = {
  HARNESS_FLAG,
  SCRUB_PREFIXES,
  SCRUB_EXACT,
  activateTestHarness,
  assertHermeticAppEnv,
  scrubInheritedEnv,
  applyTestDefaults,
  assertNoLiveDeployTargets,
  TEST_GCP_PROJECT,
};