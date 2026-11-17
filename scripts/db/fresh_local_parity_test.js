'use strict';

/**
 * Provision throwaway local DB, apply all db/migrations from zero, compare public catalog to staging.
 * Does not touch staging. Uses schema_diff.fetchCatalog + compareCatalogs.
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { fetchCatalog, compareCatalogs } = require('./schema_diff');

const ADMIN_URL =
  getEnv('REPLAY_DB_URL') ||
  `postgresql://postgres:postgres@127.0.0.1:${getEnv('LOCAL_REPLAY_PG_PORT') || '5440'}/postgres`;
const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

function buildDbUrl(dbName) {
  const u = new URL(ADMIN_URL.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${dbName}`;
  return u.toString();
}

async function applyMigrations(client) {
  const migrationsDir = path.resolve(__dirname, '../../db/migrations');
  const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  const hasCron = await client.query(
    `SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'`,
  );
  const lacksPgCron = hasCron.rows.length === 0;

  for (const file of files) {
    let sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    if (lacksPgCron && file === '20260923000003_doctornect_cron.sql') {
      sql = sql.replace(
        /CREATE EXTENSION IF NOT EXISTS pg_cron;/g,
        '-- [fresh local] Skipped pg_cron extension (mock installed in bootstrap)',
      );
    }
    process.stdout.write(`  apply ${file} ... `);
    try {
      await client.query(sql);
      console.log('ok');
    } catch (err) {
      console.log('FAIL');
      throw new Error(`${file}: ${err.message}`);
    }
  }
  return files.length;
}

async function main() {
  const stagingUri = getEnv('STAGING_SUPABASE_DB_URL');
  if (!stagingUri) {
    console.error('STAGING_SUPABASE_DB_URL required for comparison baseline.');
    process.exit(1);
  }

  console.log('============================================================');
  console.log('Fresh local Postgres: apply all migrations from zero');
  console.log('============================================================');
  console.log(`Admin: ${maskConnectionString(ADMIN_URL)}`);
  console.log(`Scratch DB: ${DB_NAME}\n`);

  const admin = new Client({ connectionString: ADMIN_URL });
  await admin.connect();
  await admin.query(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`, [DB_NAME]).catch(() => {});
  await admin.query(`DROP DATABASE IF EXISTS ${DB_NAME}`);
  await admin.query(`CREATE DATABASE ${DB_NAME}`);
  await admin.end();

  const freshUrl = buildDbUrl(DB_NAME);
  const client = new Client({ connectionString: freshUrl });
  await client.connect();

  const bootstrapDir = path.resolve(__dirname, '../../db/rds_bootstrap');
  for (const boot of ['01_roles_and_extensions.sql', '02_auth_shim.sql', '03_legacy_compat.sql']) {
    const p = path.join(bootstrapDir, boot);
    if (fs.existsSync(p)) {
      console.log(`Bootstrap: ${boot}`);
      await client.query(fs.readFileSync(p, 'utf8'));
    }
  }

  const hasCron = await client.query(`SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'`);
  if (hasCron.rows.length === 0) {
    console.log('Bootstrap: TEST-ONLY cron mock (local scratch)');
    await client.query(`
      CREATE SCHEMA IF NOT EXISTS cron;
      CREATE TABLE IF NOT EXISTS cron.job (
          jobid serial PRIMARY KEY,
          schedule text NOT NULL,
          command text NOT NULL,
          nodename text DEFAULT 'localhost',
          nodeport integer DEFAULT 5432,
          database text DEFAULT current_database(),
          username text DEFAULT current_user,
          active boolean DEFAULT true,
          jobname text UNIQUE
      );
      CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
      RETURNS bigint LANGUAGE plpgsql AS $$
      DECLARE v_id bigint;
      BEGIN
          INSERT INTO cron.job (jobname, schedule, command)
          VALUES (job_name, schedule, command)
          ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
          RETURNING jobid INTO v_id;
          RETURN v_id;
      END;
      $$;
      CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
      RETURNS boolean LANGUAGE plpgsql AS $$
      BEGIN
          DELETE FROM cron.job WHERE jobname = job_name;
          RETURN FOUND;
      END;
      $$;
    `);
  }

  console.log('\nApplying migrations...');
  const n = await applyMigrations(client);
  console.log(`\nApplied ${n} migration files.\n`);
  await client.end();

  console.log('============================================================');
  console.log('Schema parity: Staging (Supabase) vs fresh local');
  console.log('============================================================');

  const sClient = new Client({ connectionString: stagingUri, ssl: { rejectUnauthorized: false } });
  const fClient = new Client({ connectionString: freshUrl });
  await sClient.connect();
  await fClient.connect();

  try {
    const [stagingCat, freshCat] = await Promise.all([fetchCatalog(sClient), fetchCatalog(fClient)]);
    console.log(
      `Staging: ${stagingCat.columns.length} cols, ${stagingCat.policies.length} policies, ${stagingCat.functions.length} funcs, ${stagingCat.grants.length} grants`,
    );
    console.log(
      `Fresh:   ${freshCat.columns.length} cols, ${freshCat.policies.length} policies, ${freshCat.functions.length} funcs, ${freshCat.grants.length} grants`,
    );

    const diffs = compareCatalogs(stagingCat, freshCat, 'fresh_local');
    const reportPath = path.resolve(__dirname, '../../docs/reports/fresh_local_vs_staging_schema_diff.json');
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify({ generatedAt: new Date().toISOString(), dbName: DB_NAME, count: diffs.length, diffs }, null, 2));

    console.log(`\nDifferences: ${diffs.length} (full list in ${reportPath})\n`);
    const byCat = {};
    for (const d of diffs) {
      byCat[d.category] = (byCat[d.category] || 0) + 1;
    }
    console.log('By category:', byCat);

    const maxPrint = 80;
    for (let i = 0; i < Math.min(diffs.length, maxPrint); i++) {
      const d = diffs[i];
      console.log(`- [${d.category}] ${d.key}: ${d.diff}`);
    }
    if (diffs.length > maxPrint) {
      console.log(`... and ${diffs.length - maxPrint} more (see JSON report).`);
    }

    process.exit(diffs.length === 0 ? 0 : 2);
  } finally {
    await sClient.end().catch(() => {});
    await fClient.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error('Fatal:', e.message);
    process.exit(1);
  });
}

module.exports = { main };
