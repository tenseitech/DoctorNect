'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildRdsPoolConfig,
  maskRdsTarget,
  resolveRdsTlsServername,
} = require('../lib/rds_pool_config');

const ORIGINAL = { ...process.env };

beforeEach(() => {
  process.env = { ...ORIGINAL };
  delete process.env.PROD_RDS_CONNECT_HOST;
  delete process.env.PROD_RDS_SSL_SERVERNAME;
});

afterEach(() => {
  process.env = ORIGINAL;
});

test('TLS servername uses PROD_RDS_HOST (not tunnel TCP host)', () => {
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  const logicalHost = String(process.env.PROD_RDS_HOST || '').trim();
  assert.ok(logicalHost.length > 0, 'PROD_RDS_HOST fixture required');
  process.env.PROD_RDS_CONNECT_HOST = '127.0.0.1';
  process.env.PROD_RDS_PORT = '5433';
  if (!process.env.PROD_RDS_PASSWORD) {
    process.env.PROD_RDS_PASSWORD = 'test-password-not-real';
  }
  delete process.env.PROD_RDS_SSL_SERVERNAME;

  assert.equal(resolveRdsTlsServername(), logicalHost);

  const cfg = buildRdsPoolConfig();
  assert.equal(cfg.host, '127.0.0.1');
  assert.equal(cfg.ssl.servername, logicalHost);
  assert.notEqual(cfg.ssl.servername, cfg.host);
  assert.equal(cfg.ssl.rejectUnauthorized, true);
});

test('maskRdsTarget redacts password; TLS uses real servername in pool config', () => {
  process.env.PROD_RDS_HOST = 'example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com';
  process.env.PROD_RDS_CONNECT_HOST = '127.0.0.1';
  process.env.PROD_RDS_PORT = '5433';
  process.env.PROD_RDS_PASSWORD = 'secret';
  const cfg = buildRdsPoolConfig();
  const masked = maskRdsTarget(cfg);
  assert.match(masked, /servername=<prod-rds-host>/);
  assert.doesNotMatch(masked, /secret/);
  assert.notEqual(cfg.ssl.servername, '127.0.0.1');
});