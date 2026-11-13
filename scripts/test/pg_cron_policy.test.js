'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const {
  assertProductionPgCronOrThrow,
  shouldSkipMigrationFile,
  sharedPreloadIncludesPgCron,
  cronDatabaseMatchesProd,
  CRON_MIGRATION_FILE,
} = require('../lib/pg_cron_policy');

test('assertProductionPgCronOrThrow fails when pg_cron unavailable on production', () => {
  assert.throws(
    () =>
      assertProductionPgCronOrThrow({
        target: 'production',
        available: false,
        installed: false,
        allowNoCron: false,
      }),
    (err) => {
      assert.strictEqual(err.code, 'PG_CRON_NOT_AVAILABLE');
      return true;
    },
  );
});

test('assertProductionPgCronOrThrow allows staging without pg_cron check', () => {
  const r = assertProductionPgCronOrThrow({
    target: 'staging',
    available: false,
    installed: false,
  });
  assert.strictEqual(r.skipCronMigration, false);
});

test('assertProductionPgCronOrThrow --allow-no-cron skips migration file', () => {
  const r = assertProductionPgCronOrThrow({
    target: 'production',
    available: false,
    installed: false,
    allowNoCron: true,
  });
  assert.strictEqual(r.skipCronMigration, true);
  assert.strictEqual(shouldSkipMigrationFile(CRON_MIGRATION_FILE, true), true);
});

test('sharedPreloadIncludesPgCron', () => {
  assert.strictEqual(sharedPreloadIncludesPgCron('pg_stat_statements,pg_cron'), true);
  assert.strictEqual(sharedPreloadIncludesPgCron('pg_stat_statements'), false);
});

test('cronDatabaseMatchesProd compares cron.database_name to expected db', () => {
  assert.strictEqual(cronDatabaseMatchesProd('doctornect', 'doctornect'), true);
  assert.strictEqual(cronDatabaseMatchesProd('postgres', 'doctornect'), false);
});
