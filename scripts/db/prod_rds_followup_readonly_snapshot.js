#!/usr/bin/env node
'use strict';

/**
 * Read-only production RDS snapshot (tunnel). Writes JSON under docs/audit-local/ (not committed).
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const poolConfig = buildRdsPoolConfig();
  const pool = new Pool(poolConfig);
  const client = await pool.connect();
  const out = {
    captured_at: new Date().toISOString(),
    target_mask: maskRdsTarget(poolConfig),
    database: poolConfig.database,
  };

  try {
    await client.query('BEGIN READ ONLY');
    const sess = await client.query(
      'SELECT current_user, session_user, current_database() AS db',
    );
    out.session = sess.rows[0];

    const cronDb = await client.query('SHOW cron.database_name');
    const preload = await client.query('SHOW shared_preload_libraries');
    const cronRow = cronDb.rows[0] || {};
    out.pg_cron = {
      database_name:
        cronRow.cron_database_name
        ?? cronRow['cron.database_name']
        ?? null,
    };
    out.shared_preload_libraries = preload.rows[0].shared_preload_libraries;

    const keys = await client.query(
      'SELECT config_key FROM public.system_config ORDER BY config_key',
    );
    out.system_config_keys = keys.rows.map((r) => r.config_key);

    const grants = await client.query(`
      SELECT grantee, table_name, privilege_type, is_grantable
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND grantee IN ('anon', 'authenticated')
      ORDER BY grantee, table_name, privilege_type
    `);
    out.role_table_grants_summary = {
      row_count: grants.rows.length,
      by_grantee: grants.rows.reduce((acc, row) => {
        const g = row.grantee;
        acc[g] = acc[g] || { tables: new Set(), privileges: {} };
        acc[g].tables.add(row.table_name);
        const key = `${row.table_name}:${row.privilege_type}`;
        acc[g].privileges[key] = row.is_grantable;
        return acc;
      }, {}),
    };
    for (const g of Object.keys(out.role_table_grants_summary.by_grantee)) {
      const entry = out.role_table_grants_summary.by_grantee[g];
      out.role_table_grants_summary.by_grantee[g] = {
        distinct_tables: [...entry.tables].sort(),
        privilege_entries: Object.keys(entry.privileges).length,
      };
    }

    await client.query('COMMIT');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
    await pool.end();
  }

  const dir = path.join(__dirname, '../../docs/audit-local');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `prod_readonly_followup_${Date.now()}.json`);
  fs.writeFileSync(file, JSON.stringify(out, null, 2));
  console.log(`Wrote ${file}`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error('FAIL:', err.message || err);
    process.exit(1);
  });
}