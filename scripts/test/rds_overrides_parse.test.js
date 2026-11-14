'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { RDS_OVERRIDES_ROOT, listMigrationsForTarget } = require('../lib/migration_file_list');

let parse;
try {
  parse = require('libpg-query').parse;
} catch (_) {
  parse = require(path.resolve(__dirname, '../../node_modules/libpg-query')).parse;
}

function migrationBasenames() {
  const bases = new Set();
  for (const rel of listMigrationsForTarget('replay')) {
    bases.add(path.basename(rel));
  }
  return bases;
}

test('rds_overrides: each file parses and basename matches a migration', async () => {
  const allowed = migrationBasenames();
  const overrideFiles = fs
    .readdirSync(RDS_OVERRIDES_ROOT)
    .filter((f) => f.endsWith('.sql'));
  assert.ok(overrideFiles.length >= 1);
  for (const base of overrideFiles) {
    assert.ok(allowed.has(base), `override basename must match migration: ${base}`);
    const sql = fs.readFileSync(path.join(RDS_OVERRIDES_ROOT, base), 'utf8');
    const parsed = await parse(sql);
    assert.ok(parsed.stmts.length >= 1, `${base} must contain at least one statement`);
  }
});