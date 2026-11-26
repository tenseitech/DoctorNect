'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');

const {
  isProductionAppEnv,
  isProductionBootRequiresDatabaseUrl,
  resolveStagingDatabaseUrl,
  getPgPool,
  assertProductionPgPoolConfigOrThrow,
  resolveProductionPoolConfig,
  looksLikeSupabaseDatabaseUrl,
  PRODUCTION_PG_CONFIG_ERROR,
  _resetPgPoolForTests,
} = require('../src/db/pg_pool');

function snapshotEnv(keys) {
  const snap = {};
  for (const k of keys) snap[k] = process.env[k];
  return snap;
}

function restoreEnv(snap) {
  for (const [k, v] of Object.entries(snap)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
}

const ENV_KEYS = [
  'APP_ENV',
  'STAGING_SUPABASE_DB_URL',
  'SUPABASE_DB_URL',
  'DATABASE_URL',
  'PROD_RDS_HOST',
  'PROD_RDS_CONNECT_HOST',
  'PROD_RDS_PORT',
  'PROD_RDS_PASSWORD',
  'PROD_RDS_SSL_ROOT_CERT',
];

beforeEach(() => {
  _resetPgPoolForTests();
});

afterEach(() => {
  _resetPgPoolForTests();
});

test('pg_pool: staging resolves STAGING_SUPABASE_DB_URL before generic DATABASE_URL', () => {
  const snap = snapshotEnv(ENV_KEYS);
  process.env.APP_ENV = 'staging';
  process.env.STAGING_SUPABASE_DB_URL = 'postgresql://staging-only';
  process.env.DATABASE_URL = 'postgresql://generic';
  try {
    assert.equal(resolveStagingDatabaseUrl(), 'postgresql://staging-only');
    assert.equal(isProductionAppEnv(), false);
  } finally {
    restoreEnv(snap);
  }
});

test('pg_pool: production boot does not require DATABASE_URL (gateway-only deploy)', () => {
  assert.equal(isProductionBootRequiresDatabaseUrl(), false);
});

test('pg_pool: production APP_ENV detected', () => {
  const snap = snapshotEnv(['APP_ENV']);
  process.env.APP_ENV = 'production';
  try {
    assert.equal(isProductionAppEnv(), true);
  } finally {
    restoreEnv(snap);
  }
});

test('pg_pool: production + only Supabase DATABASE_URL throws', () => {
  const snap = snapshotEnv(ENV_KEYS);
  process.env.APP_ENV = 'production';
  delete process.env.PROD_RDS_PASSWORD;
  delete process.env.PROD_RDS_PORT;
  delete process.env.PROD_RDS_HOST;
  process.env.DATABASE_URL =
    'postgresql://postgres.foo:secret@aws-0-ap-south-1.pooler.supabase.com:5432/postgres';
  try {
    assert.throws(
      () => assertProductionPgPoolConfigOrThrow(),
      (err) => err.code === PRODUCTION_PG_CONFIG_ERROR,
    );
    assert.throws(
      () => getPgPool(),
      (err) => err.code === PRODUCTION_PG_CONFIG_ERROR,
    );
  } finally {
    restoreEnv(snap);
  }
});

test('pg_pool: production with only STAGING_SUPABASE_DB_URL and no RDS creds throws', () => {
  const snap = snapshotEnv(ENV_KEYS);
  process.env.APP_ENV = 'production';
  delete process.env.DATABASE_URL;
  process.env.STAGING_SUPABASE_DB_URL =
    'postgresql://postgres.foo:secret@aws-0-ap-south-1.pooler.supabase.com:5432/postgres';
  try {
    assert.throws(
      () => assertProductionPgPoolConfigOrThrow(),
      (err) => err.code === PRODUCTION_PG_CONFIG_ERROR,
    );
    assert.throws(() => getPgPool(), (err) => err.code === PRODUCTION_PG_CONFIG_ERROR);
  } finally {
    restoreEnv(snap);
  }
});

test('pg_pool: looksLikeSupabaseDatabaseUrl detects pooler host', () => {
  assert.equal(
    looksLikeSupabaseDatabaseUrl(
      'postgresql://u:p@aws-0-ap-south-1.pooler.supabase.com:5432/postgres',
    ),
    true,
  );
  assert.equal(
    looksLikeSupabaseDatabaseUrl(
      'postgresql://u:p@example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com:5432/doctornect',
    ),
    false,
  );
});

test('pg_pool: production RDS pool config uses CA and rejectUnauthorized true', () => {
  const snap = snapshotEnv(ENV_KEYS);
  const caPath = require('path').resolve(
    __dirname,
    '../../../infra/aws/global-bundle.pem',
  );
  if (!require('fs').existsSync(caPath)) {
    return;
  }
  process.env.APP_ENV = 'production';
  delete process.env.DATABASE_URL;
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  process.env.PROD_RDS_CONNECT_HOST = '127.0.0.1';
  process.env.PROD_RDS_PORT = '5433';
  process.env.PROD_RDS_PASSWORD = 'test-password-not-real';
  process.env.PROD_RDS_SSL_ROOT_CERT = caPath;
  process.env.PROD_RDS_SSL_SERVERNAME = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  // Hermetic: do not inherit a developer .env sslmode.
  const prevSslMode = process.env.PROD_RDS_SSLMODE;
  process.env.PROD_RDS_SSLMODE = 'verify-full';
  try {
    const cfg = resolveProductionPoolConfig();
    assert.ok(cfg.ssl, 'RDS config must include ssl');
    assert.notEqual(cfg.ssl.rejectUnauthorized, false);
    assert.ok(cfg.ssl.ca && cfg.ssl.ca.length > 0, 'RDS ssl must load CA bundle');
  } finally {
    if (prevSslMode === undefined) delete process.env.PROD_RDS_SSLMODE;
    else process.env.PROD_RDS_SSLMODE = prevSslMode;
    restoreEnv(snap);
  }
});

test('pg_pool: production refuses PROD_RDS_SSLMODE=require (no cert verification)', () => {
  const snap = snapshotEnv(ENV_KEYS);
  const caPath = require('path').resolve(__dirname, '../../../infra/aws/global-bundle.pem');
  if (!require('fs').existsSync(caPath)) {
    return;
  }
  process.env.APP_ENV = 'production';
  delete process.env.DATABASE_URL;
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  process.env.PROD_RDS_CONNECT_HOST = '127.0.0.1';
  process.env.PROD_RDS_PORT = '5433';
  process.env.PROD_RDS_PASSWORD = 'test-password-not-real';
  process.env.PROD_RDS_SSL_ROOT_CERT = caPath;
  const prevSslMode = process.env.PROD_RDS_SSLMODE;
  process.env.PROD_RDS_SSLMODE = 'require';
  try {
    assert.throws(() => resolveProductionPoolConfig(), (err) => err.code === 'RDS_SSL_INSECURE');
  } finally {
    if (prevSslMode === undefined) delete process.env.PROD_RDS_SSLMODE;
    else process.env.PROD_RDS_SSLMODE = prevSslMode;
    restoreEnv(snap);
  }
});