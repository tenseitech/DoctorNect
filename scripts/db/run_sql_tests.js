#!/usr/bin/env node
'use strict';

/**
 * Replays ALL migrations on throwaway Postgres 17 (Supabase staging parity) and Postgres 18
 * (RDS production parity), re-applies the post-audit migrations to prove idempotency, then runs every
 * db/tests/*.sql file inside its own transaction (rolled back), followed by the RLS coverage
 * and grant matrix audits.
 *
 *   npm run test:db                      (from repo root; needs Docker)
 *   SQL_TEST_DB_URLS=postgresql://postgres:pw@127.0.0.1:5541/postgres npm run test:db
 *
 * Options: --only=17|18   --keep (leave containers running)   --no-audits
 * Refuses any non-loopback database host: this must never touch staging or RDS.
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');
const { Client } = require('pg');
const {
  listMigrationsForTarget,
  resolveMigrationSqlPath,
} = require('../lib/migration_file_list');

const REPO = path.resolve(__dirname, '../..');
const TEST_DIR = path.join(REPO, 'db/tests');
const BOOTSTRAP = ['01_roles_and_extensions.sql', '02_auth_shim.sql', '03_legacy_compat.sql']
  .map((f) => path.join(REPO, 'db/rds_bootstrap', f));
// Applied after migrations, exactly like scripts/db/rds_bootstrap_apply.js on RDS cutover.
const POST_MIGRATE = ['04_rds_runtime_grants.sql']
  .map((f) => path.join(REPO, 'db/rds_bootstrap', f));

const args = process.argv.slice(2);
const only = (args.find((a) => a.startsWith('--only=')) || '').split('=')[1] || null;
const keep = args.includes('--keep');
const runAudits = !args.includes('--no-audits');

const IDEMPOTENT_SINCE = '20261124000000';

const CRON_MOCK = `
CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE IF NOT EXISTS cron.job (
  jobid serial PRIMARY KEY, schedule text NOT NULL, command text NOT NULL,
  nodename text DEFAULT 'localhost', nodeport integer DEFAULT 5432,
  database text DEFAULT current_database(), username text DEFAULT current_user,
  active boolean DEFAULT true, jobname text UNIQUE);
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command) VALUES (job_name, schedule, command)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid INTO v_id;
  RETURN v_id;
END; $$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN DELETE FROM cron.job WHERE jobname = job_name; RETURN FOUND; END; $$;
`;

function assertLoopback(url) {
  const host = new URL(url.replace(/^postgres:\/\//i, 'postgresql://')).hostname;
  if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)) {
    throw new Error(`Refusing non-local database host "${host}". SQL tests only run on throwaway local Postgres.`);
  }
}

function dockerOk() {
  const r = spawnSync('docker', ['info', '--format', '{{.ServerVersion}}'], { encoding: 'utf8' });
  return r.status === 0 && /\d/.test(r.stdout || '');
}

async function waitReady(url, ms = 60000) {
  const end = Date.now() + ms;
  let lastErr;
  while (Date.now() < end) {
    const c = new Client({ connectionString: url });
    try {
      await c.connect();
      await c.query('SELECT 1');
      await c.end();
      return;
    } catch (e) {
      lastErr = e;
      await c.end().catch(() => {});
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw new Error(`Postgres not ready: ${lastErr && lastErr.message}`);
}

function startContainer(major, port) {
  const name = `doctornect-sqltest-pg${major}`;
  spawnSync('docker', ['rm', '-f', name], { stdio: 'ignore' });
  execSync(`docker run -d --name ${name} -e POSTGRES_PASSWORD=sqltest -p 127.0.0.1:${port}:5432 postgres:${major}`, { stdio: 'pipe' });
  return { name, url: `postgresql://postgres:sqltest@127.0.0.1:${port}/postgres` };
}

async function applyMigrations(client, target, label, { since = null } = {}) {
  const hasCron = (await client.query(`SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'`)).rowCount > 0;
  const files = listMigrationsForTarget(target).filter((rel) => !since || path.basename(rel) >= since);
  for (const rel of files) {
    const { sqlPath } = resolveMigrationSqlPath({ relPath: rel, target });
    let sql = fs.readFileSync(sqlPath, 'utf8');
    if (!hasCron) sql = sql.replace(/CREATE EXTENSION IF NOT EXISTS pg_cron;/gi, '-- pg_cron mocked');
    try {
      await client.query(sql);
    } catch (e) {
      throw new Error(`[${label}] migration ${rel} failed: ${e.message}${e.where ? `\n  where: ${e.where}` : ''}`);
    }
  }
  return files.length;
}

async function runSqlTests(client, label) {
  const helpers = fs.readFileSync(path.join(TEST_DIR, '00_helpers.sql'), 'utf8');
  const files = fs.readdirSync(TEST_DIR).filter((f) => /^\d+_.+\.sql$/.test(f) && f !== '00_helpers.sql').sort();
  let failed = 0;
  let checks = 0;
  for (const f of files) {
    const notices = [];
    const onNotice = (n) => { if (/^ok /.test(n.message)) notices.push(n.message); };
    client.on('notice', onNotice);
    try {
      await client.query('BEGIN');
      await client.query(helpers);
      await client.query(fs.readFileSync(path.join(TEST_DIR, f), 'utf8'));
      console.log(`  PASS ${f} (${notices.length} checks)`);
    } catch (e) {
      failed += 1;
      console.log(`  FAIL ${f} after ${notices.length} checks: ${e.message}`);
    } finally {
      await client.query('ROLLBACK').catch(() => {});
      client.off('notice', onNotice);
      checks += notices.length;
    }
  }
  console.log(`[${label}] SQL tests: ${files.length - failed}/${files.length} files passed, ${checks} checks`);
  return failed;
}

function runAudit(script, url, label) {
  const r = spawnSync(process.execPath, [path.join(__dirname, script)], {
    cwd: REPO,
    encoding: 'utf8',
    env: { ...process.env, REPLAY_DB_URL: url, LOCAL_FRESH_DB_URL: url, FRESH_LOCAL_DB_NAME: new URL(url).pathname.slice(1) || 'postgres' },
  });
  const out = `${r.stdout || ''}${r.stderr || ''}`.trim().split(/\r?\n/).slice(-15).join('\n');
  console.log(`[${label}] ${script} exit=${r.status}\n${out}`);
  return r.status === 0 ? 0 : 1;
}

async function runTarget({ label, url, target }) {
  assertLoopback(url);
  await waitReady(url);
  const client = new Client({ connectionString: url });
  await client.connect();
  let failures = 0;
  try {
    for (const f of BOOTSTRAP) await client.query(fs.readFileSync(f, 'utf8'));
    await client.query(CRON_MOCK);
    const n = await applyMigrations(client, target, label);
    for (const f of POST_MIGRATE) await client.query(fs.readFileSync(f, 'utf8'));
    console.log(`[${label}] applied ${n} migrations + runtime grants`);
    // Historical migrations are applied once via the checksum ledger (scripts/db/migrate.js) and are
    // not edited; migrations added since the 2026-11 audit must be safely re-runnable.
    const rerun = await applyMigrations(client, target, `${label} re-run`, { since: IDEMPOTENT_SINCE });
    console.log(`[${label}] re-applied ${rerun} migrations >= ${IDEMPOTENT_SINCE}: idempotent`);
    failures += await runSqlTests(client, label);
  } catch (e) {
    console.log(e.message);
    failures += 1;
  } finally {
    await client.end().catch(() => {});
  }
  if (runAudits && failures === 0) {
    failures += runAudit('rls_coverage_audit.js', url, label);
    failures += runAudit('grant_matrix_audit.js', url, label);
  }
  return failures;
}

async function main() {
  const targets = [];
  const containers = [];
  if (process.env.SQL_TEST_DB_URLS) {
    process.env.SQL_TEST_DB_URLS.split(',').map((s) => s.trim()).filter(Boolean)
      .forEach((url, i) => targets.push({ label: `db${i + 1}`, url, target: 'replay' }));
  } else {
    if (!dockerOk()) {
      console.error('Docker engine is not reachable (docker info failed). Start Docker Desktop and wait until it reports "Engine running", or set SQL_TEST_DB_URLS to local throwaway Postgres URLs.');
      process.exit(2);
    }
    for (const [major, port, target] of [[17, 5541, 'replay'], [18, 5542, 'replay']]) {
      if (only && String(major) !== only) continue;
      const c = startContainer(major, port);
      containers.push(c.name);
      targets.push({ label: `pg${major}`, url: c.url, target });
    }
  }
  let failures = 0;
  try {
    for (const t of targets) failures += await runTarget(t);
  } finally {
    if (!keep) for (const name of containers) spawnSync('docker', ['rm', '-f', name], { stdio: 'ignore' });
  }
  console.log(failures === 0 ? 'ALL SQL TESTS PASSED' : `${failures} failure(s)`);
  process.exit(failures === 0 ? 0 : 1);
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { assertLoopback };
