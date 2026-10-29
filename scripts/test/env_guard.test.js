'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');
const { getEnv } = require('../lib/env_loader');

// Helper to intercept process.exit during guard assertions
function runWithArgs(args, fn) {
  const originalArgs = process.argv;
  const originalExit = process.exit;
  const originalError = console.error;
  let exitCode = null;
  const errors = [];

  try {
    process.argv = ['node', 'script.js', ...args];
    process.exit = (code) => {
      exitCode = code;
      throw new Error(`PROCESS_EXIT_${code}`);
    };
    console.error = (...msgs) => {
      errors.push(msgs.join(' '));
    };

    const result = fn();
    return { result, exitCode: null, errors };
  } catch (err) {
    if (err.message.startsWith('PROCESS_EXIT_')) {
      return { result: null, exitCode, errors };
    }
    throw err;
  } finally {
    process.argv = originalArgs;
    process.exit = originalExit;
    console.error = originalError;
  }
}

test('env_guard: getHostFingerprint parses URIs and bare hostnames', () => {
  assert.equal(getHostFingerprint('postgresql://user:pass@db.example.com:5432/mydb'), 'db.example.com');
  assert.equal(getHostFingerprint('db.example.com:5432'), 'db.example.com');
  assert.equal(getHostFingerprint('db.example.com'), 'db.example.com');
  assert.equal(getHostFingerprint(''), '');
});

test('env_guard: Refusal (a) - refuses production/RDS target without --confirm=<host>', () => {
  const prodHost = getEnv('PROD_RDS_HOST') || 'prod-db.example.com';
  const prodFingerprint = getHostFingerprint(prodHost);

  // 1. Missing --confirm entirely
  const run1 = runWithArgs(['--target=production'], () => {
    assertDatabaseGuard({ targetKind: 'production', operationName: 'Test Production' });
  });
  assert.equal(run1.exitCode, 1, 'Should exit with code 1 when --confirm is missing');
  assert.ok(run1.errors.some(e => e.includes('Must explicitly confirm the exact RDS host matching fingerprint')));

  // 2. Mismatched --confirm host
  const run2 = runWithArgs(['--target=production', '--confirm=wrong-host.rds.amazonaws.com'], () => {
    assertDatabaseGuard({ targetKind: 'production', operationName: 'Test Production' });
  });
  assert.equal(run2.exitCode, 1, 'Should exit with code 1 when --confirm has wrong host');
  assert.ok(run2.errors.some(e => e.includes('Must explicitly confirm the exact RDS host matching fingerprint')));

  // 3. Positive: correct --confirm passes
  const run3 = runWithArgs(['--target=production', `--confirm=${prodFingerprint}`], () => {
    return assertDatabaseGuard({ targetKind: 'production', operationName: 'Test Production' });
  });
  assert.equal(run3.exitCode, null, 'Should not exit when valid --confirm is provided');
  assert.equal(run3.result.targetKind, 'production');
  assert.equal(run3.result.host, prodFingerprint);
});

test('env_guard: Refusal (b) - refuses any host not matching the staging fingerprint', () => {
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const stagingFingerprint = getHostFingerprint(stagingUrl);

  // 1. Passing mismatched candidate targetHost in options
  const run1 = runWithArgs([], () => {
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'Test Staging', targetHost: 'unauthorized-host.supabase.co' });
  });
  assert.equal(run1.exitCode, 1, 'Should exit with code 1 when targetHost does not match staging fingerprint');
  assert.ok(run1.errors.some(e => e.includes('does not match staging fingerprint')));

  // 2. Passing mismatched --host CLI argument
  const run2 = runWithArgs(['--host=evil-staging.supabase.co'], () => {
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'Test Staging' });
  });
  assert.equal(run2.exitCode, 1, 'Should exit with code 1 when --host does not match staging fingerprint');
  assert.ok(run2.errors.some(e => e.includes('does not match staging fingerprint')));

  // 3. Positive: matching host or default staging target passes
  const run3 = runWithArgs([], () => {
    return assertDatabaseGuard({ targetKind: 'staging', operationName: 'Test Staging' });
  });
  assert.equal(run3.exitCode, null, 'Should not exit when valid staging is targeted');
  assert.equal(run3.result.targetKind, 'staging');
  assert.equal(run3.result.host, stagingFingerprint);
});

