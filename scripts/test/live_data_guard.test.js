'use strict';

const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { getHostFingerprint } = require('../lib/env_guard');
const {
  assertConfirmLiveData,
  assertConnectedDatabaseMatchesConfirm,
  hostHash8,
  formatLiveDataGuardHelp,
  describeLiveDataGuardTarget,
  resolveCliMigrationTarget,
  resolveLiveDataHostHash,
} = require('../lib/live_data_guard');

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
    const run = runWithArgs(['--target=staging'], () => {
      assertConfirmLiveData('scripts/db/migrate.js');
    });
    assert.equal(run.exitCode, 1);
    assert.ok(run.stderr.includes('staging Supabase Postgres'));
    assert.ok(run.stderr.includes('--target=staging --execute'));
    assert.ok(run.stderr.trim().endsWith(`${expectedHash} scripts/db/migrate.js`));
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

test('live_data_guard: rehearsal refusal names RDS not staging', () => {
  const prev = {
    PROD_RDS_HOST: process.env.PROD_RDS_HOST,
    STAGING_SUPABASE_URL: process.env.STAGING_SUPABASE_URL,
  };
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  delete process.env.STAGING_SUPABASE_URL;
  try {
    const expectedHash = hostHash8(process.env.PROD_RDS_HOST);
    const run = runWithArgs(['--target=rehearsal'], () => {
      assertConfirmLiveData('scripts/db/migrate.js');
    });
    assert.equal(run.exitCode, 1);
    assert.ok(run.stderr.includes('rehearsal RDS'));
    assert.ok(!run.stderr.includes('against live staging'));
    assert.ok(run.stderr.includes('--target=rehearsal'));
    assert.ok(run.stderr.trim().endsWith(`${expectedHash} scripts/db/migrate.js`));
  } finally {
    if (prev.PROD_RDS_HOST === undefined) delete process.env.PROD_RDS_HOST;
    else process.env.PROD_RDS_HOST = prev.PROD_RDS_HOST;
    if (prev.STAGING_SUPABASE_URL === undefined) delete process.env.STAGING_SUPABASE_URL;
    else process.env.STAGING_SUPABASE_URL = prev.STAGING_SUPABASE_URL;
  }
});

test('formatLiveDataGuardHelp uses spaced --target and --execute', () => {
  const stagingHelp = formatLiveDataGuardHelp('scripts/db/migrate.js', 'staging');
  const applyLine = stagingHelp.find((l) => l.startsWith('Apply (destructive):'));
  assert.equal(
    applyLine,
    'Apply (destructive): node scripts/db/migrate.js --target=staging --execute --confirm-live-data --confirm-staging',
  );
  assert.ok(stagingHelp.some((l) => l.includes('--target=staging --execute')));
  assert.ok(!stagingHelp.some((l) => l.includes('--target=staging--execute')));
  const rehearsalHelp = formatLiveDataGuardHelp('scripts/db/migrate.js', 'rehearsal');
  assert.ok(rehearsalHelp.some((l) => l.includes('--confirm=<PROD_RDS_HOST>')));
  assert.ok(rehearsalHelp.some((l) => l.includes('--confirm-db=doctornect_rehearsal')));
  const prodHelp = formatLiveDataGuardHelp('scripts/db/migrate.js', 'production');
  assert.ok(prodHelp.some((l) => l.includes('--confirm-db=doctornect')));
});

