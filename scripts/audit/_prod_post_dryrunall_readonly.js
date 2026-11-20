#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

(async () => {
  const u = getEnv('PROD_RDS_MASTER_USER');
  const pw = getEnv('PROD_RDS_MASTER_PASSWORD');
  const cfg = buildRdsPoolConfig({ user: u });
  cfg.user = u;
  cfg.password = pw;
  const client = new Client(cfg);
  await client.connect();
  const scratch = await client.query(
    `SELECT count(*)::int AS n FROM pg_database WHERE datname LIKE 'migrate_scratch_%'`,
  );
  const ledger = await client.query(`
    SELECT CASE WHEN to_regclass('public._schema_migrations') IS NULL THEN 0
      ELSE (SELECT count(*)::int FROM public._schema_migrations) END AS n`);
  const objs = await client.query(`
    SELECT count(*)::int AS n FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public','auth','private') AND c.relkind IN ('r','v','S','f')`);
  await client.end();
  console.log(
    JSON.stringify(
      {
        migrate_scratch_databases: scratch.rows[0].n,
        ledger_rows: ledger.rows[0].n,
        catalog_objects_public_auth_private: objs.rows[0].n,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(e.code || '', e.message);
  process.exit(1);
});