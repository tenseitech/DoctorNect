#!/usr/bin/env node
'use strict';
/** Read-only: evidence for sync_ledger_checksum approval (staging). */
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { computeChecksum } = require('../lib/migration_checksum');
const { stagingPgSsl } = require('../lib/staging_pg_ssl');

function innerSql(defOrFile) {
  const s = String(defOrFile);
  const m =
    s.match(/\$function\$([\s\S]*?)\$function\$/) ||
    s.match(/AS \$\$([\s\S]*?)\$\$/);
  return (m ? m[1] : s).replace(/\r\n/g, '\n').replace(/\s+/g, ' ').trim();
}

async function main() {
  const client = new Client({
    connectionString: getEnv('STAGING_SUPABASE_DB_URL'),
    ssl: stagingPgSsl(),
  });
  await client.connect();

  const v1 = fs.readFileSync('db/migrations/20261115000001_harden_super_admin_no_jwt_email_bypass.sql', 'utf8');
  const fn1 = await client.query(`
    SELECT pg_get_functiondef(p.oid) AS def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'is_super_admin'
  `);
  const anon1 = await client.query(
    `SELECT has_function_privilege('anon', 'private.is_super_admin()', 'EXECUTE') AS anon_exec`,
  );
  const auth1 = await client.query(
    `SELECT has_function_privilege('authenticated', 'private.is_super_admin()', 'EXECUTE') AS auth_exec`,
  );
  const svc1 = await client.query(
    `SELECT has_function_privilege('service_role', 'private.is_super_admin()', 'EXECUTE') AS svc_exec`,
  );

  console.log(
    JSON.stringify(
      {
        version: '20261115000001',
        objects: ['private.is_super_admin()', 'EXECUTE grants'],
        inner_sql_equal: innerSql(fn1.rows[0]?.def) === innerSql(v1),
        anon_exec: anon1.rows[0]?.anon_exec,
        authenticated_exec: auth1.rows[0]?.auth_exec,
        service_role_exec: svc1.rows[0]?.svc_exec,
        file_sha256: computeChecksum(v1),
      },
      null,
      2,
    ),
  );

  const v2 = fs.readFileSync(
    'db/migrations/20261115000002_pgcrypto_notification_outbox_search_path.sql',
    'utf8',
  );
  const fn2 = await client.query(`
    SELECT pg_get_functiondef(p.oid) AS def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'enqueue_notification_outbox'
  `);
  const ext2 = await client.query(`
    SELECT extname, n.nspname AS schema FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace WHERE extname = 'pgcrypto'
  `);
  const def2 = fn2.rows[0]?.def || '';
  console.log(
    JSON.stringify(
      {
        version: '20261115000002',
        objects: ['pgcrypto extension', 'public.enqueue_notification_outbox()'],
        inner_sql_equal: innerSql(def2) === innerSql(v2),
        search_path_includes_extensions: /extensions/.test(def2),
        pgcrypto_schemas: ext2.rows,
        file_sha256: computeChecksum(v2),
      },
      null,
      2,
    ),
  );

  const v3 = fs.readFileSync(
    'db/migrations/20261115000003_appointments_sync_origin_replay.sql',
    'utf8',
  );
  const cols3 = await client.query(`
    SELECT table_name, column_name, column_default, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'sync_origin'
      AND table_name IN ('appointments', 'patients', 'prescriptions')
    ORDER BY table_name
  `);
  const expect = {
    appointments: "'patient_supabase'",
    patients: "'patient_supabase'",
    prescriptions: "'doctor_firestore'",
  };
  const colMatch = cols3.rows.every((r) => {
    const d = String(r.column_default || '');
    return d.includes(expect[r.table_name]?.replace(/'/g, '') || '___');
  });
  console.log(
    JSON.stringify(
      {
        version: '20261115000003',
        objects: ['appointments.sync_origin', 'patients.sync_origin', 'prescriptions.sync_origin'],
        columns: cols3.rows,
        defaults_match_repo: colMatch,
        file_sha256: computeChecksum(v3),
      },
      null,
      2,
    ),
  );

  await client.end();
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});