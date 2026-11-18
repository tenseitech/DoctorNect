'use strict';

const fs = require('fs');
const path = require('path');
const { getEnv } = require('./env_loader');
const { findRepoRoot } = require('./repo_root');

/**
 * Prefer *.rds.amazonaws.com over loopback when .env lists PROD_RDS_HOST more than once.
 */
function resolveLogicalProdRdsHost() {
  const root = findRepoRoot();
  const envPath = path.join(root, '.env');
  const hosts = [];
  if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^\s*PROD_RDS_HOST\s*=\s*(.*)\s*$/);
      if (!m) continue;
      let v = m[1].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
      hosts.push(v);
    }
  }
  return (
    hosts.find((h) => h && /\.rds\.amazonaws\.com$/i.test(h)) ||
    hosts.find((h) => h && !/^(127\.0\.0\.1|localhost)$/i.test(h)) ||
    getEnv('PROD_RDS_HOST') ||
    ''
  );
}

function assertProdRdsLogicalHostNotLoopback(operation = 'RDS operation') {
  const logical = (getEnv('PROD_RDS_HOST') || '').trim().toLowerCase();
  const resolved = (resolveLogicalProdRdsHost() || '').trim().toLowerCase();
  const bad = (h) => !h || h === '127.0.0.1' || h === 'localhost' || h === '::1';

  if (bad(logical)) {
    const err = new Error(
      `[ENV GUARD] ${operation}: PROD_RDS_HOST must be the logical RDS *.rds.amazonaws.com endpoint (got loopback). ` +
        'Set PROD_RDS_CONNECT_HOST=127.0.0.1 for the tunnel; remove duplicate PROD_RDS_HOST=127.0.0.1 from .env.',
    );
    err.code = 'PROD_RDS_HOST_LOOPBACK';
    throw err;
  }
  if (!logical.includes('.rds.amazonaws.com') && !resolved.includes('.rds.amazonaws.com')) {
    const err = new Error(
      `[ENV GUARD] ${operation}: PROD_RDS_HOST must end with .rds.amazonaws.com for production guards and TLS.`,
    );
    err.code = 'PROD_RDS_HOST_NOT_RDS';
    throw err;
  }
  if (bad(resolved) && !logical.includes('.rds.amazonaws.com')) {
    const err = new Error(
      `[ENV GUARD] ${operation}: could not resolve a valid RDS endpoint from .env (duplicate or missing PROD_RDS_HOST).`,
    );
    err.code = 'PROD_RDS_HOST_UNRESOLVED';
    throw err;
  }
}

module.exports = {
  resolveLogicalProdRdsHost,
  assertProdRdsLogicalHostNotLoopback,
};