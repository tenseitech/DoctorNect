#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

async function probe(label, cfg) {
  const client = new Client({
    host: cfg.host,
    port: cfg.port,
    database: cfg.database,
    user: cfg.user,
    password: cfg.password,
    ssl: cfg.ssl,
    connectionTimeoutMillis: 15000,
  });
  try {
    await client.connect();
    await client.query('SELECT 1');
    await client.end();
    return { label, ok: true, sqlstate: null };
  } catch (e) {
    try {
      await client.end();
    } catch (_) {}
    return { label, ok: false, sqlstate: e.code || null, failure: String(e.message || e).replace(/[^\x20-\x7E]/g, ' ').slice(0, 120) };
  }
}

async function masterBootstrapReadonly(client) {
  const roles = await client.query(
    `SELECT rolname, rolcanlogin, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls
     FROM pg_roles WHERE rolname = 'doctornect_admin'`,
  );
  const bootstrapRoles = await client.query(
    `SELECT rolname FROM pg_roles WHERE rolname = ANY($1::text[]) ORDER BY 1`,
    [['anon', 'authenticated', 'service_role', 'authenticator', 'doctornect_admin']],
  );
  const ext = await client.query(`SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto','uuid-ossp','pg_stat_statements') ORDER BY 1`);
  let resetGrant = false;
  try {
    const g = await client.query(
      `SELECT has_function_privilege('doctornect_admin', 'pg_stat_statements_reset()', 'EXECUTE') AS ok`,
    );
    resetGrant = g.rows[0].ok;
  } catch (_) {
    resetGrant = false;
  }
  return {
    doctornect_admin: roles.rows[0] || null,
    bootstrap_roles_present: bootstrapRoles.rows.map((r) => r.rolname),
    extensions: ext.rows.map((r) => r.extname),
    pg_stat_statements_reset_grant_doctornect_admin: resetGrant,
  };
}

async function main() {
  const migratorCfg = buildRdsPoolConfig();
  console.log('TARGET', maskRdsTarget(migratorCfg));
  const probes = [await probe('doctornect_admin_discrete_params', migratorCfg)];

  const masterUser = getEnv('PROD_RDS_MASTER_USER') || getEnv('PROD_RDS_MASTER_USERNAME') || getEnv('RDS_MASTER_USER');
  const masterPass = getEnv('PROD_RDS_MASTER_PASSWORD') || getEnv('RDS_MASTER_PASSWORD');

  let masterSection = { skipped: true, reason: 'No PROD_RDS_MASTER_USER / PROD_RDS_MASTER_PASSWORD in .env' };
  if (masterUser && masterPass) {
    const masterCfg = buildRdsPoolConfig({ user: masterUser });
    masterCfg.password = masterPass;
    masterCfg.user = masterUser;
    probes.push(await probe('master_discrete_params', masterCfg));
    if (probes[probes.length - 1].ok) {
      const c = new Client({
        host: masterCfg.host,
        port: masterCfg.port,
        database: masterCfg.database,
        user: masterCfg.user,
        password: masterCfg.password,
        ssl: masterCfg.ssl,
      });
      await c.connect();
      try {
        await c.query('BEGIN READ ONLY');
        masterSection = { skipped: false, ...(await masterBootstrapReadonly(c)) };
        await c.query('ROLLBACK');
      } finally {
        await c.end();
      }
    }
  }

  console.log(JSON.stringify({ probes, master_bootstrap_inventory: masterSection }, null, 2));
  if (!probes[0].ok) process.exit(1);
}

main().catch((e) => {
  console.error('FAIL', e.code || '', e.message);
  process.exit(1);
});