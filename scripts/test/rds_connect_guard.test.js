'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { assertProductionRdsTarget, parseLocalDevPgPort } = require('../lib/rds_connect_guard');

const ISOLATED_ENV = {
  REPLAY_DB_URL: '',
  LOCAL_FRESH_DB_URL: '',
  LOCAL_REPLAY_PG_PORT: '5440',
  PROD_RDS_PORT: '5433',
};

test('assertProductionRdsTarget: blocks localhost:5432 when logical host is RDS', () => {
  assert.throws(
    () =>
      assertProductionRdsTarget(
        {
          host: '127.0.0.1',
          port: 5432,
          logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
        },
        { localDevPgPort: 5432, env: ISOLATED_ENV },
      ),
    (err) => err.code === 'RDS_LOCAL_DEV_TRAP',
  );
});

test('assertProductionRdsTarget: blocks production probe on LOCAL_REPLAY_PG_PORT (5440)', () => {
  assert.throws(
    () =>
      assertProductionRdsTarget(
        {
          logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
          host: '127.0.0.1',
          port: 5440,
        },
        { localDevPgPort: 5432, env: ISOLATED_ENV },
      ),
    (err) => err.code === 'RDS_REPLAY_PORT_TRAP',
  );
});

test('assertProductionRdsTarget: allows tunnel localhost:5433', () => {
  assert.doesNotThrow(() =>
    assertProductionRdsTarget(
      {
        host: '127.0.0.1',
        port: 5433,
        logicalHost: 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
      },
      { localDevPgPort: 5432, env: ISOLATED_ENV },
    ),
  );
});

test('parseLocalDevPgPort: isolated env defaults to 5432 without REPLAY_DB_URL', () => {
  assert.equal(parseLocalDevPgPort(ISOLATED_ENV), 5432);
});