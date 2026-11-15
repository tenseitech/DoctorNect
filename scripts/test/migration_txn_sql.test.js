'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { isSkippableTransactionControlStatement } = require('../lib/migration_txn_sql');

test('skips top-level BEGIN/COMMIT/ROLLBACK', () => {
  assert.equal(isSkippableTransactionControlStatement('BEGIN;'), true);
  assert.equal(isSkippableTransactionControlStatement('COMMIT;'), true);
  assert.equal(isSkippableTransactionControlStatement('ROLLBACK;'), true);
});

test('does not skip DDL', () => {
  assert.equal(isSkippableTransactionControlStatement("CREATE TABLE t (id int);"), false);
});