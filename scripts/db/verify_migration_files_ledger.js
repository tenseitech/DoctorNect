#!/usr/bin/env node
'use strict';

/**
 * Read-only: verify repo migration SQL files against staging _schema_migrations (checksums).
 * Usage: node scripts/db/verify_migration_files_ledger.js --confirm-live-data
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const {
  computeChecksum,
  computeLegacyRawChecksum,
  ledgerChecksumMatches,
} = require('../lib/migration_checksum');

function listRepoMigrations() {
  const dir = path.resolve('db/migrations');
  const top = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const sub = fs.existsSync(path.join(dir, 'rds'))
    ? fs.readdirSync(path.join(dir, 'rds')).filter((f) => f.endsWith('.sql')).map((f) => `rds/${f}`)
    : [];
  return [...top, ...sub.sort()];
}

async function main() {
  if (!process.argv.includes('--confirm-live-data')) {
    console.error('Refusing live staging read without --confirm-live-data');
    process.exit(1);
  }
  const url = getEnv('STAGING_SUPABASE_DB_URL');
  if (!url) {
    console.error('STAGING_SUPABASE_DB_URL missing');
    process.exit(1);
  }

  const files = listRepoMigrations();
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();
  const res = await client.query('SELECT version, name, checksum FROM public._schema_migrations ORDER BY version');
  await client.end();

  const ledger = new Map();
  for (const row of res.rows) ledger.set(row.version, row);

  const report = [];
  for (const rel of files) {
    const version = path.basename(rel).split('_')[0];
    const full = path.join('db/migrations', rel.replace(/\//g, path.sep));
    const sqlContent = fs.readFileSync(full, 'utf8');
    const checksum = computeChecksum(sqlContent);
    const row = ledger.get(version);
    const legacyRaw = computeLegacyRawChecksum(sqlContent);
    let matchKind = null;
    if (row) {
      if (row.checksum === 'legacy_supabase') {
        matchKind = 'legacy_supabase';
      } else if (row.checksum === checksum) {
        matchKind = 'normalized';
      } else if (row.checksum === legacyRaw) {
        matchKind = 'legacy_raw';
      } else if (ledgerChecksumMatches(sqlContent, row.checksum)) {
        matchKind = 'legacy_raw';
      }
    }
    report.push({
      file: rel,
      version,
      inLedger: Boolean(row),
      checksumMatch: row ? Boolean(matchKind) : null,
      checksumMatchKind: matchKind,
      ledgerChecksum: row ? row.checksum : null,
      repoChecksumPrefix: checksum.slice(0, 8),
    });
  }

  const ghost = res.rows.filter((r) => !files.some((f) => f.startsWith(`${r.version}_`)));
  const drift = report.filter((r) => r.inLedger && r.checksumMatch === false);
  const notInLedger = report.filter((r) => !r.inLedger && !r.file.startsWith('rds/'));
  const rdsOnly = report.filter((r) => !r.inLedger && r.file.startsWith('rds/'));

  console.log(`Staging: ${maskConnectionString(url)}`);
  console.log(`Ledger rows: ${res.rows.length} | Repo SQL files: ${files.length}`);
  for (const row of report) {
    const status = !row.inLedger ? 'NOT_IN_LEDGER' : row.checksumMatch ? 'OK' : 'CHECKSUM_DRIFT';
    console.log(`${status.padEnd(16)} ${row.version} ${row.file}`);
  }
  if (ghost.length) {
    console.log('\nLedger versions without repo file (expected ghost handling for 20261104000001):');
    for (const g of ghost) console.log(`  - ${g.version} (${g.name})`);
  }
  if (rdsOnly.length) {
    console.log(`\nRDS-only (expected NOT on staging Supabase): ${rdsOnly.map((r) => r.file).join(', ')}`);
  }
  if (notInLedger.length) {
    console.error(`\n${notInLedger.length} repo file(s) not in staging ledger`);
    process.exit(1);
  }
  if (drift.length) {
    console.error(`\n${drift.length} checksum drift(s)`);
    process.exit(1);
  }
  console.log('\n✅ All repo migration files present on staging with matching checksums');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
