'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');
const { parseEnvExampleKeys, checkEnvParity, ENV_CONCEPT_GROUPS } = require('../../../scripts/check_env_parity');

test('ENV-01: root .env.example is an index (no duplicate runtime keys)', () => {
  const rootExample = path.resolve(__dirname, '../../../.env.example');
  assert.ok(fs.existsSync(rootExample), 'Root .env.example must exist');
  const keys = parseEnvExampleKeys(rootExample);
  assert.strictEqual(keys.size, 0, 'Root .env.example must not declare runtime keys (index only)');
  const content = fs.readFileSync(rootExample, 'utf8');
  assert.ok(content.includes('frontend/.env.example'), 'Root index must point to frontend template');
  assert.ok(content.includes('backend/functions/.env.example'), 'Root index must point to functions template');
});

test('ENV-01: parseEnvExampleKeys reads variable names from functions .env.example', () => {
  const fnExample = path.resolve(__dirname, '../.env.example');
  assert.ok(fs.existsSync(fnExample), 'Functions .env.example must exist');

  const keys = parseEnvExampleKeys(fnExample);
  assert.ok(keys.has('USE_SUPABASE_DB_DOCTOR_PATIENT'), 'USE_SUPABASE_DB_DOCTOR_PATIENT must be in functions .env.example');
  assert.ok(keys.has('AWS_ACCESS_KEY_ID'), 'AWS_ACCESS_KEY_ID must be in functions .env.example');
  assert.ok(keys.has('AWS_SECRET_ACCESS_KEY'), 'AWS_SECRET_ACCESS_KEY must be in functions .env.example');
  assert.ok(keys.has('RAZORPAY_WEBHOOK_SECRET'), 'RAZORPAY_WEBHOOK_SECRET must be in functions .env.example');
});

test('ENV-01: .env.example placeholders document Secret Manager comments', () => {
  const fnExample = path.resolve(__dirname, '../.env.example');
  const content = fs.readFileSync(fnExample, 'utf8');

  assert.ok(
    content.includes('Secret Manager'),
    'Functions .env.example must note Secret Manager binding for placeholders'
  );
});

test('ENV-01: check_env_parity.js passes (no duplicate S3 concept names in examples)', () => {
  const prev = process.exitCode;
  process.exitCode = 0;
  checkEnvParity();
  assert.strictEqual(process.exitCode || 0, 0, 'check_env_parity must exit 0');
  process.exitCode = prev;
});

test('ENV-01: S3 concept group forbids alias keys in example templates', () => {
  const s3 = ENV_CONCEPT_GROUPS.find((g) => g.canonical === 'S3_BUCKET');
  assert.ok(s3);
  const templates = [
    path.resolve(__dirname, '../../../frontend/.env.example'),
    path.resolve(__dirname, '../.env.example'),
    path.resolve(__dirname, '../../../backend/.env.migration.example'),
  ];
  for (const abs of templates) {
    const keys = parseEnvExampleKeys(abs);
    for (const alias of s3.aliases) {
      assert.ok(!keys.has(alias), `${alias} must not appear in ${path.basename(abs)}`);
    }
  }
  const fnKeys = parseEnvExampleKeys(path.resolve(__dirname, '../.env.example'));
  assert.ok(fnKeys.has('S3_BUCKET'), 'functions .env.example must document S3_BUCKET');
});

test('ENV-01: .env files are NOT tracked in git', () => {
  const gitIgnorePath = path.resolve(__dirname, '../../../.gitignore');
  const gitIgnore = fs.readFileSync(gitIgnorePath, 'utf8');
  assert.ok(gitIgnore.includes('.env'), '.gitignore must exclude .env files');
});
