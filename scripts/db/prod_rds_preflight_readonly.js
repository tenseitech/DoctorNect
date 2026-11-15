#!/usr/bin/env node
'use strict';

const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const pool = new Pool(buildRdsPoolConfig({ purpose: 'migrate' }));
  console.log(`RDS target: ${maskRdsTarget(pool.options)}`);
  const client = await pool.connect();
  try {
    const ver = await client.query('SELECT version() AS v');
    console.log(`PostgreSQL: ${ver.rows[0].v.split(',')[0]}`);
    const ext = await client.query(
      `SELECT name, installed_version FROM pg_available_extensions
       WHERE name IN ('pgcrypto','plpgsql','uuid-ossp') ORDER BY name`,
    );
    console.log('extensions (available):');
    for (const row of ext.rows) {
      console.log(`  ${row.name} installed=${row.installed_version || 'null'}`);
    }
    const tables = await client.query(
      `SELECT count(*)::int AS n FROM information_schema.tables
       WHERE table_schema IN ('public','private') AND table_type='BASE TABLE'`,
    );
    console.log(`tables (public+private): ${tables.rows[0].n}`);
    const migTbl = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = '_schema_migrations'
       ) AS exists`,
    );
    if (migTbl.rows[0].exists) {
      const mig = await client.query('SELECT count(*)::int AS n FROM public._schema_migrations');
      console.log(`_schema_migrations rows: ${mig.rows[0].n}`);
    } else {
      console.log('_schema_migrations: (missing)');
    }
    const sample = await client.query(
      `SELECT table_schema, table_name FROM information_schema.tables
       WHERE table_schema IN ('public','private') AND table_type='BASE TABLE'
       ORDER BY 1, 2 LIMIT 25`,
    );
    console.log('sample tables:');
    for (const row of sample.rows) {
      console.log(`  ${row.table_schema}.${row.table_name}`);
    }
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('FAIL:', err.code || '', err.message || err);
  process.exit(1);
});