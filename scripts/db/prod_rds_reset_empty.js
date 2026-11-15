#!/usr/bin/env node
'use strict';

/**
 * Operator-only: reset application schemas on RDS when ALL app tables are empty.
 * NEVER run on production from automation. Default: --dry-print only.
 *
 * Flags:
 *   --confirm-host=<PROD_RDS_HOST>
 *   --confirm-db=doctornect
 *   --i-took-snapshot=<snapshot-id>
 *   --dry-print (default) | --execute (requires all three confirms)
 */

const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { APP_SCHEMAS } = require('../lib/migrate_prod_tripwire');

const RESET_SQL = [
  '-- Reset application schemas only (roles/extensions untouched)',
  ...APP_SCHEMAS.map(
    (s) => `DROP SCHEMA IF EXISTS ${s} CASCADE;`,
  ),
  ...APP_SCHEMAS.map((s) => `CREATE SCHEMA ${s};`),
  `GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;`,
  `GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;`,
  `GRANT USAGE ON SCHEMA private TO service_role;`,
];

function parseArgs(argv) {
  const args = argv || process.argv.slice(2);
  return {
    dryPrint: !args.includes('--execute'),
    confirmHost: (args.find((a) => a.startsWith('--confirm-host=')) || '').split('=').slice(1).join('='),
    confirmDb: (args.find((a) => a.startsWith('--confirm-db=')) || '').split('=')[1] || '',
    snapshotId: (args.find((a) => a.startsWith('--i-took-snapshot=')) || '').split('=').slice(1).join('='),
  };
}

async function assertAllAppTablesEmpty(client) {
  const tables = await client.query(
    `
    SELECT n.nspname AS schema_name, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = ANY ($1::text[]) AND c.relkind = 'r'
    ORDER BY 1, 2
    `,
    [APP_SCHEMAS],
  );
  const violations = [];
  for (const row of tables.rows) {
    const q = `SELECT count(*)::bigint AS n FROM ${row.schema_name}.${row.table_name}`;
    const res = await client.query(q);
    const n = Number(res.rows[0].n);
    if (n > 0) {
      violations.push({ table: `${row.schema_name}.${row.table_name}`, rows: n });
    }
  }
  return { tableCount: tables.rows.length, violations, totalRows: violations.reduce((s, v) => s + v.rows, 0) };
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const opts = parseArgs();

  if (opts.dryPrint) {
    console.log('# prod_rds_reset_empty — DRY PRINT (no connection)');
    console.log(`Target mask: ${maskRdsTarget(buildRdsPoolConfig())}`);
    console.log('\n-- SQL that would run after empty-table verification:');
    for (const line of RESET_SQL) console.log(line);
    console.log('\nRequired for --execute: --confirm-host= --confirm-db=doctornect --i-took-snapshot=<id>');
    return;
  }

  if (!opts.confirmHost || !opts.confirmDb || !opts.snapshotId) {
    console.error('ABORT: --execute requires --confirm-host, --confirm-db, --i-took-snapshot');
    process.exit(1);
  }

  const expectedHost = process.env.PROD_RDS_HOST;
  if (!expectedHost || opts.confirmHost !== expectedHost) {
    console.error('ABORT: --confirm-host does not match PROD_RDS_HOST');
    process.exit(1);
  }

  const pool = new Pool(buildRdsPoolConfig({ database: opts.confirmDb }));
  const client = await pool.connect();
  try {
    const empty = await assertAllAppTablesEmpty(client);
    console.log(`Tables scanned: ${empty.tableCount}; tables with rows: ${empty.violations.length}; totalRows=${empty.totalRows}`);
    if (empty.violations.length > 0) {
      console.error('ABORT: non-empty tables (names only):');
      for (const v of empty.violations) {
        console.error(`  ${v.table} rows=${v.rows}`);
      }
      process.exit(1);
    }

    console.log(`Snapshot acknowledged: ${opts.snapshotId}`);
    for (const stmt of RESET_SQL) {
      if (stmt.startsWith('--')) continue;
      await client.query(stmt);
    }
    console.log('✔ Application schemas reset.');
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('FAIL:', err.message || err);
    process.exit(1);
  });
}

module.exports = { RESET_SQL, assertAllAppTablesEmpty, parseArgs };