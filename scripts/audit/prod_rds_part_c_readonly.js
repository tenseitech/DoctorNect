#!/usr/bin/env node
'use strict';

/**
 * Part C read-only catalog audit (production RDS tunnel). No row data from user/health tables.
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

const OUT = path.join(__dirname, '../../docs/audit/PROD_RDS_PART_C_FINDINGS_2026-11-23.md');

const HEALTH_TABLES = [
  'patients',
  'prescriptions',
  'health_records',
  'lab_orders',
  'lab_bookings',
  'appointments',
  'ambulance_requests',
  'family_members',
  'patient_doctor_links',
];

const SYSTEM_OR_LOW_RISK = new Set([
  '_schema_migrations',
  'schema_migrations',
  'pg_stat_statements',
]);

function classifyTable(name) {
  const n = String(name || '').toLowerCase();
  if (HEALTH_TABLES.includes(n)) return 'health/user PHI';
  if (SYSTEM_OR_LOW_RISK.has(n)) return 'system/migration';
  if (n.includes('config') || n.includes('directory') || n.includes('catalog')) return 'config/directory';
  if (n.includes('audit') || n.includes('rate') || n.includes('otp')) return 'security/ops';
  return 'application/other';
}

const SQL = {
  noRls: `
    SELECT n.nspname AS schema, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname IN ('public', 'private')
      AND NOT c.relrowsecurity
    ORDER BY 1, 2`,
  rlsNotForced: `
    SELECT n.nspname AS schema, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname IN ('public', 'private')
      AND c.relrowsecurity AND NOT c.relforcerowsecurity
    ORDER BY 1, 2`,
  riskyPolicies: `
    SELECT schemaname, tablename, policyname, cmd, roles::text AS roles,
           qual AS using_expr, with_check AS with_check_expr
    FROM pg_policies
    WHERE schemaname IN ('public', 'private')
      AND (
        roles::text ILIKE '%public%'
        OR cmd IN ('*', 'ALL')
        OR qual ILIKE '%true%'
        OR with_check ILIKE '%true%'
      )
    ORDER BY 1, 2, 3`,
  anonPublicGrants: `
    SELECT table_schema, table_name, grantee, privilege_type
    FROM information_schema.role_table_grants
    WHERE table_schema IN ('public', 'private')
      AND grantee IN ('anon', 'PUBLIC')
    ORDER BY 1, 2, 3, 4`,
  definerNoPath: `
    SELECT n.nspname AS schema, p.proname AS func
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef AND n.nspname IN ('public', 'private')
      AND NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
        WHERE cfg LIKE 'search_path=%'
      )
    ORDER BY 1, 2`,
  definerPublicExec: `
    SELECT n.nspname AS schema, p.proname AS func,
           array_agg(DISTINCT grantee.rolname) AS execute_roles
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    LEFT JOIN LATERAL (
      SELECT grantee.rolname
      FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      JOIN pg_roles grantee ON grantee.oid = acl.grantee
      WHERE acl.privilege_type = 'EXECUTE'
    ) grantee ON true
    WHERE p.prosecdef AND n.nspname IN ('public', 'private')
    GROUP BY 1, 2
    HAVING bool_or(grantee.rolname IN ('anon', 'PUBLIC'))
    ORDER BY 1, 2`,
  patientPolicies: `
    SELECT schemaname, tablename, policyname, cmd, roles::text,
           qual AS using_expr, with_check AS with_check_expr
    FROM pg_policies
    WHERE tablename IN (
      'patients','prescriptions','health_records','lab_orders','appointments',
      'ambulance_requests','family_members','patient_doctor_links','users'
    )
    ORDER BY tablename, policyname`,
};

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  if (!process.argv.includes('--target=production')) {
    console.error('Usage: --target=production --confirm=<host-fingerprint>');
    process.exit(1);
  }
  const host = process.env.PROD_RDS_HOST;
  const confirm = process.argv.find((a) => a.startsWith('--confirm='));
  if (!confirm) {
    console.error(`--confirm=${getHostFingerprint(host)} required`);
    process.exit(1);
  }
  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'prod_rds_part_c_readonly',
    allowDestructive: false,
    targetHost: host,
  });

  const client = new Client(buildRdsPoolConfig({ database: process.env.PROD_RDS_DB || 'doctornect' }));
  await client.connect();
  const data = {};
  try {
    for (const [k, sql] of Object.entries(SQL)) {
      data[k] = (await client.query(sql)).rows;
    }
  } finally {
    await client.end();
  }

  const lines = [
    '# Part C — Production RDS security findings (read-only)',
    '',
    `Generated: ${new Date().toISOString()}`,
    '',
    '## Priority: tables without RLS enabled',
    '',
  ];

  if (!data.noRls.length) {
    lines.push('_None in public/private._');
  } else {
    lines.push('| Schema | Table | Data class | Risk |');
    lines.push('|--------|-------|------------|------|');
    for (const row of data.noRls) {
      const cls = classifyTable(row.table_name);
      const risk =
        cls === 'health/user PHI'
          ? '**Critical** — PHI without RLS'
          : cls === 'system/migration'
            ? 'Low — ledger/meta'
            : '**Medium** — review grants';
      lines.push(`| ${row.schema} | ${row.table_name} | ${cls} | ${risk} |`);
    }
  }

  lines.push('', '## RLS enabled but not FORCE', '');
  for (const row of data.rlsNotForced) {
    const cls = classifyTable(row.table_name);
    lines.push(`- \`${row.schema}.${row.table_name}\` — ${cls}`);
  }

  lines.push('', '## Policies (PUBLIC role, ALL cmd, or USING/WITH CHECK containing true)', '');
  for (const row of data.riskyPolicies) {
    lines.push(
      `- **${row.schemaname}.${row.tablename}** · \`${row.policyname}\` · cmd=${row.cmd} · roles=${row.roles}`,
    );
    lines.push(`  - USING: \`${String(row.using_expr || '').slice(0, 400)}\``);
    if (row.with_check_expr) lines.push(`  - WITH CHECK: \`${String(row.with_check_expr).slice(0, 400)}\``);
  }

  lines.push('', '## Grants to anon or PUBLIC', '');
  const healthGrants = data.anonPublicGrants.filter((g) =>
    HEALTH_TABLES.includes(String(g.table_name).toLowerCase()),
  );
  if (healthGrants.length) {
    lines.push('### Health-related tables', '');
    for (const g of healthGrants) {
      lines.push(`- \`${g.table_schema}.${g.table_name}\` → **${g.grantee}** ${g.privilege_type}`);
    }
  } else {
    lines.push('_No anon/PUBLIC table grants on health table names in scope._');
  }
  lines.push('', '### All anon/PUBLIC grants', '');
  for (const g of data.anonPublicGrants) {
    lines.push(`- \`${g.table_schema}.${g.table_name}\` → ${g.grantee} ${g.privilege_type}`);
  }

  lines.push('', '## SECURITY DEFINER without search_path', '');
  if (!data.definerNoPath.length) lines.push('_None._');
  else for (const r of data.definerNoPath) lines.push(`- \`${r.schema}.${r.func}\``);

  lines.push('', '## SECURITY DEFINER EXECUTE granted to anon/PUBLIC', '');
  if (!data.definerPublicExec.length) lines.push('_None._');
  else for (const r of data.definerPublicExec) lines.push(`- \`${r.schema}.${r.func}\` roles=${r.execute_roles}`);

  lines.push('', '## Patient / isolation policy trace (logic only)', '');
  for (const row of data.patientPolicies) {
    const expr = String(row.using_expr || row.with_check_expr || '');
    const hasUid =
      /firebase_uid|auth\.uid|current_profile|owner|patient_id|jwt_claim/i.test(expr) || expr.includes('private.');
    lines.push(`- **${row.tablename}** · \`${row.policyname}\` · ${row.cmd} · roles=${row.roles}`);
    lines.push(`  - Expression: \`${String(row.using_expr || '(none)').slice(0, 300)}\``);
    lines.push(`  - Owner/UID check inferred: **${hasUid ? 'yes' : 'review'}**`);
  }

  lines.push('', '## Findings summary', '');
  lines.push('| ID | Severity | Issue | Evidence |');
  lines.push('|----|----------|-------|----------|');
  lines.push(
    `| PC-01 | Medium | ${data.rlsNotForced.length} tables RLS not FORCE | See list above |`,
  );
  lines.push(
    `| PC-02 | Info | pg_cron PUBLIC ALL policies | cron.job* USING username=CURRENT_USER |`,
  );
  if (data.noRls.length) {
    for (const row of data.noRls) {
      const sev = classifyTable(row.table_name) === 'health/user PHI' ? 'Critical' : 'Medium';
      lines.push(`| PC-03 | ${sev} | No RLS on ${row.schema}.${row.table_name} | catalog query |`);
    }
  }
  if (healthGrants.length) {
    lines.push(`| PC-04 | High | anon/PUBLIC grants on health tables | ${healthGrants.length} rows |`);
  }

  fs.writeFileSync(OUT, lines.join('\n'), 'utf8');
  console.log(`Wrote ${OUT}`);
  console.log(`noRls=${data.noRls.length} rlsNotForced=${data.rlsNotForced.length} riskyPolicies=${data.riskyPolicies.length}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});