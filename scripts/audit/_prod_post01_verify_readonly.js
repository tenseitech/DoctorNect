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
  const ext = await client.query(
    `SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto','uuid-ossp','pg_stat_statements') ORDER BY 1`,
  );
  let reset = { rows: [{ ok: false }] };
  try {
    reset = await client.query(
      `SELECT has_function_privilege('doctornect_admin', 'pg_stat_statements_reset()', 'EXECUTE') AS ok`,
    );
  } catch (e) {
    if (e.code !== '42883') throw e;
  }
  const pub = await client.query(`SELECT pubname FROM pg_publication WHERE pubname = 'supabase_realtime'`);
  const fnExists = await client.query(
    `SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pg_catalog' AND p.proname='pg_stat_statements_reset') AS ok`,
  );
  await client.end();
  console.log(
    JSON.stringify(
      {
        extensions: ext.rows.map((r) => r.extname),
        pg_stat_statements_reset_function_exists: fnExists.rows[0].ok,
        pg_stat_statements_reset_grant: reset.rows[0].ok,
        supabase_realtime: pub.rows[0]?.pubname || null,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(e.code, e.message);
  process.exit(1);
});