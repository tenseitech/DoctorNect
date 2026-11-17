'use strict';

const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertProductionRdsTarget, verifyConnectedRdsSession } = require('../lib/rds_connect_guard');

async function main() {
  const db = getEnv('PROD_RDS_DB') || 'postgres';
  const cfg = buildRdsPoolConfig({ database: db });
  assertProductionRdsTarget(cfg);
  console.log('=== STAGE A (read-only) ===');
  console.log('Connect:', maskRdsTarget(cfg));
  console.log('PROD_RDS_DB from env:', db);

  const client = new Client(cfg);
  await client.connect();
  await verifyConnectedRdsSession(client, cfg);

  const dbRow = await client.query(
    'SELECT current_database() AS db, current_user AS usr, session_user AS sess',
  );
  console.log('\n-- Session --');
  console.log(dbRow.rows[0]);

  const dbs = await client.query(
    'SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1',
  );
  console.log('\n-- Databases (non-template) --');
  for (const r of dbs.rows) console.log(`  ${r.datname}`);

  const ext = await client.query(`
    SELECT name, default_version, installed_version
    FROM pg_available_extensions
    WHERE name IN ('pgcrypto','uuid-ossp','pg_cron','pg_stat_statements')
    ORDER BY name`);
  console.log('\n-- pg_available_extensions (selected) --');
  for (const r of ext.rows) {
    console.log(
      `  ${r.name}: default=${r.default_version} installed=${r.installed_version || '(none)'}`,
    );
  }

  const roles = await client.query(`
    SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolinherit
    FROM pg_roles
    WHERE rolname NOT LIKE 'pg_%' AND rolname <> 'rdsadmin'
    ORDER BY rolname`);
  console.log('\n-- Roles (excl pg_*, rdsadmin) --');
  for (const r of roles.rows) {
    console.log(
      `  ${r.rolname} login=${r.rolcanlogin} super=${r.rolsuper} createdb=${r.rolcreatedb} createrole=${r.rolcreaterole}`,
    );
  }

  const mig = await client.query(`
    SELECT count(*)::int n FROM information_schema.tables
    WHERE table_schema='public' AND table_name='_schema_migrations'`);
  const pub = await client.query(`
    SELECT count(*)::int n FROM information_schema.tables WHERE table_schema='public'`);
  console.log(`\npublic tables: ${pub.rows[0].n}; _schema_migrations: ${mig.rows[0].n > 0}`);

  await client.end();
  console.log('\n=== STAGE A complete ===');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
