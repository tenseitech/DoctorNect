'use strict';

const { getEnv } = require('./env_loader');

const LOCAL_CONNECT_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);

function parseLocalDevPgPort() {
  const explicit = getEnv('LOCAL_DEV_PG_PORT');
  if (explicit) return parseInt(explicit, 10);
  const replay = getEnv('REPLAY_DB_URL') || getEnv('LOCAL_FRESH_DB_URL') || '';
  const m = replay.match(/:(\d+)\//);
  if (m) return parseInt(m[1], 10);
  return 5432;
}

/**
 * Fail fast before opening a production RDS pool if the target is clearly local dev Postgres.
 */
function assertProductionRdsTarget(cfg, options = {}) {
  const logicalHost = String(cfg.logicalHost || getEnv('PROD_RDS_HOST') || '').trim().toLowerCase();
  const connectHost = String(cfg.host || '').trim().toLowerCase();
  const port = parseInt(String(cfg.port), 10);
  const localPort = parseLocalDevPgPort();

  const prodPortRaw = getEnv('PROD_RDS_PORT');
  if (!prodPortRaw || String(prodPortRaw).trim() === '') {
    const err = new Error(
      'PROD_RDS_PORT is required for production RDS connections (no default). ' +
        'When using an SSM/SSH tunnel set PROD_RDS_PORT=5433 and PROD_RDS_CONNECT_HOST=127.0.0.1.',
    );
    err.code = 'RDS_PORT_MISSING';
    throw err;
  }

  const looksLikeRds = logicalHost.includes('.rds.amazonaws.com') || logicalHost.includes('.rds.');
  const tunnelMode = LOCAL_CONNECT_HOSTS.has(connectHost) && port !== localPort;

  if (LOCAL_CONNECT_HOSTS.has(connectHost) && port === localPort && looksLikeRds && !options.allowLocalDev) {
    const err = new Error(
      `Refusing production RDS probe: TCP target is local dev Postgres (${connectHost}:${port}), ` +
        `while PROD_RDS_HOST is an RDS endpoint. Start the SSM/SSH tunnel and set PROD_RDS_PORT ` +
        `to the forwarded local port (typically 5433), not ${localPort}.`,
    );
    err.code = 'RDS_LOCAL_DEV_TRAP';
    throw err;
  }

  if (looksLikeRds && LOCAL_CONNECT_HOSTS.has(connectHost) && !tunnelMode) {
    const err = new Error(
      `Refusing production RDS connection: PROD_RDS_CONNECT_HOST is ${connectHost} but ` +
        `PROD_RDS_PORT=${port} does not match tunnel port (expected not ${localPort}).`,
    );
    err.code = 'RDS_TUNNEL_PORT_MISMATCH';
    throw err;
  }
}

/**
 * After connect: print server identity (no secrets) and verify SSL + RDS-ish identity.
 */
async function verifyConnectedRdsSession(client, cfg) {
  const ver = await client.query('SELECT version() AS v');
  const versionLine = ver.rows[0].v.split(',')[0];
  console.log(`PostgreSQL (verified remote): ${versionLine}`);

  let sslOn = false;
  try {
    const sslRes = await client.query('SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()');
    sslOn = Boolean(sslRes.rows[0] && sslRes.rows[0].ssl);
  } catch (_) {
    sslOn = Boolean(client.connection && client.connection.stream && client.connection.stream.encrypted);
  }
  console.log(`SSL active on session: ${sslOn ? 'yes' : 'no'}`);

  const logicalHost = String(cfg.logicalHost || '').toLowerCase();
  const expectsRds = logicalHost.includes('.rds.amazonaws.com');

  if (expectsRds) {
    if (!sslOn) {
      throw Object.assign(new Error('RDS session is not using SSL (required).'), { code: 'RDS_SSL_REQUIRED' });
    }
    const major = await client.query('SHOW server_version_num');
    const num = parseInt(major.rows[0].server_version_num, 10);
    const majorVer = Math.floor(num / 10000);
    console.log(`Server major version: ${majorVer}`);
  }

  const instance = await client.query(
    "SELECT current_setting('rds.extensions', true) IS NOT NULL OR version() ILIKE '%amazon%' AS likely_aws",
  ).catch(() => ({ rows: [{ likely_aws: null }] }));
  if (expectsRds && instance.rows[0] && instance.rows[0].likely_aws === false) {
    console.warn(
      'Warning: connected server does not look like AWS RDS (version string lacks Amazon branding). ' +
        'Verify tunnel forwards to RDS, not local Postgres.',
    );
  }

  return { versionLine, sslOn };
}

module.exports = {
  assertProductionRdsTarget,
  verifyConnectedRdsSession,
  parseLocalDevPgPort,
  LOCAL_CONNECT_HOSTS,
};
