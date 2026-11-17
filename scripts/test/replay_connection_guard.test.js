'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const { assertReplayDatabaseUrlSafe } = require('../lib/replay_connection_guard');

const ORIGINAL = { ...process.env };

function restoreEnv() {
  process.env = { ...ORIGINAL };
}

beforeEach(() => {
  restoreEnv();
});

afterEach(() => {
  restoreEnv();
});

const BASE_ENV = {
  PROD_RDS_PORT: '5433',
  STAGING_SUPABASE_DB_URL: '',
  PROD_SUPABASE_DB_URL: '',
  LOCAL_REPLAY_PG_PORT: '5440',
};

test('rejects non-loopback replay host', () => {
  const r = assertReplayDatabaseUrlSafe({
    replayUrl: 'postgresql://u:p@example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com:5432/postgres',
    env: BASE_ENV,
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'REPLAY_HOST_NOT_LOOPBACK');
});

test('rejects replay on PROD_RDS_PORT tunnel', () => {
  const r = assertReplayDatabaseUrlSafe({
    replayUrl: 'postgresql://u:p@127.0.0.1:5433/postgres',
    allowNonstandardReplayPort: true,
    env: BASE_ENV,
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'REPLAY_PORT_MATCHES_PROD_TUNNEL');
});

test('requires LOCAL_REPLAY_PG_PORT unless override flag', () => {
  const blocked = assertReplayDatabaseUrlSafe({
    replayUrl: 'postgresql://u:p@127.0.0.1:5432/postgres',
    env: BASE_ENV,
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.code, 'REPLAY_PORT_NONSTANDARD');
  const allowed = assertReplayDatabaseUrlSafe({
    replayUrl: 'postgresql://u:p@127.0.0.1:5432/postgres',
    allowNonstandardReplayPort: true,
    env: BASE_ENV,
  });
  assert.equal(allowed.ok, true);
});

test('accepts docker replay on 5440', () => {
  const r = assertReplayDatabaseUrlSafe({
    replayUrl: 'postgresql://u:p@127.0.0.1:5440/postgres',
    env: BASE_ENV,
  });
  assert.equal(r.ok, true);
});