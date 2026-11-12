'use strict';

const fs = require('fs');
const path = require('path');
const { getEnv } = require('./env_loader');

const DEFAULT_CA = path.resolve(__dirname, '../../infra/aws/global-bundle.pem');

/**
 * RDS Postgres client config with optional SSM/SSH tunnel.
 *
 * - PROD_RDS_HOST: logical RDS endpoint (host fingerprint, TLS servername, --confirm= value)
 * - PROD_RDS_CONNECT_HOST: TCP host for pg (default PROD_RDS_HOST; use 127.0.0.1 when tunneling)
 * - PROD_RDS_PORT: TCP port (tunnel local port, e.g. 5433)
 * - PROD_RDS_SSL_SERVERNAME: TLS SNI (defaults to PROD_RDS_HOST — required through localhost tunnel)
 */
function resolveRdsTlsServername() {
  return getEnv('PROD_RDS_SSL_SERVERNAME') || getEnv('PROD_RDS_HOST') || '';
}

function resolveRdsConnectHost() {
  return getEnv('PROD_RDS_CONNECT_HOST') || getEnv('PROD_RDS_HOST') || '';
}

function readCaBundle() {
  const certPath = getEnv('PROD_RDS_SSL_ROOT_CERT') || DEFAULT_CA;
  if (!fs.existsSync(certPath)) {
    const err = new Error(
      `RDS CA bundle not found at ${certPath}. Download AWS RDS global bundle (see infra/aws/README_CA_BUNDLE.md).`,
    );
    err.code = 'ENOENT_CA_BUNDLE';
    throw err;
  }
  return fs.readFileSync(certPath);
}

function buildRdsPoolConfig(options = {}) {
  const database = options.database || getEnv('PROD_RDS_DB') || 'doctornect';
  const user = options.user || getEnv('PROD_RDS_USER') || 'postgres';
  const password = getEnv('PROD_RDS_PASSWORD');
  const host = resolveRdsConnectHost();
  const portRaw = getEnv('PROD_RDS_PORT');
  if (!portRaw || String(portRaw).trim() === '') {
    throw Object.assign(
      new Error(
        'PROD_RDS_PORT is required (no default). For SSM/SSH tunnel use PROD_RDS_PORT=5433 with PROD_RDS_CONNECT_HOST=127.0.0.1.',
      ),
      { code: 'RDS_PORT_MISSING' },
    );
  }
  const port = parseInt(portRaw, 10);
  const servername = resolveRdsTlsServername();

  if (!host || !password) {
    throw new Error('PROD_RDS_HOST / PROD_RDS_CONNECT_HOST and PROD_RDS_PASSWORD are required');
  }

  const ca = readCaBundle();
  const sslMode = (getEnv('PROD_RDS_SSLMODE') || 'verify-full').toLowerCase();

  const ssl = {
    ca,
    rejectUnauthorized: sslMode !== 'require',
    servername: servername || host,
  };

  return {
    host,
    port,
    database,
    user,
    password,
    ssl,
    logicalHost: getEnv('PROD_RDS_HOST') || host,
  };
}

function maskRdsTarget(cfg) {
  const connect = cfg.host === '127.0.0.1' || cfg.host === 'localhost' ? `127.0.0.1:${cfg.port}` : '<rds-connect-host>';
  return `postgresql://${cfg.user}:****@${connect}/${cfg.database}?sslmode=verify-full&servername=<prod-rds-host>`;
}

module.exports = {
  buildRdsPoolConfig,
  maskRdsTarget,
  readCaBundle,
  resolveRdsConnectHost,
  resolveRdsTlsServername,
  DEFAULT_CA,
};
