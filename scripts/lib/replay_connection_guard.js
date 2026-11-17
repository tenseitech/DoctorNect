'use strict';

const { getHostFingerprint } = require('./env_guard');
const { getEnv } = require('./env_loader');

function envGet(key, envOverride) {
  if (envOverride && Object.prototype.hasOwnProperty.call(envOverride, key)) {
    return envOverride[key] == null ? '' : String(envOverride[key]);
  }
  return getEnv(key);
}

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

function parseConnectionUrlHostPort(url) {
  if (!url || !String(url).includes('://')) {
    return { host: getHostFingerprint(url), port: null };
  }
  try {
    const u = new URL(String(url).replace(/^postgres:\/\//i, 'postgresql://'));
    const port = u.port ? parseInt(u.port, 10) : null;
    return { host: (u.hostname || '').toLowerCase(), port };
  } catch (_) {
    return { host: getHostFingerprint(url), port: null };
  }
}

function isLoopbackHost(host) {
  return LOCAL_HOSTS.has(String(host || '').trim().toLowerCase());
}

/**
 * Static guards for REPLAY_DB_URL / RDS admin URLs before any DB connect.
 * @returns {{ ok: true } | { ok: false, code: string, message: string }}
 */
function assertReplayDatabaseUrlSafe(options = {}) {
  const allowNonstandardPort = Boolean(options.allowNonstandardReplayPort);
  const env = options.env;
  const replayUrl = String(
    options.replayUrl
      || envGet('REPLAY_DB_URL', env)
      || envGet('RDS_ADMIN_DB_URL', env)
      || envGet('RDS_MASTER_URL', env)
      || '',
  ).trim();

  if (!replayUrl) {
    return { ok: false, code: 'REPLAY_URL_MISSING', message: 'Missing REPLAY_DB_URL (or RDS_ADMIN_DB_URL / RDS_MASTER_URL).' };
  }

  const { host, port } = parseConnectionUrlHostPort(replayUrl);
  if (!isLoopbackHost(host)) {
    return {
      ok: false,
      code: 'REPLAY_HOST_NOT_LOOPBACK',
      message: `Replay URL host must be localhost/127.0.0.1/::1 (got non-loopback). Refusing live/rds tunnel targets.`,
    };
  }

  const prodRdsHost = getHostFingerprint(envGet('PROD_RDS_HOST', env) || '');
  if (prodRdsHost && host === prodRdsHost) {
    return { ok: false, code: 'REPLAY_MATCHES_PROD_RDS', message: 'Replay URL host matches PROD_RDS_HOST.' };
  }

  const prodConnectHost = getHostFingerprint(envGet('PROD_RDS_CONNECT_HOST', env) || '');
  const prodRdsPort = String(envGet('PROD_RDS_PORT', env) || '').trim();
  if (prodConnectHost && host === prodConnectHost && !isLoopbackHost(host)) {
    return {
      ok: false,
      code: 'REPLAY_MATCHES_PROD_CONNECT',
      message: 'Replay URL host matches PROD_RDS_CONNECT_HOST (non-loopback).',
    };
  }
  if (prodRdsPort && isLoopbackHost(host) && String(port) === prodRdsPort) {
    return {
      ok: false,
      code: 'REPLAY_PORT_MATCHES_PROD_TUNNEL',
      message: `Replay URL port ${port} matches PROD_RDS_PORT (${prodRdsPort}). Use LOCAL_REPLAY_PG_PORT (default 5440) for Docker replay, not the RDS tunnel port.`,
    };
  }

  const expectedPort = parseInt(
    String(options.expectedReplayPort || envGet('LOCAL_REPLAY_PG_PORT', env) || '5440').trim(),
    10,
  );
  if (!allowNonstandardPort && port != null && !Number.isNaN(expectedPort) && port !== expectedPort) {
    return {
      ok: false,
      code: 'REPLAY_PORT_NONSTANDARD',
      message: `Replay URL port is ${port}; Docker replay must use LOCAL_REPLAY_PG_PORT=${expectedPort} (pass --allow-nonstandard-replay-port only in tests).`,
    };
  }

  const stagingUrl = envGet('STAGING_SUPABASE_DB_URL', env);
  if (stagingUrl && getHostFingerprint(replayUrl) === getHostFingerprint(stagingUrl)) {
    return { ok: false, code: 'REPLAY_MATCHES_STAGING', message: 'Replay URL matches STAGING_SUPABASE_DB_URL.' };
  }

  const prodSupabaseUrl = envGet('PROD_SUPABASE_DB_URL', env);
  if (prodSupabaseUrl && getHostFingerprint(replayUrl) === getHostFingerprint(prodSupabaseUrl)) {
    return { ok: false, code: 'REPLAY_MATCHES_PROD_SUPABASE', message: 'Replay URL matches PROD_SUPABASE_DB_URL.' };
  }

  return { ok: true };
}

module.exports = {
  assertReplayDatabaseUrlSafe,
  parseConnectionUrlHostPort,
  isLoopbackHost,
};