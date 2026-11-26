#!/usr/bin/env node
'use strict';

/**
 * Read-only: staging ledger + super_admin function body probe + admin_users sanity.
 * Does not apply migrations.
 */

const { Pool } = require('pg');
const path = require('path');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { stagingPgSsl } = require('../lib/staging_pg_ssl');

const VERSIONS = [
  '20261112000003',
  '20261115000001',
  '20261115000002',
];

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const appEnv = String(getEnv('APP_ENV') || 'staging').toLowerCase();
  if (appEnv === 'production') {
    console.error('Refusing APP_ENV=production');
    process.exit(2);
  }
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('STAGING_SUPABASE_DB_URL missing');
    process.exit(2);
  }
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'staging_migration_exposure_audit' });

  console.log(`Staging migration exposure audit\nDB: ${maskConnectionString(dbUrl)}\n`);

  const pool = new Pool({ connectionString: dbUrl, ssl: stagingPgSsl(), max: 2 });
  const client = await pool.connect();
  try {
    const ledger = await client.query(
      `SELECT version, name, applied_at
       FROM public._schema_migrations
       WHERE version = ANY($1::text[])
       ORDER BY version`,
      [VERSIONS],
    );
    const supa = await client.query(
      `SELECT version, name, inserted_at
       FROM supabase_migrations.schema_migrations
       WHERE version = ANY($1::text[])
       ORDER BY version`,
      [VERSIONS],
    ).catch(() => ({ rows: [] }));

    console.log('--- public._schema_migrations (target versions) ---');
    console.table(ledger.rows);
    console.log('--- supabase_migrations.schema_migrations (if present) ---');
    console.table(supa.rows);

    const fn = await client.query(`
      SELECT pg_get_functiondef(p.oid) AS def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'private' AND p.proname = 'is_super_admin'
      LIMIT 1
    `);
    const def = fn.rows[0]?.def || '';
    const hasEmailBypass =
      /admin@doctornect\.com/i.test(def) &&
      !/private\.admin_users/i.test(def);
    const hasHardenedJoin = /private\.admin_users/i.test(def) && /email_verified/i.test(def);
    console.log('\n--- is_super_admin() analysis ---');
    console.log(`email-only bypass pattern (bad): ${hasEmailBypass ? 'YES — APPLY 20261115000001' : 'no'}`);
    console.log(`admin_users + email_verified join (good): ${hasHardenedJoin ? 'yes' : 'no'}`);

    const adminRows = await client.query(`
      SELECT count(*)::int AS n FROM private.admin_users
    `);
    const adminSample = await client.query(`
      SELECT user_id, granted_at
      FROM private.admin_users
      ORDER BY granted_at DESC NULLS LAST
      LIMIT 10
    `);
    const systemAdmins = await client.query(`
      SELECT id, email, role, verified
      FROM public.users
      WHERE lower(email) = 'admin@doctornect.com'
         OR role IN ('admin', 'super_admin', 'superAdmin')
      ORDER BY updated_at DESC NULLS LAST
      LIMIT 10
    `);

    console.log('\n--- private.admin_users (count + sample, no secrets) ---');
    console.log(`row_count=${adminRows.rows[0].n}`);
    console.table(adminSample.rows);

    console.log('\n--- public.users admin-like rows (sample) ---');
    console.table(systemAdmins.rows.map((r) => ({
      id: r.id?.slice?.(0, 12) + '…',
      email: r.email ? `${String(r.email).slice(0, 3)}***` : null,
      role: r.role,
      verified: r.verified,
    })));

    const pgcrypto = await client.query(`
      SELECT e.extname, n.nspname AS schema
      FROM pg_extension e
      JOIN pg_namespace n ON n.oid = e.extnamespace
      WHERE e.extname = 'pgcrypto'
    `);
    console.log('\n--- pgcrypto installed ---');
    console.table(pgcrypto.rows);

    const applied03 = ledger.rows.some((r) => r.version === '20261112000003');
    const applied01 = ledger.rows.some((r) => r.version === '20261115000001');
    console.log('\n--- VERDICT ---');
    console.log(`20261112000003 in ledger: ${applied03 ? 'YES' : 'NO/unknown'}`);
    console.log(`20261115000001 in ledger: ${applied01 ? 'YES' : 'NO — operator must apply'}`);
    if (hasEmailBypass) {
      console.log('ACTION REQUIRED: run 20261115000001 on staging (see MANUAL_STEPS.md)');
      process.exit(1);
    }
    process.exit(applied01 && hasHardenedJoin ? 0 : 1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});