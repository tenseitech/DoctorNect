#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

loadRootEnv();

async function main() {
  const cfg = buildRdsPoolConfig();
  const client = new Client(cfg);
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');
    const preload = await client.query(`SHOW shared_preload_libraries`);
    let rdsExt = null;
    try {
      rdsExt = await client.query(`SHOW rds.extensions`);
    } catch (e) {
      rdsExt = { rows: [{ note: `SHOW rds.extensions unavailable: ${e.code || e.message}` }] };
    }
    const avail = await client.query(
      `SELECT name, default_version, installed_version, comment FROM pg_available_extensions WHERE name = 'pg_cron'`,
    );
    const installed = await client.query(`SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_cron'`);
    console.log(
      JSON.stringify(
        {
          target: maskRdsTarget(cfg),
          shared_preload_libraries: preload.rows[0].shared_preload_libraries,
          rds_extensions: rdsExt.rows[0],
          pg_cron_available: avail.rows,
          pg_cron_installed: installed.rows,
        },
        null,
        2,
      ),
    );
    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error('FAIL', e.message);
  process.exit(1);
});