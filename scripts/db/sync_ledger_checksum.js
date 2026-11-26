'use strict';

/**
 * One-off: align _schema_migrations.checksum with on-disk file when SQL was
 * edited after apply (no SQL re-run). Requires --confirm-live-data.
 */
const fs = require('fs');
const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');
const { computeChecksum } = require('./migrate');
const { buildStagingPgConfig, CA_PATH_ENV } = require('../lib/staging_pg_ssl');

// Verified TLS (STAGING_SUPABASE_CA_PATH); shared with migrate.js and the demo seed.
function buildPoolConfig(dbUrl) {
  const env = { ...process.env, [CA_PATH_ENV]: getEnv(CA_PATH_ENV) };
  const { connectionString, ssl } = buildStagingPgConfig(dbUrl, { env });
  return { connectionString, ssl };
}

async function main() {
  bootstrapMutatingScript('scripts/db/sync_ledger_checksum.js');
  const version = process.argv.find((a) => a.startsWith('--version='))?.split('=')[1];
  const fileArg = process.argv.find((a) => a.startsWith('--file='))?.split('=')[1];
  if (!version || !fileArg) {
    console.error('Usage: node scripts/db/sync_ledger_checksum.js --version=20261103000008 --file=20261103000008_staging_anon_security_cleanup.sql --confirm-live-data');
    process.exit(1);
  }

  const sqlPath = require('path').resolve('db/migrations', fileArg);
  const checksum = computeChecksum(fs.readFileSync(sqlPath, 'utf8'));
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  const pool = new Pool(buildPoolConfig(dbUrl));

  const before = await pool.query(
    'SELECT version, checksum FROM public._schema_migrations WHERE version = $1',
    [version],
  );
  if (!before.rows.length) {
    console.error(`No ledger row for version ${version}`);
    process.exit(1);
  }
  console.log(`Ledger checksum (before): ${before.rows[0].checksum}`);
  console.log(`On-disk checksum:         ${checksum}`);

  if (before.rows[0].checksum === checksum) {
    console.log('Already in sync.');
    await pool.end();
    return;
  }

  const updated = await pool.query(
    'UPDATE public._schema_migrations SET checksum = $1 WHERE version = $2 RETURNING version',
    [checksum, version],
  );
  console.log(`Updated ${updated.rowCount} row(s) for version ${version}`);
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
