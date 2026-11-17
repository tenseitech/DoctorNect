'use strict';

/**
 * Fail if public tables lack RLS or have authenticated/anon grants without policies.
 * Local fresh DB only unless --confirm-live-data + STAGING URL (operator approved).
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';
const MEDICAL_TABLES = [
  'appointments',
  'prescriptions',
  'prescription_medicines',
  'health_records',
  'lab_reports',
  'lab_orders',
  'lab_bookings',
  'pharmacy_deliveries',
  'support_tickets',
  'support_ticket_messages',
  'in_app_notifications',
  'referrals',
  'reviews',
  'patient_doctor_links',
  'family_members',
];

function localUrl() {
  const base = getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

async function audit(client) {
  const tables = await client.query(`
    SELECT c.relname AS table_name,
           c.relrowsecurity AS rls_enabled,
           c.relforcerowsecurity AS rls_forced
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
    ORDER BY c.relname;
  `);

  const pol = await client.query(`
    SELECT tablename, count(*)::int AS policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    GROUP BY tablename;
  `);
  const polMap = new Map(pol.rows.map((r) => [r.tablename, r.policy_count]));

  const grants = await client.query(`
    SELECT table_name, grantee
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND grantee IN ('anon', 'authenticated')
      AND privilege_type = 'SELECT'
    GROUP BY table_name, grantee;
  `);
  const grantMap = new Map();
  for (const g of grants.rows) {
    const k = g.table_name;
    if (!grantMap.has(k)) grantMap.set(k, new Set());
    grantMap.get(k).add(g.grantee);
  }

  const issues = [];
  for (const t of tables.rows) {
    const name = t.table_name;
    if (name.startsWith('pg_')) continue;
    const pc = polMap.get(name) || 0;
    const g = grantMap.get(name);

    if (!t.rls_enabled) {
      issues.push({ severity: 'ERROR', table: name, issue: 'RLS disabled' });
      continue;
    }
    if (g && g.size > 0 && pc === 0) {
      issues.push({
        severity: 'ERROR',
        table: name,
        issue: `grants to ${[...g].join(',')} but zero policies`,
      });
    }
    if (MEDICAL_TABLES.includes(name) && pc === 0) {
      issues.push({ severity: 'WARN', table: name, issue: 'medical table has no policies listed' });
    }
  }

  return { tableCount: tables.rows.length, issues };
}

async function main() {
  const url = process.argv.includes('--target=staging') && process.argv.includes('--confirm-live-data')
    ? getEnv('STAGING_SUPABASE_DB_URL')
    : localUrl();

  if (!url) {
    console.error('No database URL');
    process.exit(1);
  }

  const client = new Client({
    connectionString: url,
    ssl: url.includes('supabase') ? { rejectUnauthorized: false } : undefined,
  });
  await client.connect();
  const report = await audit(client);
  await client.end();

  const out = path.resolve(__dirname, '../../docs/reports/rls_coverage_audit.json');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify({ at: new Date().toISOString(), db: maskConnectionString(url), ...report }, null, 2));

  console.log(`RLS coverage: ${report.tableCount} public tables, ${report.issues.length} issue(s)`);
  const errors = report.issues.filter((i) => i.severity === 'ERROR');
  for (const i of report.issues) {
    console.log(`- [${i.severity}] ${i.table}: ${i.issue}`);
  }
  console.log(`Wrote ${out}`);
  process.exit(errors.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
