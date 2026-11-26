'use strict';

/**
 * Shared Postgres pool for Cloud Functions direct SQL (DLQ, reconciliation).
 * APP_ENV=staging → STAGING_SUPABASE_DB_URL chain only.
 * APP_ENV=production → DATABASE_URL or PROD_RDS_* only (never Supabase URLs).
 */

const fs = require('fs');
const path = require('path');

let _pgPool = null;

const PRODUCTION_PG_CONFIG_ERROR = 'PRODUCTION_PG_CONFIG_MISSING';

/**
 * Direct-SQL modules when APP_ENV=production. Not wired through index.js exports today.
 * @type {ReadonlyArray<{ file: string, functions: string, pathKind: 'pg_pool', traffic: string }>}
 */
const PRODUCTION_PG_POOL_CALLERS = Object.freeze([
  {
    file: 'cross_role_sync.js',
    functions: 'DLQ insert and server-side maintenance jobs',
    pathKind: 'pg_pool',
    traffic: 'batch/maintenance (needs pg_pool); not exported from index.js',
  },
]);

const { isProductionBootRequiresDatabaseUrl } = require('./production_pg_pool_boot');

function isProductionAppEnv() {
  return String(process.env.APP_ENV || 'staging').trim().toLowerCase() === 'production';
}

function looksLikeSupabaseDatabaseUrl(url) {
  const s = String(url || '').trim().toLowerCase();
  return s.includes('supabase.co') || s.includes('pooler.supabase.com');
}

function hasProductionRdsCredentials() {
  const password = String(process.env.PROD_RDS_PASSWORD || '').trim();
  const port = String(process.env.PROD_RDS_PORT || '').trim();
  const host =
    String(process.env.PROD_RDS_CONNECT_HOST || process.env.PROD_RDS_HOST || '').trim();
  return Boolean(password && port && host);
}

function resolveStagingDatabaseUrl() {
  return String(
    process.env.STAGING_SUPABASE_DB_URL ||
      process.env.SUPABASE_DB_URL ||
      process.env.DATABASE_URL ||
      '',
  ).trim();
}

function loadRdsCaBundle() {
  const defaultCa = path.resolve(__dirname, '../../../../infra/aws/global-bundle.pem');
  const certPath = String(process.env.PROD_RDS_SSL_ROOT_CERT || defaultCa).trim();
  if (!fs.existsSync(certPath)) {
    const err = new Error(
      `[pg_pool] RDS CA bundle not found at ${certPath}. See infra/aws/README_CA_BUNDLE.md.`,
    );
    err.code = 'RDS_CA_MISSING';
    throw err;
  }
  return fs.readFileSync(certPath);
}

function resolveRdsTlsServername() {
  return String(process.env.PROD_RDS_SSL_SERVERNAME || process.env.PROD_RDS_HOST || '').trim();
}

function sslForRdsConnectionString(connectionString) {
  const servername = resolveRdsTlsServername();
  let hostname = servername;
  try {
    const parsed = new URL(connectionString);
    if (!hostname && parsed.hostname) hostname = parsed.hostname;
  } catch (_) {
    /* ignore */
  }
  const sslMode = String(process.env.PROD_RDS_SSLMODE || 'verify-full').toLowerCase();
  return {
    ca: loadRdsCaBundle(),
    rejectUnauthorized: sslMode !== 'require',
    servername: servername || hostname || undefined,
  };
}

function resolveProductionPoolConfig() {
  assertProductionPgPoolConfigOrThrow();

  const directUrl = String(process.env.DATABASE_URL || '').trim();
  if (directUrl) {
    if (looksLikeSupabaseDatabaseUrl(directUrl)) {
      const err = new Error(
        '[pg_pool] APP_ENV=production DATABASE_URL must not point at Supabase.',
      );
      err.code = PRODUCTION_PG_CONFIG_ERROR;
      throw err;
    }
    const isRds = /\.rds\.amazonaws\.com/i.test(directUrl);
    return {
      connectionString: directUrl,
      ssl: isRds ? sslForRdsConnectionString(directUrl) : { rejectUnauthorized: true },
    };
  }

  try {
    const { buildRdsPoolConfig } = require(path.resolve(
      __dirname,
      '../../../../scripts/lib/rds_pool_config',
    ));
    const cfg = buildRdsPoolConfig();
    const ssl = cfg.ssl || {};
    if (ssl.rejectUnauthorized === false) {
      const err = new Error(
        '[pg_pool] APP_ENV=production RDS SSL must verify the server certificate (rejectUnauthorized cannot be false).',
      );
      err.code = 'RDS_SSL_INSECURE';
      throw err;
    }
    if (!ssl.ca) {
      ssl.ca = loadRdsCaBundle();
      ssl.rejectUnauthorized = true;
    }
    return cfg;
  } catch (err) {
    if (err.code === PRODUCTION_PG_CONFIG_ERROR || err.code === 'RDS_SSL_INSECURE') {
      throw err;
    }
    const wrap = new Error(
      `[pg_pool] APP_ENV=production could not build RDS pool config: ${err.message}`,
    );
    wrap.code = PRODUCTION_PG_CONFIG_ERROR;
    throw wrap;
  }
}

