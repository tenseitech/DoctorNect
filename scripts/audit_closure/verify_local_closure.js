#!/usr/bin/env node
'use strict';

/**
 * Local audit-closure verification (no secrets printed).
 * Exit 0 when all locally runnable checks pass.
 */
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..', '..');

function run(cmd, args, cwd = root) {
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', shell: process.platform === 'win32' });
  return {
    ok: !r.error && r.status === 0,
    status: r.status,
    stdout: (r.stdout || '').trim().slice(0, 2000),
    stderr: (r.stderr || '').trim().slice(0, 2000),
  };
}

const report = {
  generatedAt: new Date().toISOString(),
  checks: {},
};

report.checks.env_parity = run('node', ['scripts/check_env_parity.js']);
report.checks.audit1_staging_prereq = run('node', ['scripts/security/audit1_staging_prereq_check.js']);
report.checks.docker_cli = {
  ok: false,
  note: 'Docker CLI required for Audit 2 local smoke; use GitHub Actions on audit-closure branch.',
};
const docker = run('docker', ['--version']);
report.checks.docker_cli.ok = docker.ok;
if (docker.ok) report.checks.docker_cli.version = docker.stdout.split('\n')[0];

report.ok =
  report.checks.env_parity.ok &&
  report.checks.audit1_staging_prereq.status === 2; // expected blocked without staging env

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
process.exit(report.checks.env_parity.ok ? 0 : 1);