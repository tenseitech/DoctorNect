'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');
const { parseEnvExampleKeys, checkEnvParity, ENV_CONCEPT_GROUPS } = require('../../../scripts/check_env_parity');

test('ENV-01: single root .env.example documents runtime keys', () => {
  const rootExample = path.resolve(__dirname, '../../../.env.example');
  assert.ok(fs.existsSync(rootExample), 'Root .env.example must exist');
  const keys = parseEnvExampleKeys(rootExample);
  assert.ok(keys.size > 50, 'Root .env.example must declare runtime keys');
  assert.ok(keys.has('FIRESTORE_FORBIDDEN'), 'FIRESTORE_FORBIDDEN must be documented');
  assert.ok(keys.has('STAGING_SUPABASE_DB_URL'), 'STAGING_SUPABASE_DB_URL must be documented');
  assert.ok(keys.has('PROD_RDS_HOST'), 'PROD_RDS_HOST must be documented');
});

test('ENV-01: root .env.example defaults FIRESTORE_FORBIDDEN on for Postgres-only server', () => {
  const rootExample = path.resolve(__dirname, '../../../.env.example');
  const content = fs.readFileSync(rootExample, 'utf8');
  assert.match(content, /FIRESTORE_FORBIDDEN=1/m, 'template must default FIRESTORE_FORBIDDEN to 1');
});

test('ENV-01: check_env_parity.js passes', () => {
  const prev = process.exitCode;
  process.exitCode = 0;
  checkEnvParity();
  assert.strictEqual(process.exitCode || 0, 0, 'check_env_parity must exit 0');
  process.exitCode = prev;
});

test('ENV-01: S3 concept group forbids alias keys in root example', () => {
  const s3 = ENV_CONCEPT_GROUPS.find((g) => g.canonical === 'S3_BUCKET');
  assert.ok(s3);
  const keys = parseEnvExampleKeys(path.resolve(__dirname, '../../../.env.example'));
  for (const alias of s3.aliases) {
    assert.ok(!keys.has(alias), `${alias} must not appear in root .env.example`);
  }
  assert.ok(keys.has('S3_BUCKET_STAGING'));
  assert.ok(keys.has('S3_BUCKET_PRODUCTION'));
});

test('ENV-01: .env files are NOT tracked in git', () => {
  const gitIgnorePath = path.resolve(__dirname, '../../../.gitignore');
  const gitIgnore = fs.readFileSync(gitIgnorePath, 'utf8');
  assert.ok(gitIgnore.includes('.env'), '.gitignore must exclude .env files');
});
