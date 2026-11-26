#!/usr/bin/env node
'use strict';

/**
 * Read-only: SECURITY DEFINER functions owned by non-BYPASSRLS roles
 * that appear to DML (or SELECT) tables with FORCE ROW LEVEL SECURITY, or
 * with --scope=part-c-9 predicted FORCE targets before migration.
 */

const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');

/** Prod catalog 2026-11-23 — RLS on, FORCE off */
const PART_C_FORCE_PENDING = [
  'private.admin_users',
  'private.provisioning_errors',
  'public.doctor_directory_updates',
  'public.doctor_invites',
  'public.doctor_private',
  'public.pharmacy_doctor_invites',
  'public.storage_audit_logs',
  'public.user_devices',
  'public.users',
];

function buildDefinerSql({ watchTables, includeSelect }) {
  const tableSource = watchTables
    ? `watch AS (
  SELECT unnest($1::text[]) AS fqname
)`
    : `force_rls AS (
  SELECT format('%I.%I', n.nspname, c.relname) AS fqname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r'
    AND c.relforcerowsecurity
    AND n.nspname = ANY (ARRAY['public', 'private'])
)`;

  const joinTable = watchTables ? 'watch' : 'force_rls';
  const dmlAlternation = includeSelect
    ? 'INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|FROM|JOIN'
    : 'INSERT\\s+INTO|UPDATE|DELETE\\s+FROM';

  return `
WITH ${tableSource},
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
    (
      SELECT array_agg(DISTINCT grantee.rolname)
      FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      JOIN pg_roles grantee ON grantee.oid = acl.grantee
      WHERE acl.privilege_type = 'EXECUTE'
    ) AS execute_roles
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prosecdef
    AND n.nspname = ANY (ARRAY['public', 'private'])
)
SELECT
  c.signature,
  c.schema_name,
  c.func_name,
  c.owner,
  c.owner_bypassrls,
  c.search_path_pinned,
  c.execute_roles,
  w.fqname AS target_table
FROM candidates c
CROSS JOIN ${joinTable} w
WHERE NOT c.owner_bypassrls
  AND c.body ~* ('(${dmlAlternation})\\s+' || replace(w.fqname, '.', '\\.'))
ORDER BY c.signature, w.fqname;
`;
}

const TABLE_META_SQL = `
SELECT
  format('%I.%I', n.nspname, c.relname) AS fqname,
  pg_get_userbyid(c.relowner) AS table_owner,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_rls,
  ro.rolsuper AS owner_is_super,
  ro.rolbypassrls AS owner_bypassrls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles ro ON ro.rolname = pg_get_userbyid(c.relowner)
WHERE format('%I.%I', n.nspname, c.relname) = ANY ($1::text[])
ORDER BY 1;
`;

const TRIGGER_SQL = `
SELECT
  format('%I.%I', tn.nspname, tc.relname) AS table_name,
  t.tgname AS trigger_name,
  CASE t.tgenabled WHEN 'O' THEN 'origin' WHEN 'D' THEN 'disabled' WHEN 'R' THEN 'replica' WHEN 'A' THEN 'always' END AS enabled,
  p.prosecdef AS fn_security_definer,
  pg_get_userbyid(p.proowner) AS fn_owner,
  COALESCE((SELECT r.rolbypassrls FROM pg_roles r WHERE r.rolname = pg_get_userbyid(p.proowner)), false) AS fn_owner_bypassrls,
  format('%I.%I(%s)', fn.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)) AS fn_signature
FROM pg_trigger t
JOIN pg_class tc ON tc.oid = t.tgrelid
JOIN pg_namespace tn ON tn.oid = tc.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace fn ON fn.oid = p.pronamespace
WHERE NOT t.tgisinternal
  AND format('%I.%I', tn.nspname, tc.relname) = ANY ($1::text[])
ORDER BY 1, 2;
`;

function formatExecuteRoles(rawExec) {
  const execList = Array.isArray(rawExec)
    ? rawExec
    : rawExec == null || rawExec === ''
      ? []
      : String(rawExec)
          .replace(/^\{|\}$/g, '')
          .split(',')
          .map((s) => s.trim().replace(/^"|"$/g, ''))
          .filter(Boolean);
  return execList.filter(Boolean).join(',') || '(none explicit)';
}

