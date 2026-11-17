'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('pg');

const DB_URL =
  process.env.MIGRATION_ROLLBACK_TEST_URL ||
  'postgresql://postgres:test@localhost:5440/migrate_rollback_test';

async function resetDb() {
  const admin = new Client({ connectionString: 'postgresql://postgres:test@localhost:5440/postgres' });
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS migrate_rollback_test');
  await admin.query('CREATE DATABASE migrate_rollback_test');
  await admin.end();
}

test('failed migration rolls back DDL and leaves no ledger row', async (t) => {
  await resetDb();
  const client = new Client({ connectionString: DB_URL });
  await client.connect();
  t.after(async () => {
    await client.end();
  });

  await client.query(`
    CREATE TABLE IF NOT EXISTS public._schema_migrations (
      version text PRIMARY KEY,
      name text,
      checksum text,
      applied_at timestamptz DEFAULT now()
    );
  `);

  const version = '99999999999999';
  await client.query('BEGIN');
  let failed = false;
  try {
    await client.query('CREATE TABLE public.migrate_rollback_probe (id int PRIMARY KEY);');
    await client.query('SELECT 1/0'); // force failure
    await client.query(
      'INSERT INTO public._schema_migrations (version, name, checksum) VALUES ($1,$2,$3)',
      [version, 'probe', 'abc'],
    );
    await client.query('COMMIT');
  } catch (_) {
    failed = true;
    await client.query('ROLLBACK');
  }
  assert.equal(failed, true);

  const tbl = await client.query(
    `SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='migrate_rollback_probe'`,
  );
  assert.equal(tbl.rows.length, 0);

  const led = await client.query('SELECT 1 FROM public._schema_migrations WHERE version=$1', [version]);
  assert.equal(led.rows.length, 0);
});