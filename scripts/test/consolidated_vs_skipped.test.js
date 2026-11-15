'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { SKIPPED_BASES, extractObjects } = require('../audit/compare_consolidated_vs_skipped_migrations');
const { findRepoRoot } = require('../lib/repo_root');

test('consolidated gap report exists for skipped RDS overrides', () => {
  const report = path.join(findRepoRoot(), 'docs/audit/CONSOLIDATED_MISSING_FROM_SKIPPED.txt');
  assert.ok(fs.existsSync(report));
  const text = fs.readFileSync(report, 'utf8');
  assert.match(text, /Missing count: \d+/);
});

test('each skipped migration yields extractable head objects', () => {
  const root = findRepoRoot();
  const migDir = path.join(root, 'db/migrations');
  for (const base of SKIPPED_BASES) {
    const content = fs.readFileSync(path.join(migDir, base), 'utf8');
    const objs = extractObjects(base, content);
    assert.ok(objs.length > 0, `${base} should define policies/functions/grants/triggers`);
  }
});