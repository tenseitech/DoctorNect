'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { assertProductionRdsTarget, parseLocalDevPgPort } = require('../lib/rds_connect_guard');

test('assertProductionRdsTarget: blocks localhost:5432 when logical host is RDS', () => {
  const localPort = parseLocalDevPgPort();
  assert.throws(
    () =>
      assertProductionRdsTarget({
        host: '127.0.0.1',
        port: localPort,
        logicalHost: 'doctornect-db.c92k0uqgqekv.ap-south-1.rds.amazonaws.com',
      }),
    (err) => err.code === 'RDS_LOCAL_DEV_TRAP',
  );
});

test('assertProductionRdsTarget: allows tunnel localhost:5433', () => {
  const localPort = parseLocalDevPgPort();
  assert.doesNotThrow(() =>
    assertProductionRdsTarget({
      host: '127.0.0.1',
      port: localPort + 1,
      logicalHost: 'doctornect-db.c92k0uqgqekv.ap-south-1.rds.amazonaws.com',
    }),
  );
});
