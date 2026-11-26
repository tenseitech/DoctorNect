'use strict';

/**
 * Shared pg connection options for the staging Supabase Postgres (direct host or session
 * pooler). Certificate verification is always on:
 *
 * - Supabase serves a chain that ends in its own private root ("Supabase Root 2021 CA"),
 *   which is not in Node's built-in trust store. Download it once from the Supabase dashboard
 *   (Project Settings > Database > SSL Configuration > Download certificate, file
 *   `prod-ca-2021.crt`) and point STAGING_SUPABASE_CA_PATH at it.
 * - With the CA file the connection verifies the chain AND the hostname (verify-full).
 * - Without it, a Supabase host is refused with a message that explains the fix. We never
 *   fall back to `rejectUnauthorized: false` and never touch NODE_TLS_REJECT_UNAUTHORIZED.
 * - ssl* / uselibpqcompat parameters are removed from the connection string, because pg lets
 *   connection-string SSL settings override the `ssl` object built here.
 * - Loopback hosts (local Docker) may connect without TLS only when the caller allows it.
 *
 * Nothing here prints or returns the connection string in an error message.
 */

const fs = require('fs');
const path = require('path');

const CA_PATH_ENV = 'STAGING_SUPABASE_CA_PATH';
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
const URL_SSL_PARAMS = /^(ssl.*|uselibpqcompat)$/i;

function parseDbUrl(dbUrl) {
  try {
    return new URL(String(dbUrl).trim().replace(/^postgres:\/\//i, 'postgresql://'));
  } catch (_) {
    throw new Error('[staging_pg_ssl] database URL is not a valid postgres:// URL (value not shown).');
  }
}

function isSupabaseHost(hostname) {
  const h = String(hostname || '').toLowerCase();
  return h.endsWith('.supabase.com') || h.endsWith('.supabase.co');
}

function resolveCaPath(raw, repoRoot) {
  const p = String(raw || '').trim().replace(/^["']|["']$/g, '');
  if (!p) return '';
  return path.isAbsolute(p) ? p : path.resolve(repoRoot, p);
}

/**
 * @param {string} dbUrl staging connection string (never logged)
 * @param {object} [opts]
 * @param {object} [opts.env] environment (default process.env)
 * @param {boolean} [opts.allowLocal] allow plain TCP to loopback hosts (local Docker only)
 * @param {Function} [opts.readFile] file reader (tests)
 * @param {string} [opts.repoRoot] base for a relative STAGING_SUPABASE_CA_PATH
 * @returns {{ connectionString: string, ssl: false | object, host: string, verified: boolean }}
 */
function buildStagingPgConfig(dbUrl, opts = {}) {
  const env = opts.env || process.env;
  const readFile = opts.readFile || fs.readFileSync;
  const repoRoot = opts.repoRoot || path.resolve(__dirname, '../..');
  const parsed = parseDbUrl(dbUrl);
  const host = parsed.hostname.toLowerCase();
  const urlSslMode = (parsed.searchParams.get('sslmode') || '').toLowerCase();

  for (const key of [...parsed.searchParams.keys()]) {
    if (URL_SSL_PARAMS.test(key)) parsed.searchParams.delete(key);
  }
  const connectionString = parsed.toString();

  if (LOOPBACK_HOSTS.has(host)) {
    if (opts.allowLocal) return { connectionString, ssl: false, host, verified: false };
    throw new Error(`[staging_pg_ssl] refusing loopback host ${host} (not the staging database).`);
  }
  if (urlSslMode === 'disable' || urlSslMode === 'allow' || urlSslMode === 'prefer') {
    throw new Error(`[staging_pg_ssl] sslmode=${urlSslMode} is not allowed for ${host}; TLS with verification is required.`);
  }

  const caPath = resolveCaPath(env[CA_PATH_ENV], repoRoot);
  if (caPath) {
    let ca;
    try {
      ca = String(readFile(caPath, 'utf8'));
    } catch (e) {
      throw new Error(`[staging_pg_ssl] ${CA_PATH_ENV} points to a file that cannot be read (${e.code || e.message}).`);
    }
    if (!ca.includes('-----BEGIN CERTIFICATE-----')) {
      throw new Error(`[staging_pg_ssl] ${CA_PATH_ENV} is not a PEM certificate file.`);
    }
    return {
      connectionString,
      ssl: { ca, rejectUnauthorized: true, servername: host },
      host,
      verified: true,
    };
  }

  if (isSupabaseHost(host)) {
    throw new Error(
      `[staging_pg_ssl] ${CA_PATH_ENV} is not set. Supabase certificates chain to the private ` +
        '"Supabase Root 2021 CA", which Node does not trust by default. Download it from the ' +
        'Supabase dashboard (Project Settings > Database > SSL Configuration > Download ' +
        `certificate) and set ${CA_PATH_ENV} to that file (absolute, or relative to the repo root).`,
    );
  }
  // Other hosts: verify against Node's built-in public roots.
  return { connectionString, ssl: { rejectUnauthorized: true, servername: host }, host, verified: true };
}

module.exports = { buildStagingPgConfig, CA_PATH_ENV, isSupabaseHost };
