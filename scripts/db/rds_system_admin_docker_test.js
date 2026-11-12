#!/usr/bin/env node
'use strict';

/**
 * Validates RDS system-admin SQL on plain PostgreSQL (Docker). Does NOT touch production RDS.
 *
 *   node scripts/db/rds_system_admin_docker_test.js
 *
 * Requires Docker available locally.
 */

const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SQL_FILE = path.join(ROOT, 'db', 'migrations', 'rds', '20261113000001_rds_system_admin_and_audit.sql');
const CONTAINER = `doctornect-rds-sql-test-${Date.now()}`;
const PG_PORT = 55433;

const BOOTSTRAP_SQL = `
CREATE TABLE IF NOT EXISTS public.users (
  id TEXT PRIMARY KEY,
  email TEXT,
  role TEXT,
  status TEXT,
  deactivated BOOLEAN DEFAULT FALSE,
  is_system_admin BOOLEAN NOT NULL DEFAULT FALSE,
  display_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  log_id TEXT PRIMARY KEY,
  admin_uid TEXT,
  admin_email TEXT,
  action TEXT,
  target_type TEXT,
  target_id TEXT,
  details TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.users (id, email, role, status, is_system_admin)
VALUES ('admin-uid', 'admin@doctornect.com', 'super_admin', 'approved', TRUE)
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  role = EXCLUDED.role,
  is_system_admin = EXCLUDED.is_system_admin;
`;

function sh(cmd) {
  return execSync(cmd, { stdio: 'pipe', encoding: 'utf8' });
}

function psql(sql) {
  const r = spawnSync(
    'docker',
    ['exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', sql],
    { encoding: 'utf8' },
  );
  if (r.status !== 0) {
    throw new Error(r.stderr || r.stdout || 'psql failed');
  }
  return r.stdout;
}

function expectFail(sql, snippet) {
  const r = spawnSync(
    'docker',
    ['exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', sql],
    { encoding: 'utf8' },
  );
  if (r.status === 0) {
    throw new Error(`Expected failure for: ${snippet}`);
  }
  return r.stderr || r.stdout;
}

async function main() {
  if (!fs.existsSync(SQL_FILE)) throw new Error(`Missing ${SQL_FILE}`);
  console.log('Starting postgres:16-alpine container...');
  sh(
    `docker run -d --rm --name ${CONTAINER} -e POSTGRES_PASSWORD=postgres -p ${PG_PORT}:5432 postgres:16-alpine`,
  );
  try {
    for (let i = 0; i < 30; i++) {
      try {
        sh(`docker exec ${CONTAINER} pg_isready -U postgres`);
        break;
      } catch (_) {
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
    psql(BOOTSTRAP_SQL);
    const migrationSql = fs.readFileSync(SQL_FILE, 'utf8');
    function applyMigration() {
      const r = spawnSync(
        'docker',
        ['exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
        { input: migrationSql, encoding: 'utf8' },
      );
      if (r.status !== 0) throw new Error(r.stderr || r.stdout || 'migration failed');
    }
    applyMigration();
    console.log('PASS: migration applied (1st run)');
    applyMigration();
    console.log('PASS: migration idempotent (2nd run)');

    expectFail(
      `UPDATE public.users SET role = 'doctor' WHERE id = 'admin-uid';`,
      'role change',
    );
    console.log('PASS: UPDATE role blocked');

    expectFail(`UPDATE public.users SET deactivated = TRUE WHERE id = 'admin-uid';`, 'suspend');
    console.log('PASS: suspend blocked');

    expectFail(`DELETE FROM public.users WHERE id = 'admin-uid';`, 'delete');
    console.log('PASS: DELETE blocked');

    psql(
      `INSERT INTO public.admin_audit_logs (log_id, admin_uid, admin_email, action, target_type, target_id, details)
       VALUES ('t1','a','a@b.com','TEST','user','x','ok');`,
    );
    expectFail(`UPDATE public.admin_audit_logs SET action='X' WHERE log_id='t1';`, 'audit update');
    console.log('PASS: audit append-only');
  } finally {
    try {
      sh(`docker rm -f ${CONTAINER}`);
    } catch (_) {}
  }
  console.log('\nRDS docker validation: ALL PASS');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
