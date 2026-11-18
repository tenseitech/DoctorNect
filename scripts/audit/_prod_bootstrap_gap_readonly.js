#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

loadRootEnv();

const BOOTSTRAP_ROLES = ['anon', 'authenticated', 'service_role', 'authenticator', 'doctornect_admin'];

async function main() {
  const cfg = buildRdsPoolConfig();
  const client = new Client(cfg);
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');

    const roles = await client.query(
      `SELECT rolname FROM pg_roles WHERE rolname = ANY($1::text[])`,
      [BOOTSTRAP_ROLES],
    );
    const haveRoles = new Set(roles.rows.map((r) => r.rolname));
    const gap01 = [];
    if (!haveRoles.has('anon')) gap01.push('role:anon');
    if (!haveRoles.has('authenticated')) gap01.push('role:authenticated');
    if (!haveRoles.has('service_role')) gap01.push('role:service_role');
    if (!haveRoles.has('authenticator')) gap01.push('role:authenticator');
    if (!haveRoles.has('doctornect_admin')) gap01.push('role:doctornect_admin');
    const pgcrypto = await client.query(`SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto'`);
    if (!pgcrypto.rows.length) gap01.push('extension:pgcrypto');

    const gap02 = [];
    const jwt = await client.query(`
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'auth' AND p.proname = 'jwt'
      ) AS ok`);
    if (!jwt.rows[0].ok) gap02.push('auth.jwt() shim');

    const gap03 = [];
    const supaAdmin = await client.query(`SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') AS ok`);
    if (!supaAdmin.rows[0].ok) gap03.push('supabase_admin role stub');
    const authUsers = await client.query(`SELECT to_regclass('auth.users') IS NOT NULL AS ok`);
    if (!authUsers.rows[0].ok) gap03.push('auth.users stub table');
    const privSchema = await client.query(`
      SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'private') AS ok`);
    if (!privSchema.rows[0].ok) gap03.push('private schema');
    const privGrant = await client.query(`
      SELECT has_schema_privilege('authenticated', 'private', 'USAGE') AS ok`);
    if (!privGrant.rows[0].ok) gap03.push('GRANT USAGE ON SCHEMA private TO authenticated');

    const ledger = await client.query(`SELECT count(*)::int AS n, max(version) AS head FROM public._schema_migrations`);
    const pubTables = await client.query(`
      SELECT count(*)::int AS n FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'`);

    let verdict = 'GREENFIELD';
    if (Number(ledger.rows[0].n) > 0 || Number(pubTables.rows[0].n) > 30) verdict = 'POPULATED';
    else if (gap01.length || gap02.length || gap03.length || Number(pubTables.rows[0].n) > 0) verdict = 'PARTIAL';

    console.log(
      JSON.stringify(
        {
          target: maskRdsTarget(cfg),
          verdict,
          bootstrap_01_missing: gap01.length ? gap01 : null,
          bootstrap_02_missing: gap02.length ? gap02 : null,
          bootstrap_03_missing: gap03.length ? gap03 : null,
          ledger_rows: ledger.rows[0].n,
          ledger_head: ledger.rows[0].head,
          public_table_count: pubTables.rows[0].n,
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