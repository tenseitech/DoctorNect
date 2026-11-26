#!/usr/bin/env node
'use strict';
/** Read-only prod RDS inventory (stdout only, no file writes). */
const { Client } = require('pg');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

const APP_TABLES = [
  'users',
  'doctors',
  'patients',
  'appointments',
  'admin_users',
  'notification_outbox',
];

const BOOTSTRAP_ROLES = [
  'anon',
  'authenticated',
  'service_role',
  'authenticator',
  'app_migrator',
  'doctornect_admin',
];

async function main() {
  const cfg = buildRdsPoolConfig();
  const expectedPort = Number(process.env.PROD_RDS_PORT || '5434');
  const connectPort = Number(cfg.port);
  if (connectPort !== expectedPort) {
    console.error(
      `HARD_ABORT: PROD forensics must use tunnel port ${expectedPort}, got connect port ${connectPort} (refuse Docker :5442 bleed)`,
    );
    process.exit(2);
  }
  const sslMode = (process.env.PROD_RDS_SSLMODE || 'verify-full').toLowerCase();
  if (sslMode === 'disable' || sslMode === 'off' || cfg.ssl === false) {
    console.error('HARD_ABORT: PROD forensics requires TLS (verify-full); ssl disabled');
    process.exit(2);
  }
  console.log('target', maskRdsTarget(cfg));
  const client = new Client(cfg);
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');

    const identity = await client.query(`
      SELECT
        current_user,
        current_database(),
        version(),
        inet_server_port() AS server_port,
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_superuser') AS has_rds_superuser,
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rdsadmin') AS has_rdsadmin_docker_stub
    `);
    const id = identity.rows[0];
  const ver = String(id.version || '');
  if (id.has_rdsadmin_docker_stub && !id.has_rds_superuser) {
    console.error('HARD_ABORT: looks like Docker rdslike (rdsadmin, no rds_superuser), not AWS RDS');
    process.exit(2);
  }
  if (!id.has_rds_superuser) {
    console.error('HARD_ABORT: missing rds_superuser role (expected on DoctorNect RDS after bootstrap 01)');
    process.exit(2);
  }
  if (!ver.includes('18.3')) {
    console.error(`HARD_ABORT: expected PostgreSQL 18.3 on prod RDS, got: ${ver.slice(0, 80)}`);
    process.exit(2);
  }
  if (Number(id.server_port) !== 5432) {
    console.error(`HARD_ABORT: inet_server_port expected 5432 on RDS server, got ${id.server_port}`);
    process.exit(2);
  }
  console.log(
    'SESSION',
    JSON.stringify({
      current_user: id.current_user,
      current_database: id.current_database,
      version: ver.slice(0, 60),
      server_port: id.server_port,
      tunnel_connect_port: connectPort,
      ssl: true,
      rds_superuser: id.has_rds_superuser,
    }),
  );

    const ledger = await client.query(`
      SELECT CASE WHEN to_regclass('public._schema_migrations') IS NULL THEN 0
        ELSE (SELECT count(*)::int FROM public._schema_migrations) END AS n`);
    console.log('LEDGER_ROWS', ledger.rows[0].n);

    const schemas = await client.query(`
      SELECT nspname FROM pg_namespace
      WHERE nspname IN ('public','private','auth','extensions')
      ORDER BY 1`);
    console.log('CORE_SCHEMAS', schemas.rows.map((r) => r.nspname));

    const counts = await client.query(`
      SELECT n.nspname AS schema,
        sum(CASE WHEN c.relkind = 'r' THEN 1 ELSE 0 END)::int AS tables,
        sum(CASE WHEN c.relkind = 'v' THEN 1 ELSE 0 END)::int AS views
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public','private','auth','extensions')
      GROUP BY 1 ORDER BY 1`);

    const funcs = await client.query(`
      SELECT n.nspname AS schema, count(*)::int AS functions
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname IN ('public','private','auth')
      GROUP BY 1 ORDER BY 1`);

    const pol = await client.query(`
      SELECT schemaname, count(*)::int AS policies
      FROM pg_policies
      WHERE schemaname IN ('public','private')
      GROUP BY 1 ORDER BY 1`);

    console.log('RELATION_COUNTS', JSON.stringify(counts.rows));
    console.log('FUNCTION_COUNTS', JSON.stringify(funcs.rows));
    console.log('POLICY_COUNTS', JSON.stringify(pol.rows));

    const roles = await client.query(`
      SELECT rolname, rolcanlogin, rolbypassrls
      FROM pg_roles
      WHERE rolname = ANY($1::text[])
      ORDER BY rolname`,
      [BOOTSTRAP_ROLES],
    );
    console.log('BOOTSTRAP_ROLES', JSON.stringify(roles.rows));

    const exts = await client.query(`
      SELECT e.extname, n.nspname AS schema
      FROM pg_extension e
      JOIN pg_namespace n ON n.oid = e.extnamespace
      ORDER BY e.extname`);

    const cron = await client.query(`
      SELECT extname FROM pg_extension WHERE extname = 'pg_cron'`);
    const cronAvail = await client.query(`
      SELECT name FROM pg_available_extensions WHERE name = 'pg_cron'`);

    console.log('EXTENSIONS', JSON.stringify(exts.rows));
    console.log('PG_CRON_INSTALLED', cron.rows.length > 0);
    console.log('PG_CRON_AVAILABLE', cronAvail.rows.length > 0);

    const authJwt = await client.query(`
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'auth' AND p.proname = 'jwt'
      ) AS auth_jwt_exists`);
    console.log('AUTH_SHIM_JWT', authJwt.rows[0].auth_jwt_exists);

    const rowCounts = [];
    for (const t of APP_TABLES) {
      const reg = await client.query(
        `SELECT to_regclass($1) AS reg`,
        [`public.${t}`],
      );
      if (!reg.rows[0].reg) {
        rowCounts.push({ table: t, status: 'missing' });
        continue;
      }
      const r = await client.query(`SELECT count(*)::bigint AS n FROM public.${t}`);
      rowCounts.push({ table: t, n: String(r.rows[0].n) });
    }
    console.log('APP_TABLE_ROWS', JSON.stringify(rowCounts));

    const publicTables = await client.query(`
      SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
      ORDER BY 1`);
    const authN = await client.query(`
      SELECT count(*)::int AS n FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'auth'`);
    const privN = await client.query(`
      SELECT count(*)::int AS n FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'private'`);
    console.log('PUBLIC_TABLES', JSON.stringify(publicTables.rows));
    console.log('AUTH_PRIVATE_OBJECT_COUNTS', JSON.stringify({ auth: authN.rows[0].n, private: privN.rows[0].n }));

    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error('FAIL', e.message || e);
  process.exit(1);
});