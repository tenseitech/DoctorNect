'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');
const {
  parseEnvExampleKeys,
  extractJsEnvVars,
  extractDartEnvVars,
  LEGACY_ALIASES,
  TEST_ONLY_VARS,
  DEV_SCRIPT_VARS,
} = require('../../../scripts/check_env_parity');

test('ENV-01: parseEnvExampleKeys reads variable names from root .env.example', () => {
  const rootExample = path.resolve(__dirname, '../../../.env.example');
  assert.ok(fs.existsSync(rootExample), 'Root .env.example must exist');

  const keys = parseEnvExampleKeys(rootExample);
  assert.ok(keys.has('USE_SUPABASE_DB_DOCTOR_PATIENT'), 'USE_SUPABASE_DB_DOCTOR_PATIENT must be in root .env.example');
  assert.ok(keys.has('AWS_ACCESS_KEY_ID'), 'AWS_ACCESS_KEY_ID must be in root .env.example');
  assert.ok(keys.has('AWS_SECRET_ACCESS_KEY'), 'AWS_SECRET_ACCESS_KEY must be in root .env.example');
  assert.ok(keys.has('RAZORPAY_WEBHOOK_SECRET'), 'RAZORPAY_WEBHOOK_SECRET must be in root .env.example');
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
    content.includes('production mein Secret Manager se bind hota hai'),
    'Functions .env.example must note Secret Manager binding for placeholders'
  );

  const rootExample = path.resolve(__dirname, '../../../.env.example');
  const rootContent = fs.readFileSync(rootExample, 'utf8');
  assert.ok(
    rootContent.includes('production mein Secret Manager se bind hota hai'),
    'Root .env.example must note Secret Manager binding for placeholders'
  );
});

test('ENV-01: .env files are NOT tracked in git', () => {
  const gitIgnorePath = path.resolve(__dirname, '../../../.gitignore');
  const gitIgnore = fs.readFileSync(gitIgnorePath, 'utf8');
  assert.ok(gitIgnore.includes('.env'), '.gitignore must exclude .env files');
});
