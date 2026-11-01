'use strict';

const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { assertConfirmLiveData, hostHash8 } = require('../lib/live_data_guard');

function runWithArgs(args, fn) {
  const originalArgs = process.argv;
  const originalExit = process.exit;
  const originalError = console.error;
  let exitCode = null;
  let stderr = '';

  try {
    process.argv = ['node', 'migrate.js', ...args];
    process.exit = (code) => {
      exitCode = code;
      throw new Error(`PROCESS_EXIT_${code}`);
    };
    console.error = (msg) => {
      stderr += String(msg);
    };
    const result = fn();
    return { result, exitCode: null, stderr };
  } catch (err) {
    if (err.message.startsWith('PROCESS_EXIT_')) {
      return { result: null, exitCode, stderr };
    }
    throw err;
  } finally {
    process.argv = originalArgs;
    process.exit = originalExit;
    console.error = originalError;
  }
}

test('live_data_guard: hostHash8 is deterministic 8-char uppercase hex', () => {
  const h = hostHash8('example.supabase.co');
  assert.match(h, /^[0-9A-F]{8}$/);
  assert.equal(h, hostHash8('example.supabase.co'));
});

test('live_data_guard: refusal prints hash and script name only', () => {
  const prev = {
    STAGING_SUPABASE_URL: process.env.STAGING_SUPABASE_URL,
    SUPABASE_URL: process.env.SUPABASE_URL,
  };
  process.env.STAGING_SUPABASE_URL = 'https://example.supabase.co';
  delete process.env.SUPABASE_URL;

  try {
    const expectedHash = hostHash8('example.supabase.co');
    const run = runWithArgs([], () => {
      assertConfirmLiveData('scripts/db/migrate.js');
    });
    assert.equal(run.exitCode, 1);
    assert.equal(run.stderr.trim(), `${expectedHash} scripts/db/migrate.js`);
  } finally {
    if (prev.STAGING_SUPABASE_URL === undefined) delete process.env.STAGING_SUPABASE_URL;
    else process.env.STAGING_SUPABASE_URL = prev.STAGING_SUPABASE_URL;
    if (prev.SUPABASE_URL === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = prev.SUPABASE_URL;
  }
});

test('live_data_guard: --confirm-live-data enables non-dry-run only with --execute', () => {
  const prevUrl = process.env.STAGING_SUPABASE_URL;
  const prevAllow = process.env.DOCTORNECT_ALLOWED_HOST_HASHES;
  const allowFile = path.join(require('os').tmpdir(), `doctornect-allow-${Date.now()}.txt`);
  process.env.STAGING_SUPABASE_URL = 'https://example.supabase.co';
  fs.writeFileSync(allowFile, `${hostHash8('example.supabase.co')}\n`);
  process.env.DOCTORNECT_ALLOWED_HOST_HASHES = allowFile;
  try {
    const dry = runWithArgs(['--confirm-live-data'], () =>
      assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(dry.exitCode, null);
    assert.equal(dry.result.dryRun, true);

    const execRun = runWithArgs(['--confirm-live-data', '--execute'], () =>
      assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(execRun.exitCode, null);
    assert.equal(execRun.result.dryRun, false);
  } finally {
    if (prevUrl === undefined) delete process.env.STAGING_SUPABASE_URL;
    else process.env.STAGING_SUPABASE_URL = prevUrl;
    if (prevAllow === undefined) delete process.env.DOCTORNECT_ALLOWED_HOST_HASHES;
    else process.env.DOCTORNECT_ALLOWED_HOST_HASHES = prevAllow;
    try {
      fs.unlinkSync(allowFile);
    } catch (_) {}
  }
});