function resolvePoolConfig(target) {
  if (target === 'staging') {
    const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    if (!dbUrl) throw new Error('STAGING_SUPABASE_DB_URL is not set');
    return { poolConfig: { connectionString: dbUrl }, label: 'staging' };
  }
  if (target === 'replay' || target === 'rds-replay') {
    const rawReplayUrl = getEnv('REPLAY_DB_URL');
    if (!rawReplayUrl) throw new Error('REPLAY_DB_URL is not configured');
    const parsed = new URL(rawReplayUrl);
    const rdsLikeReplay = getEnv('REPLAY_RDS_LIKE') === '1' || target === 'rds-replay';
    if (rdsLikeReplay) {
      parsed.pathname = `/${getEnv('REPLAY_RDS_DB') || 'doctornect'}`;
      const replayUser = getEnv('REPLAY_USER') || 'doctornect_admin';
      if (replayUser) parsed.username = replayUser;
    }
    return { poolConfig: { connectionString: parsed.toString() }, label: 'rds-replay' };
  }
  if (target === 'rehearsal' || target === 'production') {
    const database = target === 'rehearsal' ? 'doctornect_rehearsal' : getEnv('PROD_RDS_DB') || 'doctornect';
    return {
      poolConfig: buildRdsPoolConfig({ database }),
      label: target,
    };
  }
  throw new Error(`Unknown --target=${target} (use staging, replay, rds-replay, rehearsal, production)`);
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const args = process.argv.slice(2);
  const targetArg = args.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'rehearsal';
  const scopeArg = args.find((a) => a.startsWith('--scope='));
  const scope = scopeArg ? scopeArg.split('=')[1] : 'force-rls';
  const includeSelect = args.includes('--include-select');

  const watchTables =
    scope === 'part-c-9' || scope === 'pending-force'
      ? PART_C_FORCE_PENDING
      : null;

  if (target === 'production' && !args.includes('--confirm-live-data')) {
    console.error('[GUARD] Refusing --target=production without --confirm-live-data (use staging/replay for Part C).');
    process.exit(1);
  }

  const { poolConfig, label } = resolvePoolConfig(target);
  const pool = new Pool(poolConfig);
  const client = await pool.connect();
  try {
    console.log(`Target: ${label} | scope: ${scope}${watchTables ? ` (${watchTables.length} tables)` : ''}`);
    if (watchTables) {
      const meta = await client.query(TABLE_META_SQL, [watchTables]);
      console.log('\n=== Table owners (direct session = owner bypasses RLS unless FORCE) ===\n');
      for (const row of meta.rows) {
        console.log(
          `${row.fqname} | owner=${row.table_owner} | rls=${row.rls_enabled} | force=${row.force_rls} | owner_bypassrls=${row.owner_bypassrls}`,
        );
      }
      const trg = await client.query(TRIGGER_SQL, [watchTables]);
      if (trg.rows.length) {
        console.log('\n=== Triggers on Part C tables ===\n');
        for (const row of trg.rows) {
          console.log(
            `${row.table_name}.${row.trigger_name} → ${row.fn_signature} | definer=${row.fn_security_definer} | fn_owner=${row.fn_owner} | fn_owner_bypassrls=${row.fn_owner_bypassrls}`,
          );
        }
      }
    }

    const sql = buildDefinerSql({ watchTables, includeSelect: includeSelect || Boolean(watchTables) });
    const res = watchTables
      ? await client.query(sql, [watchTables])
      : await client.query(sql);

    const bySig = new Map();
    for (const row of res.rows) {
      const list = bySig.get(row.signature) || { ...row, target_tables: [] };
      list.target_tables.push(row.target_table);
      bySig.set(row.signature, list);
    }
    const items = [...bySig.values()];
    const modeLabel = watchTables
      ? 'DEFINER non-BYPASSRLS owner touching Part C tables (pre-FORCE prediction)'
      : 'DEFINER + FORCE RLS DML hits (owner without BYPASSRLS)';
    console.log(`\n=== ${modeLabel}: ${items.length} ===\n`);
    for (const it of items) {
      console.log(
        `${it.schema_name}.${it.func_name} | owner=${it.owner} | search_path_pinned=${it.search_path_pinned} | EXECUTE=${formatExecuteRoles(it.execute_roles)} | tables: ${it.target_tables.join(', ')}`,
      );
    }
    process.exit(items.length ? 2 : 0);
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {
  PART_C_FORCE_PENDING,
  buildDefinerSql,
};