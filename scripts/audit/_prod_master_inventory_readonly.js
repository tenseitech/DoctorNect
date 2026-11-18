#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');
const { resolveLogicalProdRdsHost } = require('../lib/prod_rds_host_policy');

loadRootEnv();

function maskHost(h) {
  if (!h || h.length < 16) return '****';
  return `${h.slice(0, 8)}…${h.slice(-14)}`;
}

async function inventory02_03(client) {
  const authSchema = await client.query(`SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') AS ok`);
  const jwt = await client.query(`
    SELECT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'auth' AND p.proname = 'jwt'
    ) AS ok`);
  const supa = await client.query(`SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') AS ok`);
  const authUsers = await client.query(`SELECT to_regclass('auth.users') IS NOT NULL AS ok`);
  const priv = await client.query(`SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'private') AS ok`);
  const privGrant = await client.query(
    `SELECT has_schema_privilege('authenticated', 'private', 'USAGE') AS ok`,
  );
  const gap02 = [];
  if (!jwt.rows[0].ok) gap02.push('auth.jwt()');
  if (!authSchema.rows[0].ok) gap02.push('auth schema');
  const gap03 = [];
  if (!supa.rows[0].ok) gap03.push('supabase_admin stub');
  if (!authUsers.rows[0].ok) gap03.push('auth.users stub');
  if (!priv.rows[0].ok) gap03.push('private schema');
  if (!privGrant.rows[0].ok) gap03.push('GRANT USAGE ON SCHEMA private TO authenticated');
  return { gap02: gap02.length ? gap02 : null, gap03: gap03.length ? gap03 : null };
}

async function pgCronSql(client) {
  const preload = await client.query(`SHOW shared_preload_libraries`);
  let cronDb = null;
  try {
    cronDb = await client.query(`SHOW cron.database_name`);
  } catch (e) {
    cronDb = { rows: [{ note: e.code || 'unavailable' }] };
  }
  let rdsExt = null;
  try {
    rdsExt = await client.query(`SHOW rds.extensions`);
  } catch (e) {
    rdsExt = { rows: [{ note: e.code || 'unavailable' }] };
  }
  const avail = await client.query(
    `SELECT name, installed_version FROM pg_available_extensions WHERE name = 'pg_cron'`,
  );
  const installed = await client.query(`SELECT extname FROM pg_extension WHERE extname = 'pg_cron'`);
  const libs = String(preload.rows[0].shared_preload_libraries || '');
  const pgCronPreloaded = /\bpg_cron\b/i.test(libs);
  return {
    shared_preload_libraries: libs,
    pg_cron_in_shared_preload: pgCronPreloaded,
    cron_database_name: cronDb.rows[0],
    rds_extensions: rdsExt.rows[0],
    pg_cron_available: avail.rows,
    pg_cron_installed: installed.rows,
  };
}

async function main() {
  const masterUser = getEnv('PROD_RDS_MASTER_USER') || getEnv('PROD_RDS_MASTER_USERNAME') || getEnv('RDS_MASTER_USER');
  const masterPass = getEnv('PROD_RDS_MASTER_PASSWORD') || getEnv('RDS_MASTER_PASSWORD');
  if (!masterUser || !masterPass) {
    console.log(
      JSON.stringify({
        error: 'PROD_RDS_MASTER_USER and PROD_RDS_MASTER_PASSWORD required in .env for master inventory',
        master_keys_checked: ['PROD_RDS_MASTER_USER', 'PROD_RDS_MASTER_USERNAME', 'RDS_MASTER_USER'],
      }),
    );
    process.exit(2);
  }

  const masterCfg = buildRdsPoolConfig({ user: masterUser });
  masterCfg.password = masterPass;
  masterCfg.user = masterUser;
  console.log('MASTER_TARGET', maskRdsTarget(masterCfg));

  const client = new Client({
    host: masterCfg.host,
    port: masterCfg.port,
    database: masterCfg.database,
    user: masterCfg.user,
    password: masterCfg.password,
    ssl: masterCfg.ssl,
    connectionTimeoutMillis: 20000,
  });
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');
    const id = await client.query(`
      SELECT current_user, version() AS ver,
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_superuser') AS rds_superuser,
        inet_server_port() AS server_port`);
    const docRole = await client.query(
      `SELECT rolname, rolcanlogin, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls
       FROM pg_roles WHERE rolname = 'doctornect_admin'`,
    );
    const bootstrapRoles = await client.query(
      `SELECT rolname FROM pg_roles WHERE rolname = ANY($1::text[]) ORDER BY 1`,
      [['anon', 'authenticated', 'service_role', 'authenticator', 'doctornect_admin', 'app_migrator']],
    );
    const ext = await client.query(
      `SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto','uuid-ossp','pg_stat_statements') ORDER BY 1`,
    );
    let resetGrant = null;
    try {
      const g = await client.query(
        `SELECT has_function_privilege('doctornect_admin', 'pg_stat_statements_reset()', 'EXECUTE') AS ok`,
      );
      resetGrant = g.rows[0].ok;
    } catch (_) {
      resetGrant = false;
    }
    const ledger = await client.query(`SELECT count(*)::int AS n FROM public._schema_migrations`);
    const pub = await client.query(`
      SELECT count(*)::int AS n FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r'`);
    const gaps = await inventory02_03(client);
    const cron = await pgCronSql(client);

    let verdict = 'GREENFIELD';
    if (ledger.rows[0].n > 0 || pub.rows[0].n > 30) verdict = 'POPULATED';
    else if (
      docRole.rows.length === 0 ||
      bootstrapRoles.rows.length < 4 ||
      gaps.gap02 ||
      gaps.gap03 ||
      pub.rows[0].n > 0
    ) {
      verdict = 'PARTIAL';
    }

    const logicalHost = resolveLogicalProdRdsHost();
    console.log(
      JSON.stringify(
        {
          identity: {
            connect: '127.0.0.1:' + masterCfg.port,
            logical_host_masked: maskHost(logicalHost),
            ssl: !!masterCfg.ssl,
            version: String(id.rows[0].ver).slice(0, 60),
            rds_superuser: id.rows[0].rds_superuser,
            server_port: id.rows[0].server_port,
          },
          verdict,
          doctornect_admin: docRole.rows[0] || null,
          bootstrap_01_roles_present: bootstrapRoles.rows.map((r) => r.rolname),
          bootstrap_01_extensions: ext.rows.map((r) => r.extname),
          pg_stat_statements_reset_grant_doctornect_admin: resetGrant,
          bootstrap_02_missing: gaps.gap02,
          bootstrap_03_missing: gaps.gap03,
          ledger_rows: ledger.rows[0].n,
          public_table_count: pub.rows[0].n,
          pg_cron: cron,
          pg_cron_blocks_migrate: !cron.pg_cron_in_shared_preload,
        },
        null,
        2,
      ),
    );
    await client.query('ROLLBACK');
    if (!cron.pg_cron_in_shared_preload) process.exit(3);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error('FAIL', e.code || '', String(e.message).slice(0, 200));
  process.exit(1);
});