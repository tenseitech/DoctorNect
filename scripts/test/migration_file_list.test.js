'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  listMigrationsForTarget,
  listRdsOnlyMigrationRelPaths,
  listSharedMigrationRelPathsFromDir,
  migrationVersionFromRel,
  assertVersionCollisions,
  assertMigrationVersionFormats,
  sortMigrationRelPaths,
} = require('../lib/migration_file_list');

test('staging target excludes db/migrations/rds/', () => {
  const staging = listMigrationsForTarget('staging');
  const production = listMigrationsForTarget('production');
  const rehearsal = listMigrationsForTarget('rehearsal');
  const replay = listMigrationsForTarget('replay');
  const replayCheck = listMigrationsForTarget('replay_check');
  const rdsOnly = listRdsOnlyMigrationRelPaths();
  assert.ok(rdsOnly.length >= 1, 'expected at least one RDS-only migration file');
  for (const rel of rdsOnly) {
    assert.ok(!staging.includes(rel), `staging must not include ${rel}`);
    for (const inc of [production, rehearsal, replay, replayCheck]) {
      assert.ok(inc.includes(rel), `${rel} must be in production-style target list`);
    }
  }
  assert.ok(production.length === staging.length + rdsOnly.length);
});

test('merged sort interleaves shared and rds/ by version prefix', () => {
  const sorted = sortMigrationRelPaths([
    'rds/20261001000002_rds_only.sql',
    '20261001000001_first.sql',
    '20261001000003_third.sql',
  ]);
  assert.deepEqual(sorted, [
    '20261001000001_first.sql',
    'rds/20261001000002_rds_only.sql',
    '20261001000003_third.sql',
  ]);
});

test('invalid migration version prefix throws before collision check', () => {
  assert.throws(
    () => assertMigrationVersionFormats(['20261_bad_prefix.sql']),
    /Invalid migration filename.*20261_bad_prefix\.sql/,
  );
  assert.throws(
    () => assertMigrationVersionFormats(['rds/not14digits.sql']),
    /Invalid migration filename.*not14digits/,
  );
});

test('sort uses numeric version order (14-digit string compare)', () => {
  const sorted = sortMigrationRelPaths([
    '20260923000010_after.sql',
    '20260923000002_before.sql',
    'rds/20260923000005_mid.sql',
  ]);
  assert.deepEqual(sorted, [
    '20260923000002_before.sql',
    'rds/20260923000005_mid.sql',
    '20260923000010_after.sql',
  ]);
});

test('version collision throws with both file names', () => {
  assert.throws(
    () =>
      assertVersionCollisions([
        '20261113000001_shared.sql',
        'rds/20261113000001_rds.sql',
      ]),
    (err) =>
      err.message.includes('20261113000001') &&
      err.message.includes('20261113000001_shared.sql') &&
      err.message.includes('rds/20261113000001_rds.sql'),
  );
});

test('empty migrations dir throws', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'doctornect-mig-empty-'));
  try {
    assert.throws(() => listSharedMigrationRelPathsFromDir(dir), /empty migrations dir/);
  } finally {
    fs.rmdirSync(dir);
  }
});

test('migrationVersionFromRel handles rds/ prefix', () => {
  assert.equal(
    migrationVersionFromRel('rds/20261113000001_rds_system_admin_and_audit.sql'),
    '20261113000001',
  );
});

test('production list is sorted by version prefix', () => {
  const files = listMigrationsForTarget('production');
  let prev = '';
  for (const rel of files) {
    const v = migrationVersionFromRel(rel);
    assert.ok(v >= prev, `versions must be non-decreasing: ${prev} -> ${v}`);
    prev = v;
  }
});