/**
 * Fail fast when production would otherwise fall back to staging Supabase URLs.
 */
function assertProductionPgPoolConfigOrThrow() {
  if (!isProductionAppEnv()) return;

  const directUrl = String(process.env.DATABASE_URL || '').trim();
  if (directUrl) {
    if (looksLikeSupabaseDatabaseUrl(directUrl)) {
      const err = new Error(
        '[pg_pool] APP_ENV=production DATABASE_URL must not point at Supabase.',
      );
      err.code = PRODUCTION_PG_CONFIG_ERROR;
      throw err;
    }
    return;
  }

  if (!hasProductionRdsCredentials()) {
    const err = new Error(
      '[pg_pool] APP_ENV=production requires DATABASE_URL or PROD_RDS_HOST/PROD_RDS_CONNECT_HOST, PROD_RDS_PASSWORD, and PROD_RDS_PORT. Supabase DB URLs are not used in production.',
    );
    err.code = PRODUCTION_PG_CONFIG_ERROR;
    throw err;
  }
}

function defaultPoolOptions(base) {
  const max = parseInt(process.env.PG_POOL_MAX || '10', 10);
  const idleTimeoutMillis = parseInt(process.env.PG_POOL_IDLE_MS || '30000', 10);
  const defaultConnectMs = isProductionAppEnv() ? '5000' : '10000';
  const connectionTimeoutMillis = parseInt(
    process.env.PG_POOL_CONNECT_MS || defaultConnectMs,
    10,
  );
  return {
    ...base,
    max: Number.isFinite(max) ? max : 10,
    idleTimeoutMillis: Number.isFinite(idleTimeoutMillis) ? idleTimeoutMillis : 30000,
    connectionTimeoutMillis: Number.isFinite(connectionTimeoutMillis)
      ? connectionTimeoutMillis
      : parseInt(defaultConnectMs, 10),
  };
}

function attachPgPoolErrorLogging(pool) {
  if (!pool || pool.__doctornectPgPoolErrorHook) return;
  pool.__doctornectPgPoolErrorHook = true;
  pool.on('error', (err) => {
    console.error(`[pg_pool] pool error (idle client): ${err?.message || err}`);
  });
}

function getPgPool() {
  if (_pgPool) return _pgPool;

  if (isProductionAppEnv()) {
    assertProductionPgPoolConfigOrThrow();
  } else {
    const stagingUrl = resolveStagingDatabaseUrl();
    if (!stagingUrl) return null;
  }

  let Pool;
  try {
    ({ Pool } = require('pg'));
  } catch (_) {
    try {
      ({ Pool } = require('../../../scripts/node_modules/pg'));
    } catch (__) {
      return null;
    }
  }

  if (isProductionAppEnv()) {
    const prodOpts = resolveProductionPoolConfig();
    if (prodOpts.connectionString) {
      _pgPool = new Pool(
        defaultPoolOptions({
          connectionString: prodOpts.connectionString,
          ssl: prodOpts.ssl,
        }),
      );
    } else {
      const { ssl, ...rest } = prodOpts;
      const mergedSsl = ssl || { ca: loadRdsCaBundle(), rejectUnauthorized: true };
      if (mergedSsl.rejectUnauthorized === false) {
        const err = new Error(
          '[pg_pool] APP_ENV=production RDS SSL must verify the server certificate.',
        );
        err.code = 'RDS_SSL_INSECURE';
        throw err;
      }
      _pgPool = new Pool(defaultPoolOptions({ ...rest, ssl: mergedSsl }));
    }
  } else {
    const dbUrl = resolveStagingDatabaseUrl();
    _pgPool = new Pool(
      defaultPoolOptions({
        connectionString: dbUrl,
        ssl: { rejectUnauthorized: false },
      }),
    );
  }

  attachPgPoolErrorLogging(_pgPool);
  return _pgPool;
}

/** @visibleForTesting */
function _resetPgPoolForTests() {
  if (_pgPool) {
    void _pgPool.end().catch(() => {});
    _pgPool = null;
  }
}

module.exports = {
  getPgPool,
  isProductionAppEnv,
  isProductionBootRequiresDatabaseUrl,
  PRODUCTION_PG_POOL_CALLERS,
  resolveStagingDatabaseUrl,
  assertProductionPgPoolConfigOrThrow,
  resolveProductionPoolConfig,
  looksLikeSupabaseDatabaseUrl,
  PRODUCTION_PG_CONFIG_ERROR,
  _resetPgPoolForTests,
};