test('live_data_guard: production/rehearsal require distinct --confirm-db', () => {
  const prev = {
    PROD_RDS_HOST: process.env.PROD_RDS_HOST,
    PROD_RDS_DB: process.env.PROD_RDS_DB,
    STAGING_SUPABASE_URL: process.env.STAGING_SUPABASE_URL,
  };
  const allowFile = path.join(require('os').tmpdir(), `doctornect-allow-db-${Date.now()}.txt`);
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  delete process.env.STAGING_SUPABASE_URL;
  fs.writeFileSync(allowFile, `${hostHash8(process.env.PROD_RDS_HOST)}\n`);
  process.env.DOCTORNECT_ALLOWED_HOST_HASHES = allowFile;
  try {
    const missingDb = runWithArgs(
      ['--target=rehearsal', '--confirm-live-data', '--confirm=example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com'],
      () => assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(missingDb.exitCode, 1);
    assert.ok(missingDb.stderr.includes('--confirm-db=doctornect_rehearsal'));

    const wrongDb = runWithArgs(
      [
        '--target=production',
        '--confirm-live-data',
        `--confirm=${process.env.PROD_RDS_HOST}`,
        '--confirm-db=doctornect_rehearsal',
      ],
      () => assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(wrongDb.exitCode, 1);
    assert.ok(wrongDb.stderr.includes('--confirm-db=doctornect'));

    const okRehearsal = runWithArgs(
      [
        '--target=rehearsal',
        '--confirm-live-data',
        `--confirm=${process.env.PROD_RDS_HOST}`,
        '--confirm-db=doctornect_rehearsal',
      ],
      () => assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(okRehearsal.exitCode, null);
    assert.equal(okRehearsal.result.confirmed, true);
  } finally {
    if (prev.PROD_RDS_HOST === undefined) delete process.env.PROD_RDS_HOST;
    else process.env.PROD_RDS_HOST = prev.PROD_RDS_HOST;
    if (prev.PROD_RDS_DB === undefined) delete process.env.PROD_RDS_DB;
    else process.env.PROD_RDS_DB = prev.PROD_RDS_DB;
    if (prev.STAGING_SUPABASE_URL === undefined) delete process.env.STAGING_SUPABASE_URL;
    else process.env.STAGING_SUPABASE_URL = prev.STAGING_SUPABASE_URL;
    delete process.env.DOCTORNECT_ALLOWED_HOST_HASHES;
    try {
      fs.unlinkSync(allowFile);
    } catch (_) {}
  }
});

test('assertConnectedDatabaseMatchesConfirm aborts on current_database mismatch', async () => {
  const prevArgv = process.argv;
  const prevExit = process.exit;
  let exitCode = null;
  process.exit = (code) => {
    exitCode = code;
    throw new Error(`PROCESS_EXIT_${code}`);
  };
  process.argv = [
    'node',
    'migrate.js',
    '--target=rehearsal',
    '--confirm-live-data',
    '--confirm=host.example',
    '--confirm-db=doctornect_rehearsal',
  ];
  const client = {
    query: async (sql) => {
      if (sql.includes('current_database')) {
        return { rows: [{ db: 'doctornect' }] };
      }
      return { rows: [] };
    },
  };
  try {
    await assertConnectedDatabaseMatchesConfirm(client, 'scripts/db/migrate.js');
    assert.fail('expected exit');
  } catch (err) {
    if (!err.message.startsWith('PROCESS_EXIT_')) throw err;
  } finally {
    process.argv = prevArgv;
    process.exit = prevExit;
  }
  assert.equal(exitCode, 1);
});

test('assertConnectedDatabaseMatchesConfirm passes when database matches', async () => {
  const prevArgv = process.argv;
  process.argv = [
    'node',
    'migrate.js',
    '--target=production',
    '--confirm-db=doctornect',
  ];
  const client = {
    query: async () => ({ rows: [{ db: 'doctornect' }] }),
  };
  try {
    await assertConnectedDatabaseMatchesConfirm(client, 'scripts/db/migrate.js');
  } finally {
    process.argv = prevArgv;
  }
});

test('live_data_guard: ADC cannot skip --confirm-db on RDS targets', () => {
  const prev = {
    GAC: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    PROD_RDS_HOST: process.env.PROD_RDS_HOST,
    STAGING_SUPABASE_URL: process.env.STAGING_SUPABASE_URL,
    allow: process.env.DOCTORNECT_ALLOWED_HOST_HASHES,
  };
  const allowFile = path.join(require('os').tmpdir(), `doctornect-allow-adc-${Date.now()}.txt`);
  process.env.GOOGLE_APPLICATION_CREDENTIALS = '/tmp/fake-sa.json';
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  delete process.env.STAGING_SUPABASE_URL;
  fs.writeFileSync(allowFile, `${hostHash8(process.env.PROD_RDS_HOST)}\n`);
  process.env.DOCTORNECT_ALLOWED_HOST_HASHES = allowFile;
  try {
    const missingDb = runWithArgs(
      [
        '--target=rehearsal',
        '--confirm-live-data',
        `--confirm=${process.env.PROD_RDS_HOST}`,
      ],
      () => assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(missingDb.exitCode, 1);
    assert.ok(missingDb.stderr.includes('--confirm-db=doctornect_rehearsal'));

    process.env.PROD_RDS_HOST = ' ';
    const run = runWithArgs(
      ['--target=production', '--confirm-live-data', '--confirm-db=doctornect'],
      () => assertConfirmLiveData('scripts/db/migrate.js'),
    );
    assert.equal(run.exitCode, 1);
    assert.ok(run.stderr.includes('PROD_RDS_HOST'));
    assert.ok(run.stderr.includes('ADC cannot bypass'));
  } finally {
    if (prev.GAC === undefined) delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
    else process.env.GOOGLE_APPLICATION_CREDENTIALS = prev.GAC;
    if (prev.PROD_RDS_HOST === undefined) delete process.env.PROD_RDS_HOST;
    else process.env.PROD_RDS_HOST = prev.PROD_RDS_HOST;
    if (prev.STAGING_SUPABASE_URL === undefined) delete process.env.STAGING_SUPABASE_URL;
    else process.env.STAGING_SUPABASE_URL = prev.STAGING_SUPABASE_URL;
    if (prev.allow === undefined) delete process.env.DOCTORNECT_ALLOWED_HOST_HASHES;
    else process.env.DOCTORNECT_ALLOWED_HOST_HASHES = prev.allow;
    try {
      fs.unlinkSync(allowFile);
    } catch (_) {}
  }
});

test('live_data_guard: replay host hash fingerprints hostname not full URL', () => {
  const prev = {
    REPLAY_DB_URL: process.env.REPLAY_DB_URL,
    argv: process.argv,
  };
  const replayUrl = 'postgresql://replay_user:secret@127.0.0.1:5440/replay_check';
  process.env.REPLAY_DB_URL = replayUrl;
  process.argv = ['node', 'migrate.js', '--target=replay'];
  try {
    const expected = hostHash8(getHostFingerprint(replayUrl));
    assert.equal(resolveLiveDataHostHash(), expected);
    assert.notEqual(resolveLiveDataHostHash(), hostHash8(replayUrl));
    assert.notEqual(
      resolveLiveDataHostHash(),
      hostHash8(hostHash8(getHostFingerprint(replayUrl))),
    );
  } finally {
    process.argv = prev.argv;
    if (prev.REPLAY_DB_URL === undefined) delete process.env.REPLAY_DB_URL;
    else process.env.REPLAY_DB_URL = prev.REPLAY_DB_URL;
  }
});

test('resolveCliMigrationTarget and describeLiveDataGuardTarget', () => {
  const prevArgv = process.argv;
  try {
    process.argv = ['node', 'x', '--target=production'];
    assert.equal(resolveCliMigrationTarget(), 'production');
    assert.ok(describeLiveDataGuardTarget('production').label.includes('production AWS RDS'));
    assert.equal(describeLiveDataGuardTarget('production').databaseName, 'doctornect');
  } finally {
    process.argv = prevArgv;
  }
});
