'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  RDS_OVERRIDES_ROOT,
  listMigrationsForTarget,
  migrationRelPathToAbs,
} = require('../lib/migration_file_list');

let parse;
try {
  parse = require('libpg-query').parse;
} catch (_) {
  parse = require(path.resolve(__dirname, '../../node_modules/libpg-query')).parse;
}

function migrationRelByBasename() {
  const map = new Map();
  for (const rel of listMigrationsForTarget('replay')) {
    map.set(path.basename(rel), rel);
  }
  return map;
}

test('rds_overrides: each file parses, basename matches migration, original exists', async () => {
  const byBase = migrationRelByBasename();
  const overrideFiles = fs
    .readdirSync(RDS_OVERRIDES_ROOT)
    .filter((f) => f.endsWith('.sql'));
  assert.ok(overrideFiles.length >= 1);
  for (const base of overrideFiles) {
    const rel = byBase.get(base);
    assert.ok(rel, `override basename must match a replay migration: ${base}`);
    const originalPath = migrationRelPathToAbs(rel);
    assert.ok(fs.existsSync(originalPath), `original migration missing for override ${base}`);
    const sql = fs.readFileSync(path.join(RDS_OVERRIDES_ROOT, base), 'utf8');
    const parsed = await parse(sql);
    assert.ok(parsed.stmts.length >= 1, `${base} must contain at least one statement`);
  }
});