#!/usr/bin/env node
'use strict';
/** Exact count(*) for public schema tables with rows; auth.users if present. Read-only. */
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

async function main() {
  const expectedPort = Number(process.env.PROD_RDS_PORT || '5434');
  const cfg = buildRdsPoolConfig({
    user: getEnv('PROD_RDS_MASTER_USER') || getEnv('PROD_RDS_USER'),
  });
  cfg.user = getEnv('PROD_RDS_MASTER_USER') || cfg.user;
  cfg.password = getEnv('PROD_RDS_MASTER_PASSWORD') || getEnv('PROD_RDS_PASSWORD');

  if (Number(cfg.port) !== expectedPort) {
    console.error(`HARD_ABORT: expected tunnel port ${expectedPort}, connect port ${cfg.port}`);
    process.exit(2);
  }
  const sslMode = (process.env.PROD_RDS_SSLMODE || 'verify-full').toLowerCase();
  if (sslMode === 'disable' || sslMode === 'off' || cfg.ssl === false) {
    console.error('HARD_ABORT: verify-full required');
    process.exit(2);
  }

  console.log('target', maskRdsTarget(cfg));
  const client = new Client(cfg);
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');

    const authExists = await client.query(`SELECT to_regclass('auth.users') IS NOT NULL AS ok`);
    const out = { mask_target: maskRdsTarget(cfg), nonempty: {} };

    if (authExists.rows[0].ok) {
      const r = await client.query('SELECT count(*)::bigint AS c FROM auth.users');
      const c = Number(r.rows[0].c);
      if (c > 0) out.nonempty['auth.users'] = c;
      else out.explicit_zero = { ...(out.explicit_zero || {}), 'auth.users': 0 };
    } else {
      out.auth_users = 'absent';
    }

    const pu = await client.query('SELECT count(*)::bigint AS c FROM public.users');
    const puN = Number(pu.rows[0].c);
    if (puN > 0) out.nonempty['public.users'] = puN;
    else out.explicit_zero = { ...(out.explicit_zero || {}), 'public.users': 0 };

    const tables = await client.query(`
      SELECT c.relname AS table_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind = 'r'
        AND c.relname NOT IN ('users')
      ORDER BY c.relname
    `);

    for (const { table_name } of tables.rows) {
      const r = await client.query(`SELECT count(*)::bigint AS c FROM public."${table_name.replace(/"/g, '""')}"`);
      const c = Number(r.rows[0].c);
      if (c > 0) out.nonempty[`public.${table_name}`] = c;
    }

    const cronSchema = await client.query(`SELECT to_regnamespace('cron') IS NOT NULL AS ok`);
    if (cronSchema.rows[0].ok) {
      const cronTables = await client.query(`
        SELECT c.relname AS table_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'cron' AND c.relkind = 'r'
        ORDER BY c.relname
      `);
      out.cron_nonempty = {};
      for (const { table_name } of cronTables.rows) {
        const r = await client.query(`SELECT count(*)::bigint AS c FROM cron."${table_name.replace(/"/g, '""')}"`);
        const c = Number(r.rows[0].c);
        if (c > 0) out.cron_nonempty[`cron.${table_name}`] = c;
      }
    }

    await client.query('ROLLBACK');
    out.nonempty_count = Object.keys(out.nonempty).length;
    console.log(JSON.stringify(out, null, 2));
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.code || '', e.message);
  process.exit(1);
});