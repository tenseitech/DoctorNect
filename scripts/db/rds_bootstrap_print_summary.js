'use strict';

/**
 * Print-only bootstrap SQL summary (no RDS connection).
 * Usage: node scripts/db/rds_bootstrap_print_summary.js
 */

const fs = require('fs');
const path = require('path');

const PHASES = [
  {
    file: '01_roles_and_extensions.sql',
    phase: 'Pre-migrate (run on empty doctornect DB)',
    summary: [
      'Roles (idempotent): anon, authenticated, service_role (NOLOGIN); authenticator (LOGIN NOINHERIT); app_migrator (LOGIN CREATEROLE); rds_superuser stub; rds_master stub (local parity only — not used on real RDS master).',
      'GRANT anon, authenticated, service_role TO authenticator.',
      'CREATE EXTENSION pgcrypto, uuid-ossp; attempt pg_stat_statements.',
      'CREATE PUBLICATION supabase_realtime (if missing).',
    ],
  },
  {
    file: '02_auth_shim.sql',
    phase: 'Pre-migrate',
    summary: [
      'CREATE SCHEMA auth.',
      'Functions: auth.jwt(), auth.uid() (TEXT / JWT sub), auth.role(), auth.email(), auth.jwt_aud(), auth.jwt_exp().',
      'Used by RLS policies and migrations referencing auth.uid().',
    ],
  },
  {
    file: '03_legacy_compat.sql',
    phase: 'Pre-migrate',
    summary: [
      'CREATE ROLE supabase_admin NOLOGIN (migration compat).',
      'CREATE TABLE auth.users stub (legacy FK targets from early migrations).',
      'CREATE SCHEMA private (sensitive columns).',
    ],
  },
  {
    file: '04_rds_runtime_grants.sql',
    phase: 'Post-migrate ONLY (after migrate.js --execute)',
    summary: [
      'GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role; USAGE ON private TO service_role.',
      'Per-table GRANT SELECT/INSERT/UPDATE/DELETE for service_role on ops tables (abuse_rate_limits, admin_audit_logs, …).',
      'Tight anon SELECT grants on doctor_directory, lab_catalog_tests, system_config, review_public.',
      'GRANT anon, authenticated, service_role TO authenticator; default privileges for app_migrator.',
    ],
  },
];

function main() {
  const bootstrapDir = path.resolve(__dirname, '../../db/rds_bootstrap');
  console.log('=== RDS bootstrap SQL summary (print-only, no DB connection) ===\n');
  console.log('Operator order for greenfield production:');
  console.log('  1. CREATE DATABASE doctornect (session on postgres DB as admin)');
  console.log('  2. Set PROD_RDS_DB=doctornect in .env');
  console.log('  3. Apply bootstrap 01–03 on database doctornect');
  console.log('  4. migrate.js --target=production --dry-run-all');
  console.log('  5. migrate.js --target=production --execute');
  console.log('  6. Apply bootstrap 04 on doctornect');
  console.log('  7. rds_readiness_probe (extensions, roles, pg_cron jobs)\n');

  for (const block of PHASES) {
    const p = path.join(bootstrapDir, block.file);
    const bytes = fs.existsSync(p) ? fs.statSync(p).size : 0;
    console.log(`--- ${block.file} (${bytes} bytes) — ${block.phase} ---`);
    for (const line of block.summary) {
      console.log(`  • ${line}`);
    }
    console.log('');
  }

  console.log('Dry-run listing (no SQL executed):');
  console.log('  node scripts/db/rds_bootstrap_apply.js --print-summary');
  console.log('  node scripts/db/rds_bootstrap_apply.js --target=production  # lists files only');
}

main();
