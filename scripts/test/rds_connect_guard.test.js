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
        logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
      }),
    (err) => err.code === 'RDS_LOCAL_DEV_TRAP',
  );
});

test('assertProductionRdsTarget: blocks production probe on LOCAL_REPLAY_PG_PORT', () => {
  assert.throws(() => {
    try {
      assertProductionRdsTarget(
        {
          logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
          host: '127.0.0.1',
          port: 5440,
        },
        {},
      );
    } catch (e) {
      assert.strictEqual(e.code, 'RDS_REPLAY_PORT_TRAP');
      throw e;
    }
  });
});

test('assertProductionRdsTarget: allows tunnel localhost:5433', () => {
  const localPort = parseLocalDevPgPort();
  assert.doesNotThrow(() =>
    assertProductionRdsTarget({
      host: '127.0.0.1',
      port: localPort + 1,
      logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
    }),
  );
});
