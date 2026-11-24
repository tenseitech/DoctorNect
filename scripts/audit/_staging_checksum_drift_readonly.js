#!/usr/bin/env node
'use strict';
/** One-off read-only: list ledger checksum drift + live is_super_admin (staging). */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { computeChecksum, computeLegacyRawChecksum } = require('../lib/migration_checksum');

function normalizeFnBody(def) {
  return String(def || '')
    .replace(/\r\n/g, '\n')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function fnBodyFromFile(sql) {
  const start = sql.indexOf('AS $$');
  if (start < 0) return normalizeFnBody(sql);
  const end = sql.indexOf('$$', start + 5);
  return normalizeFnBody(sql.slice(start, end + 2));
}

async function main() {
  const url = getEnv('STAGING_SUPABASE_DB_URL');
  if (!url) throw new Error('STAGING_SUPABASE_DB_URL missing');
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();

  const ledger = await client.query(
    'SELECT version, name, checksum FROM public._schema_migrations ORDER BY version',
  );

  const drift = [];
  for (const row of ledger.rows) {
    const rel = `db/migrations/${row.name}`;
    const abs = path.join(process.cwd(), rel);
    const isSha = /^[a-f0-9]{64}$/i.test(row.checksum);
    let current = null;
    let git = 'missing file';
    if (fs.existsSync(abs)) {
      const content = fs.readFileSync(abs, 'utf8');
      current = computeChecksum(content);
      try {
        git = execSync(`git log -1 --format="%h %ci" -- "${rel}"`, { encoding: 'utf8' }).trim();
      } catch {
        git = 'n/a';
      }
      const match =
        row.checksum === current ||
        row.checksum === computeLegacyRawChecksum(content) ||
        row.checksum === 'legacy_supabase';
      if (!match || !isSha) {
        drift.push({
          version: row.version,
          file: row.name,
          recorded: row.checksum,
          current,
          git,
        });
      }
    } else if (!isSha) {
      drift.push({
        version: row.version,
        file: row.name,
        recorded: row.checksum,
        current,
        git,
      });
    }
  }

  console.log('CHECKSUM_DRIFT_ROWS', JSON.stringify(drift, null, 2));

  const fn = await client.query(`
    SELECT pg_get_functiondef(p.oid) AS def,
           p.prosecdef AS security_definer,
           pg_get_userbyid(p.proowner) AS owner,
           array_to_string(p.proacl, ',') AS acl
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'is_super_admin'
  `);

  const grants = await client.query(`
    SELECT grantee, privilege_type
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'private' AND routine_name = 'is_super_admin'
    ORDER BY grantee, privilege_type
  `);

  console.log('IS_SUPER_ADMIN_LIVE', JSON.stringify({ fn: fn.rows[0] || null, grants: grants.rows }, null, 2));

  const repoSql = fs.readFileSync(
    path.join(process.cwd(), 'db/migrations/20261115000001_harden_super_admin_no_jwt_email_bypass.sql'),
    'utf8',
  );
  const liveNorm = fnBodyFromFile(fn.rows[0]?.def || '');
  const expectedNorm = fnBodyFromFile(repoSql);
  const anonRevoked = !(await client.query(
    `SELECT has_function_privilege('anon', 'private.is_super_admin()', 'EXECUTE') AS ok`,
  )).rows[0].ok;
  console.log(
    'IS_SUPER_ADMIN_BODY_MATCH',
    JSON.stringify({
      live_present: Boolean(fn.rows[0]),
      body_normalized_equal: liveNorm === expectedNorm,
      anon_execute_revoked: anonRevoked,
    }),
  );

  const outbox = await client.query(`
    SELECT pg_get_functiondef(p.oid) AS def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'enqueue_notification_outbox'
  `);
  const repo02 = fs.readFileSync(
    path.join(process.cwd(), 'db/migrations/20261115000002_pgcrypto_notification_outbox_search_path.sql'),
    'utf8',
  );
  console.log(
    'ENQUEUE_OUTBOX_MATCH',
    JSON.stringify({
      present: Boolean(outbox.rows[0]),
      body_normalized_equal: fnBodyFromFile(outbox.rows[0]?.def || '') === fnBodyFromFile(repo02),
      search_path_line: (outbox.rows[0]?.def || '').split(/\r?\n/).find((l) => l.includes('search_path')) || null,
    }),
  );

  const cols = await client.query(`
    SELECT table_name, column_name, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'sync_origin'
      AND table_name IN ('appointments', 'patients', 'prescriptions')
    ORDER BY table_name
  `);
  console.log('SYNC_ORIGIN_COLUMNS', JSON.stringify(cols.rows, null, 2));

  const ext = await client.query(`
    SELECT extname, n.nspname AS schema
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE extname = 'pgcrypto'
  `);
  console.log('PGCRYPTO', JSON.stringify(ext.rows));

  await client.end();
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});