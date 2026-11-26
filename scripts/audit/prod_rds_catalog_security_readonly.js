#!/usr/bin/env node
'use strict';

/**
 * Read-only production RDS catalog security snapshot (no user/health row data).
 * Requires tunnel to PROD_RDS (e.g. 127.0.0.1:5434).
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

const OUT = path.join(__dirname, '../../docs/audit/PROD_RDS_CATALOG_SECURITY_2026-11-23.md');

const QUERIES = {
  publicPolicies: `
    SELECT schemaname, tablename, policyname, cmd, roles::text,
           qual AS using_expr, with_check AS with_check_expr
    FROM pg_policies
    WHERE roles::text ILIKE '%public%'
    ORDER BY 1, 2, 3`,
  rlsTables: `
    SELECT n.nspname AS schema, c.relname AS table,
           c.relrowsecurity AS rls_enabled,
           c.relforcerowsecurity AS rls_forced
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname IN ('public', 'private')
    ORDER BY 1, 2`,
  definerNoSearchPath: `
    SELECT n.nspname AS schema, p.proname AS func,
           pg_get_userbyid(p.proowner) AS owner,
           EXISTS (
             SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
             WHERE cfg LIKE 'search_path=%'
           ) AS search_path_pinned
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef AND n.nspname IN ('public', 'private')
    ORDER BY 1, 2`,
  roleGrants: `
    SELECT grantee.rolname, table_schema, table_name, privilege_type
    FROM information_schema.role_table_grants g
    JOIN pg_roles grantee ON grantee.rolname = g.grantee
    WHERE grantee.rolname IN ('anon', 'authenticated', 'PUBLIC')
      AND table_schema IN ('public', 'private')
    ORDER BY 1, 2, 3, 4`,
  systemConfigAnon: `
    SELECT pol.polname, pol.polcmd, pol.polroles::regrole[]::text[] AS roles,
           pg_get_expr(pol.polqual, pol.polrelid) AS using_expr
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'system_config'
    ORDER BY pol.polname`,
  systemConfigAnonVisibleKeys: `
    SELECT config_key
    FROM public.system_config
    WHERE config_key IN ('patient_module_status', 'promoted_ads', 'demo_accounts')
    ORDER BY config_key`,
};

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const host = process.env.PROD_RDS_HOST;
  const confirm = process.argv.find((a) => a.startsWith('--confirm='));
  if (!confirm) {
    console.error(`Usage: node prod_rds_catalog_security_readonly.js --confirm=${getHostFingerprint(host)}`);
    process.exit(1);
  }
  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'prod_rds_catalog_security_readonly',
    allowDestructive: false,
    targetHost: host,
  });

  const client = new Client(buildRdsPoolConfig({ database: process.env.PROD_RDS_DB || 'doctornect' }));
  await client.connect();
  try {
    const results = {};
    for (const [key, sql] of Object.entries(QUERIES)) {
      const res = await client.query(sql);
      results[key] = res.rows;
    }

    const lines = [
      '# Production RDS catalog security (read-only)',
      '',
      `Generated: ${new Date().toISOString()}`,
      `Host fingerprint: ${getHostFingerprint(host)}`,
      '',
      '## Policies involving PUBLIC role',
      '',
    ];
    if (!results.publicPolicies.length) {
      lines.push('_None found in pg_policies._');
    } else {
      for (const row of results.publicPolicies) {
        lines.push(
          `- **${row.schemaname}.${row.tablename}** \`${row.policyname}\` cmd=${row.cmd} roles=${row.roles}`,
        );
        lines.push(`  - USING: \`${String(row.using_expr || '').slice(0, 500)}\``);
        if (row.with_check_expr) {
          lines.push(`  - WITH CHECK: \`${String(row.with_check_expr).slice(0, 500)}\``);
        }
      }
    }

    lines.push('', '## RLS enabled / forced (public + private)', '');
    const enabled = results.rlsTables.filter((r) => r.rls_enabled);
    lines.push(`- Tables with RLS enabled: **${enabled.length}** / ${results.rlsTables.length}`);
    const notForced = enabled.filter((r) => !r.rls_forced);
    if (notForced.length) {
      lines.push(`- RLS enabled but **not forced**: ${notForced.map((r) => `${r.schema}.${r.table}`).join(', ')}`);
    }

    lines.push('', '## SECURITY DEFINER without pinned search_path', '');
    const badDef = results.definerNoSearchPath.filter((r) => !r.search_path_pinned);
    lines.push(`Count: **${badDef.length}** (of ${results.definerNoSearchPath.length} definer functions)`);
    for (const row of badDef.slice(0, 40)) {
      lines.push(`- ${row.schema}.${row.func} owner=${row.owner}`);
    }
    if (badDef.length > 40) lines.push(`- _…and ${badDef.length - 40} more_`);

    lines.push('', '## Grants to anon / authenticated / PUBLIC (table privileges)', '');
    lines.push(`Row count: **${results.roleGrants.length}**`);
    const byRole = {};
    for (const g of results.roleGrants) {
      byRole[g.rolname] = (byRole[g.rolname] || 0) + 1;
    }
    for (const [role, n] of Object.entries(byRole)) {
      lines.push(`- ${role}: ${n} grant rows`);
    }

    lines.push('', '## system_config policies (SEC-013)', '');
    for (const row of results.systemConfigAnon) {
      lines.push(`- **${row.polname}** cmd=${row.polcmd} roles=${JSON.stringify(row.roles)}`);
      lines.push(`  - USING: \`${row.using_expr}\``);
    }
    lines.push('', '### config_key rows matching public-read allowlist check', '');
    for (const row of results.systemConfigAnonVisibleKeys) {
      lines.push(`- present: \`${row.config_key}\``);
    }
    const hasDemo = results.systemConfigAnonVisibleKeys.some((r) => r.config_key === 'demo_accounts');
    lines.push(
      '',
      `**Anon-visible keys per policy** should be only \`patient_module_status\`, \`promoted_ads\`. ` +
        `demo_accounts present: **${hasDemo}**.`,
    );

    fs.writeFileSync(OUT, lines.join('\n'), 'utf8');
    console.log(`Wrote ${OUT}`);
    console.log(`PUBLIC policies: ${results.publicPolicies.length}`);
    console.log(`Definer without search_path: ${badDef.length}`);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});