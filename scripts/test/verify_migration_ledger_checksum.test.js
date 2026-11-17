'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { resolveMigrationSqlPath, migrationRelPathToAbs } = require('../lib/migration_file_list');
const { computeChecksum } = require('../lib/migration_checksum');

const OVERRIDE_EXAMPLE = '20260923000002_doctornect_rls.sql';

test('RDS ledger checksum uses override SQL when present', () => {
  const staging = resolveMigrationSqlPath({ relPath: OVERRIDE_EXAMPLE, target: 'staging' });
  const production = resolveMigrationSqlPath({ relPath: OVERRIDE_EXAMPLE, target: 'production' });
  assert.equal(staging.useOverride, false);
  assert.equal(production.useOverride, true);
  const baseSql = fs.readFileSync(staging.sqlPath, 'utf8');
  const overrideSql = fs.readFileSync(production.sqlPath, 'utf8');
  assert.notEqual(computeChecksum(baseSql), computeChecksum(overrideSql));
});

test('readMigrationSqlForChecksum parity with verify script helper', () => {
  const { readMigrationSqlForChecksum } = require('../db/verify_migration_files_ledger');
  const rel = OVERRIDE_EXAMPLE;
  const prod = readMigrationSqlForChecksum(rel, 'production');
  const staging = readMigrationSqlForChecksum(rel, 'staging');
  assert.equal(prod.useOverride, true);
  assert.equal(staging.useOverride, false);
  assert.ok(fs.existsSync(prod.sqlPath));
  assert.equal(prod.sqlPath, resolveMigrationSqlPath({ relPath: rel, target: 'production' }).sqlPath);
  assert.equal(
    staging.sqlContent,
    fs.readFileSync(migrationRelPathToAbs(rel), 'utf8'),
  );
});