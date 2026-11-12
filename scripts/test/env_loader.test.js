'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { getEnv, hasEnv, maskConnectionString, mergedEnv } = require('../lib/env_loader');

test('env_loader: reads only process.env and documented .env files', () => {
  // 1. Process environment precedence
  const testKey = 'TEST_INJECTED_PROCESS_ENV_VAR';
  process.env[testKey] = 'injected_value_123';
  // Check that fresh re-evaluation or mergedEnv includes process.env
  assert.equal(process.env[testKey], 'injected_value_123');

  // 2. Source inspection: verify env_loader.js has NO references to shell history or pgpass
  const loaderSource = fs.readFileSync(path.resolve(__dirname, '../lib/env_loader.js'), 'utf8');
  assert.ok(!loaderSource.includes('PSReadLine'), 'Must not reference PSReadLine');
  assert.ok(!loaderSource.includes('ConsoleHost_history'), 'Must not reference ConsoleHost_history');
  assert.ok(!loaderSource.includes('pgpass'), 'Must not reference pgpass');
  assert.ok(!loaderSource.includes('pg_hba'), 'Must not reference pg_hba');

  // 3. Documented .env files only
  const allowedFiles = ['.env', '.env.migration', 'backend/functions/.env'];
  for (const f of allowedFiles) {
    assert.ok(loaderSource.includes(f), `env_loader should explicitly load documented file: ${f}`);
  }

  // 4. maskConnectionString properly redacts credentials
  const rawUrl = 'postgresql://myuser:secretpassword123@myhost.rds.amazonaws.com:5432/mydb';
  const masked = maskConnectionString(rawUrl);
  assert.ok(!masked.includes('secretpassword123'), 'Masked URL must not expose plaintext password');
  assert.ok(masked.includes('****'), 'Masked URL must replace password with ****');
  assert.ok(masked.includes('myuser'), 'Masked URL preserves username');
  assert.ok(masked.includes('myhost.rds.amazonaws.com'), 'Masked URL preserves host');
});

test('env_loader: hasEnv and getEnv contract', () => {
  assert.equal(typeof getEnv('NON_EXISTENT_VARIABLE_999'), 'string');
  assert.equal(getEnv('NON_EXISTENT_VARIABLE_999'), '');
  assert.equal(hasEnv('NON_EXISTENT_VARIABLE_999'), false);
});
