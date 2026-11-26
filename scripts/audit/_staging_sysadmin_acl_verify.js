#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');

loadRootEnv();

const PROCS = [
  'private.is_system_admin_user(text)',
  'private.trg_users_protect_system_admin()',
  'private.trg_users_protect_system_admin_delete()',
];

async function main() {
  const c = new Client({
    connectionString: getEnv('STAGING_SUPABASE_DB_URL').replace(/^postgres:/i, 'postgresql:'),
  });
  await c.connect();
  try {
    const out = [];
    for (const ident of PROCS) {
      const r = await c.query(
        `SELECT pg_catalog.array_to_string(p.proacl, E'\\n') AS acl,
                has_function_privilege('authenticated', ($1::text)::regprocedure, 'EXECUTE') AS auth,
                has_function_privilege('service_role', ($1::text)::regprocedure, 'EXECUTE') AS svc,
                has_function_privilege('anon', ($1::text)::regprocedure, 'EXECUTE') AS anon
         FROM pg_proc p
         WHERE p.oid = ($1::text)::regprocedure`,
        [ident],
      );
      const row = r.rows[0] || {};
      const hasPublic =
        row.acl &&
        row.acl.split('\n').some((line) => line === '=X/postgres' || line.startsWith('=X/') || line.startsWith('=X'));
      const publicViaAcl =
        row.acl &&
        row.acl.split('\n').some((line) => line.startsWith('=') && line.includes('X'));
      out.push({
        fn: ident,
        acl: row.acl || '(null)',
        authenticated_exec: row.auth,
        service_role_exec: row.svc,
        anon_exec: row.anon,
        public_grant_in_acl: publicViaAcl,
      });
    }
    console.log(JSON.stringify(out, null, 2));
  } finally {
    await c.end();
  }
}
main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});