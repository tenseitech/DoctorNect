#!/usr/bin/env node
'use strict';

/**
 * Staging DB row proof for core migration flows (read-only).
 * Does NOT register users or call MSG91 — uses latest rows already in staging.
 *
 * Usage (staging only):
 *   node scripts/smoke/staging_e2e_db_proof.js
 *
 * Requires in root .env:
 *   APP_ENV=staging
 *   STAGING_SUPABASE_DB_URL (session pooler :5432)
 */

const { Pool } = require('pg');
const path = require('path');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { stagingPgSsl } = require('../lib/staging_pg_ssl');

async function query(client, label, sql, params = []) {
  const res = await client.query(sql, params);
  console.log(`\n=== ${label} (rows=${res.rowCount}) ===`);
  for (const row of res.rows.slice(0, 5)) {
    console.log(JSON.stringify(row));
  }
  if (res.rowCount === 0) {
    console.log('(no rows — seed staging test data first)');
  }
  return res;
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const appEnv = String(getEnv('APP_ENV') || 'staging').toLowerCase();
  if (appEnv === 'production') {
    console.error('Refusing to run on APP_ENV=production. Use staging only.');
    process.exit(2);
  }

  const dbUrl =
    getEnv('STAGING_SUPABASE_DB_URL') ||
    getEnv('SUPABASE_DB_URL') ||
    getEnv('DATABASE_URL');
  if (!dbUrl) {
    console.error('Missing STAGING_SUPABASE_DB_URL / SUPABASE_DB_URL / DATABASE_URL');
    process.exit(2);
  }

  assertDatabaseGuard({ targetKind: 'staging', operationName: 'staging_e2e_db_proof' });

  const pool = new Pool({
    connectionString: dbUrl,
    ssl: stagingPgSsl(),
    max: 2,
    connectionTimeoutMillis: 15000,
  });

  const client = await pool.connect();
  try {
    await query(
      client,
      'doctors (latest profile)',
      `SELECT doctor_id, name, mobile, verified, updated_at
       FROM public.doctors ORDER BY updated_at DESC NULLS LAST LIMIT 3`,
    );
    await query(
      client,
      'appointments (latest booking)',
      `SELECT appointment_id, doctor_id, patient_id, patient_status, doctor_status, date_time
       FROM public.appointments ORDER BY date_time DESC NULLS LAST LIMIT 3`,
    );
    await query(
      client,
      'lab_orders (latest)',
      `SELECT order_id, doctor_id, patient_id, lab_id, status, updated_at
       FROM public.lab_orders ORDER BY updated_at DESC NULLS LAST LIMIT 3`,
    );
    await query(
      client,
      'pharmacy deliveries (latest)',
      `SELECT delivery_id, store_id, doctor_id, status, sent_at, updated_at
       FROM public.pharmacy_deliveries ORDER BY sent_at DESC NULLS LAST LIMIT 3`,
    );
    await query(
      client,
      'otp_challenges (recent, hashed only)',
      `SELECT challenge_id, mobile, role, sent_at, expires_at, is_demo
       FROM public.otp_challenges ORDER BY sent_at DESC NULLS LAST LIMIT 3`,
    );
    console.log('\nOK: read-only staging proofs complete (no writes).');
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});