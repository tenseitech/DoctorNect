#!/usr/bin/env node
'use strict';

/**
 * Read-only: SECURITY DEFINER functions owned by non-BYPASSRLS roles
 * that appear to DML tables with FORCE ROW LEVEL SECURITY.
 */

const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');

const AUDIT_SQL = `
WITH force_rls AS (
  SELECT format('%I.%I', n.nspname, c.relname) AS fqname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r'
    AND c.relforcerowsecurity
    AND n.nspname = ANY (ARRAY['public', 'private'])
),
candidates AS (
  SELECT
    format('%I.%I(%s)', n.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)) AS signature,
    n.nspname AS schema_name,
    p.proname AS func_name,
    pg_get_userbyid(p.proowner) AS owner,
    COALESCE((SELECT r.rolbypassrls FROM pg_roles r WHERE r.rolname = pg_get_userbyid(p.proowner)), false) AS owner_bypassrls,
    EXISTS (
      SELECT 1
      FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg LIKE 'search_path=%'
    ) AS search_path_pinned,
    pg_get_functiondef(p.oid) AS body,
    array_agg(DISTINCT pr.rolname) FILTER (WHERE pr.rolname IS NOT NULL) AS execute_roles
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  LEFT JOIN LATERAL (
    SELECT grantee.rolname
    FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    JOIN pg_roles grantee ON grantee.oid = acl.grantee
    WHERE acl.privilege_type = 'EXECUTE'
  ) pr ON true
  WHERE p.prosecdef
    AND n.nspname = ANY (ARRAY['public', 'private'])
  GROUP BY p.oid, n.nspname, p.proname, p.proowner, p.proconfig, p.oid
)
SELECT
  c.signature,
  c.schema_name,
  c.func_name,
  c.owner,
  c.owner_bypassrls,
  c.search_path_pinned,
  c.execute_roles,
  fr.fqname AS force_rls_table,
  c.body
FROM candidates c
CROSS JOIN force_rls fr
WHERE NOT c.owner_bypassrls
  AND c.body ~* ('(INSERT\\s+INTO|UPDATE|DELETE\\s+FROM)\\s+' || replace(fr.fqname, '.', '\\.'))
ORDER BY c.signature, fr.fqname;
`;

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const args = process.argv.slice(2);
  const targetArg = args.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'rehearsal';
  const database = target === 'rehearsal' ? 'doctornect_rehearsal' : process.env.PROD_RDS_DB || 'doctornect';
  const pool = new Pool(
    buildRdsPoolConfig({
      database,
      ...(process.env.PROD_RDS_SSLMODE === 'disable' ? {} : {}),
    }),
  );
  if (!process.env.PROD_RDS_SSLMODE) {
    process.env.PROD_RDS_SSLMODE = 'disable';
  }
  const client = await pool.connect();
  try {
    const ledger = await client.query(
      `SELECT version FROM public._schema_migrations WHERE version = '20261118000005'`,
    );
    console.log(`Ledger 20261118000005 rows: ${ledger.rowCount}`);
    const res = await client.query(AUDIT_SQL);
    const bySig = new Map();
    for (const row of res.rows) {
      const list = bySig.get(row.signature) || { ...row, force_rls_tables: [] };
      list.force_rls_tables.push(row.force_rls_table);
      bySig.set(row.signature, list);
    }
    const items = [...bySig.values()];
    console.log(`\n=== DEFINER + FORCE RLS DML hits (owner without BYPASSRLS): ${items.length} ===\n`);
    for (const it of items) {
      const rawExec = it.execute_roles;
      const execList = Array.isArray(rawExec)
        ? rawExec
        : rawExec == null || rawExec === ''
          ? []
          : String(rawExec)
              .replace(/^\{|\}$/g, '')
              .split(',')
              .map((s) => s.trim().replace(/^"|"$/g, ''))
              .filter(Boolean);
      const exec = execList.filter(Boolean).join(',') || '(none explicit)';
      console.log(
        `${it.schema_name}.${it.func_name} | owner=${it.owner} | search_path_pinned=${it.search_path_pinned} | EXECUTE=${exec} | FORCE RLS tables: ${it.force_rls_tables.join(', ')}`,
      );
    }
    process.exit(items.length ? 2 : 0);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});