#!/usr/bin/env node
'use strict';
const path = require('path');
const {
  findDuplicateEnvKeysInFile,
  formatDuplicateEnvReport,
} = require('../lib/env_duplicate_keys');
const { parseEnvFile } = require('../lib/parse_env_file');
const { findRepoRoot } = require('../lib/repo_root');
const { resolveLogicalProdRdsHost } = require('../lib/prod_rds_host_policy');

const root = findRepoRoot();
const envPath = path.join(root, '.env');
const dupes = findDuplicateEnvKeysInFile(envPath);
if (dupes.length) {
  console.log(formatDuplicateEnvReport('.env', dupes));
}
const parsed = parseEnvFile(envPath, { failOnProductionDuplicateKeys: false });

const PROD_KEYS = Object.keys(parsed).filter((k) => k.startsWith('PROD_RDS_')).sort();

function maskHost(v) {
  if (!v) return '(missing)';
  if (/^127\.0\.0\.1|localhost$/i.test(v)) return v;
  if (v.length <= 12) return '****';
  return `${v.slice(0, 8)}…${v.slice(-12)}`;
}

function maskScalar(k, v) {
  if (!v) return '(missing)';
  if (k.includes('PASSWORD')) return `(set, len=${v.length})`;
  if (k.includes('HOST') || k.includes('SERVERNAME')) return maskHost(v);
  return v;
}

const effectiveHost = resolveLogicalProdRdsHost();
const lastWin = parsed.PROD_RDS_HOST;

console.log(
  JSON.stringify(
    {
      env_path: envPath,
      duplicate_keys: dupes,
      prod_rds_keys_masked: Object.fromEntries(PROD_KEYS.map((k) => [k, maskScalar(k, parsed[k])])),
      effective_merged_last: {
        PROD_RDS_HOST: maskHost(lastWin),
        PROD_RDS_PORT: parsed.PROD_RDS_PORT,
        PROD_RDS_DB: parsed.PROD_RDS_DB,
        PROD_RDS_CONNECT_HOST: maskHost(parsed.PROD_RDS_CONNECT_HOST),
        PROD_RDS_USER: parsed.PROD_RDS_USER,
      },
      resolver_endpoint: maskHost(effectiveHost),
      checks: {
        host_is_rds_amazonaws: /\.rds\.amazonaws\.com$/i.test(effectiveHost || ''),
        port_is_5434: String(parsed.PROD_RDS_PORT || process.env.PROD_RDS_PORT) === '5434',
        db_is_doctornect: (parsed.PROD_RDS_DB || 'doctornect') === 'doctornect',
        last_prod_rds_host_is_loopback: /^(127\.0\.0\.1|localhost)$/i.test(String(lastWin || '')),
      },
      master_keys_present: Object.keys(parsed).filter((k) => /MASTER/i.test(k) && k.startsWith('PROD_')),
    },
    null,
    2,
  ),
);