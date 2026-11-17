'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { isSkippableTransactionControlStatement } = require('../lib/migration_txn_sql');
const { assertClientRoutingHintIgnored } = require('../lib/demo_routing');

test('transaction control statements never run inside migrate harness', () => {
  assert.equal(isSkippableTransactionControlStatement('COMMIT;'), true);
  assert.equal(isSkippableTransactionControlStatement('BEGIN;'), true);
  assert.equal(isSkippableTransactionControlStatement('ROLLBACK;'), true);
  assert.equal(isSkippableTransactionControlStatement('SAVEPOINT sp_stmt;'), true);
  assert.equal(isSkippableTransactionControlStatement("CREATE TABLE t(id int);"), false);
});

test('Cloud Functions gateway client headers pass routing-hint gate', () => {
  const check = assertClientRoutingHintIgnored({
    'x-app-env': 'production',
    'x-client-source': 'medibond-cloud-functions',
    authorization: 'Bearer x',
  });
  assert.equal(check.ok, true);
  assert.deepEqual(check.blocked, []);
});