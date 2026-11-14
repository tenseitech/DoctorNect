#!/usr/bin/env node
'use strict';

/**
 * Read-only: verify repo migration SQL files against _schema_migrations (checksums).
 *
 *   node scripts/db/verify_migration_files_ledger.js --target=staging --confirm-live-data
 *   node scripts/db/verify_migration_files_ledger.js --target=rehearsal --confirm-live-data --confirm=<PROD_RDS_HOST>
 *   node scripts/db/verify_migration_files_ledger.js --target=production --confirm-live-data --confirm=<PROD_RDS_HOST>
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { assertDatabaseGuard } = require('../lib/env_guard');
const {
  computeChecksum,
  computeLegacyRawChecksum,
  ledgerChecksumMatches,
} = require('../lib/migration_checksum');
const { GHOST_STAGING_LEDGER_VERSION } = require('../lib/live_data_guard');
const { listMigrationsForTarget, migrationRelPathToAbs } = require('../lib/migration_file_list');

const STAGING_GHOST_VERSIONS = new Set([GHOST_STAGING_LEDGER_VERSION]);

function resolveCliTarget() {
  const arg = process.argv.find((a) => a.startsWith('--target='));
  return arg ? arg.split('=')[1].toLowerCase() : 'staging';
}

function listRepoMigrationsForVerifyTarget(target) {
  if (target === 'staging') {
    return listMigrationsForTarget('staging');
  }
  return listMigrationsForTarget('production');
}

async function connectForTarget(target) {
  if (target === 'staging') {
    const url = getEnv('STAGING_SUPABASE_DB_URL');
    if (!url) {
      throw new Error('STAGING_SUPABASE_DB_URL missing');
    }
    assertDatabaseGuard({
      targetKind: 'staging',
      operationName: 'verify_migration_files_ledger',
      allowDestructive: false,
      targetHost: null,
    });
    const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
    await client.connect();
    return { client, mask: maskConnectionString(url), label: 'staging Supabase' };
  }
  if (target === 'production' || target === 'rehearsal') {
    const dbName = target === 'rehearsal' ? 'doctornect_rehearsal' : getEnv('PROD_RDS_DB') || 'doctornect';
    assertDatabaseGuard({
      targetKind: 'production',
      operationName: `verify_migration_files_ledger (${target})`,
      allowDestructive: false,
      targetHost: getEnv('PROD_RDS_HOST'),
    });
    const cfg = buildRdsPoolConfig({ database: dbName });
    const client = new Client(cfg);
    await client.connect();
    return { client, mask: maskConnectionString(`postgresql://****@${cfg.host}:${cfg.port}/${dbName}`), label: target };
  }
  throw new Error(`Unsupported --target=${target} (use staging, rehearsal, or production)`);
}

async function main() {
  const target = resolveCliTarget();
  if (!process.argv.includes('--confirm-live-data')) {
    console.error(`Refusing live ${target} read without --confirm-live-data`);
    process.exit(1);
  }

  const files = listRepoMigrationsForVerifyTarget(target);
  const { client, mask, label } = await connectForTarget(target);
  let res;
  try {
    res = await client.query(
      'SELECT version, name, checksum FROM public._schema_migrations ORDER BY version',
    );
  } finally {
    await client.end();
  }

  const ledger = new Map();
  for (const row of res.rows) ledger.set(row.version, row);

  const report = [];
  for (const rel of files) {
    const version = path.basename(rel).split('_')[0];
    const full = migrationRelPathToAbs(rel);
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

  const ghost = res.rows.filter(
    (r) =>
      !files.some((f) => path.basename(f).split('_')[0] === r.version) &&
      !(target === 'staging' && STAGING_GHOST_VERSIONS.has(r.version)),
  );
  const drift = report.filter((r) => r.inLedger && r.checksumMatch === false);
  const notInLedger = report.filter((r) => !r.inLedger && !r.file.startsWith('rds/'));
  const rdsOnly = report.filter((r) => !r.inLedger && r.file.startsWith('rds/'));

  console.log(`Target: ${label} (${mask})`);
  console.log(`Ledger rows: ${res.rows.length} | Repo SQL files: ${files.length}`);
  for (const row of report) {
    const status = !row.inLedger ? 'NOT_IN_LEDGER' : row.checksumMatch ? 'OK' : 'CHECKSUM_DRIFT';
    console.log(`${status.padEnd(16)} ${row.version} ${row.file}`);
  }
  if (ghost.length) {
    console.log('\nLedger versions without repo file (unexpected ghosts):');
    for (const g of ghost) console.log(`  - ${g.version} (${g.name})`);
  }
  if (target === 'staging' && rdsOnly.length) {
    console.log(`\nRDS-only (expected NOT on staging Supabase): ${rdsOnly.map((r) => r.file).join(', ')}`);
  }
  if (target !== 'staging' && rdsOnly.length) {
    console.error(`\n${rdsOnly.length} RDS-only migration(s) missing from ${target} ledger — run migrate after bootstrap.`);
    process.exit(1);
  }
  if (notInLedger.length) {
    console.error(`\n${notInLedger.length} shared repo file(s) not in ${target} ledger`);
    process.exit(1);
  }
  if (drift.length) {
    console.error(`\n${drift.length} checksum drift(s)`);
    process.exit(1);
  }
  if (ghost.length) {
    console.error(`\n${ghost.length} unexpected ghost ledger version(s) on ${target}`);
    process.exit(1);
  }
  console.log(`\n✅ All repo migration files for --target=${target} match ledger checksums`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});