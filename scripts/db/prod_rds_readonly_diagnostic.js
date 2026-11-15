#!/usr/bin/env node
'use strict';

/**
 * Production / RDS tunnel diagnostics — READ ONLY (no DDL).
 * Uses buildRdsPoolConfig from repo .env (tunnel: PROD_RDS_CONNECT_HOST=127.0.0.1).
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

function ts() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function q(client, sql, params) {
  const res = await client.query(sql, params);
  return res.rows;
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const outDir = path.resolve(__dirname, '../../docs/audit');
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `prod_rds_readonly_diagnostic_${ts()}.json`);

  const pool = new Pool(buildRdsPoolConfig());
  const lines = [];
  const log = (msg) => {
    console.log(msg);
    lines.push(msg);
  };

  log(`RDS target: ${maskRdsTarget(pool.options)}`);
  const client = await pool.connect();

  const report = { at: new Date().toISOString() };

  try {
    try {
    await client.query('BEGIN READ ONLY');

    report.session = (await q(
      client,
      `SELECT current_user, current_database(), current_setting('search_path') AS search_path, version()`,
    ))[0];

    log('\n=== SESSION ===');
    log(JSON.stringify(report.session, null, 2));

    report.schemas = await q(
      client,
      `SELECT nspname AS schema_name, pg_get_userbyid(nspowner) AS owner
       FROM pg_namespace
       WHERE nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
         AND nspname <> 'information_schema'
       ORDER BY nspname`,
    );
    log(`\n=== NON-SYSTEM SCHEMAS (${report.schemas.length}) ===`);
    for (const row of report.schemas) {
      log(`  ${row.schema_name} (owner=${row.owner})`);
    }

    report.relkinds = await q(
      client,
      `SELECT n.nspname AS schema_name,
              CASE c.relkind
                WHEN 'r' THEN 'table'
                WHEN 'i' THEN 'index'
                WHEN 'v' THEN 'view'
                WHEN 'S' THEN 'sequence'
                WHEN 'm' THEN 'matview'
                ELSE c.relkind::text
              END AS relkind,
              count(*)::int AS n
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
         AND n.nspname <> 'information_schema'
         AND c.relkind IN ('r', 'i', 'v', 'S')
       GROUP BY 1, 2
       ORDER BY 1, 2`,
    );
    log('\n=== RELKIND COUNTS BY SCHEMA ===');
    console.table(report.relkinds);

    report.role_exists = await q(
      client,
      `SELECT r.rolname,
              r.rolsuper,
              r.rolcreaterole,
              r.rolcreatedb,
              r.rolcanlogin,
              EXISTS (SELECT 1 FROM pg_auth_members m
                      JOIN pg_roles parent ON parent.oid = m.roleid
                      WHERE m.member = r.oid AND parent.rolname = 'rds_superuser') AS has_rds_superuser
       FROM pg_roles r
       WHERE r.rolname IN ('postgres', 'rdsadmin', 'doctornect_admin', 'anon', 'authenticated',
                           'service_role', 'authenticator', 'app_migrator', 'rds_master', 'rds_superuser')
       ORDER BY r.rolname`,
    );
    log('\n=== KEY ROLES ===');
    console.table(report.role_exists);

    report.all_app_roles = await q(
      client,
      `SELECT rolname, rolcanlogin, rolsuper, rolcreaterole
       FROM pg_roles
       WHERE rolname NOT LIKE 'pg\\_%' ESCAPE '\\'
         AND rolname <> 'rdsadmin'
       ORDER BY rolname`,
    );

    report.role_settings = await q(
      client,
      `SELECT r.rolname, s.setting
       FROM pg_db_role_setting d
       JOIN pg_roles r ON r.oid = d.setrole
       CROSS JOIN LATERAL unnest(d.setconfig) AS s(setting)
       WHERE s.setting ILIKE '%search_path%'
       ORDER BY r.rolname`,
    );
    log('\n=== ROLE search_path SETTINGS ===');
    if (report.role_settings.length) console.table(report.role_settings);
    else log('  (none)');

    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  }

  try {
    const guc = await client.query(`SHOW shared_preload_libraries`);
    report.shared_preload_libraries = guc.rows[0].shared_preload_libraries;
    log(`\nshared_preload_libraries=${report.shared_preload_libraries}`);
  } catch (e) {
    report.shared_preload_libraries_error = e.message;
  }

  try {
    const cronDb = await client.query(`SHOW cron.database_name`);
    report.cron_database_name = cronDb.rows[0].cron_database_name;
    log(`cron.database_name=${report.cron_database_name}`);
  } catch (e) {
    report.cron_database_name_error = e.message;
  }

  report.pg_cron = await q(
    client,
    `SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_cron'`,
  );

  report.ledger = await q(
    client,
    `SELECT EXISTS (
       SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname = '_schema_migrations'
     ) AS ledger_exists`,
  );
  if (report.ledger[0]?.ledger_exists) {
    report.migration_count = (
      await q(client, `SELECT count(*)::int AS n FROM public._schema_migrations`)
    )[0];
    report.migrations_sample = await q(
      client,
      `SELECT version, name FROM public._schema_migrations ORDER BY version LIMIT 20`,
    );
  }

  report.object_inventory = await q(
    client,
    `SELECT n.nspname AS schema_name,
            pg_get_userbyid(c.relowner) AS owner,
            CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'i' THEN 'index' ELSE c.relkind::text END AS kind,
            count(*)::int AS n
     FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
       AND n.nspname <> 'information_schema'
     GROUP BY 1, 2, 3
     ORDER BY n DESC, 1, 2
     LIMIT 80`,
  );

  report.extensions_installed = await q(
    client,
    `SELECT extname, n.nspname AS schema, pg_get_userbyid(e.extowner) AS owner
     FROM pg_extension e
     JOIN pg_namespace n ON n.oid = e.extnamespace
     ORDER BY extname`,
  );

  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
  fs.writeFileSync(
    path.join(outDir, 'prod_rds_readonly_diagnostic_latest.txt'),
    lines.join('\n'),
  );
  log(`\nWrote ${outPath}`);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('FAIL:', err.code || '', err.message || err);
  process.exit(1);
});