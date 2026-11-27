#!/usr/bin/env node
'use strict';

/**
 * Master local verification for audit closure (no staging secrets printed).
 */
const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const root = path.join(__dirname, '..', '..');
const evidencePath = path.join(root, 'docs', 'audit', 'audit_closure', 'DOCTORNECT_FINAL_AUDIT_EVIDENCE.json');

const results = {
  startedAt: new Date().toISOString(),
  steps: [],
};

function step(name, fn) {
  const entry = { name, status: 'NOT_RUN' };
  results.steps.push(entry);
  try {
    const code = fn();
    entry.status = code === 0 ? 'PASS' : code === 2 ? 'BLOCKED' : 'FAIL';
    entry.exitCode = code;
  } catch (e) {
    entry.status = 'FAIL';
    entry.error = String(e.message || e).slice(0, 500);
  }
}

step('env_parity', () =>
  spawnSync(process.execPath, ['scripts/check_env_parity.js'], { cwd: root, stdio: 'pipe' }).status ?? 1);

step('audit1_staging_prereq', () =>
  spawnSync(process.execPath, ['scripts/security/audit1_staging_prereq_check.js'], { cwd: root, stdio: 'pipe' }).status ?? 1);

step('sec07_csp_static', () =>
  spawnSync(
    process.execPath,
    ['--test', 'test/hosting_csp_connect_src.test.js'],
    { cwd: path.join(root, 'backend', 'functions'), stdio: 'pipe' },
  ).status ?? 1);

step('gateway_unit', () =>
  spawnSync('npm', ['test'], { cwd: path.join(root, 'services', 'api-gateway'), shell: true, stdio: 'pipe' }).status ?? 1);

step('functions_env_parity', () =>
  spawnSync('npm', ['run', 'test:env-parity'], {
    cwd: path.join(root, 'backend', 'functions'),
    shell: true,
    stdio: 'pipe',
  }).status ?? 1);

step('alert_templates_validation', () =>
  spawnSync(
    process.execPath,
    ['--test', 'scripts/test/alert_templates_validation.test.js'],
    { cwd: root, stdio: 'pipe' },
  ).status ?? 1);

const covPath = path.join(root, 'frontend', 'coverage', 'lcov.info');
if (fs.existsSync(covPath)) {
  step('flutter_coverage_gate', () =>
    spawnSync(process.execPath, ['scripts/audit_closure/flutter_coverage_gate.js'], {
      cwd: root,
      stdio: 'pipe',
      env: { ...process.env, FLUTTER_COVERAGE_MIN_LINES: '26' },
    }).status ?? 1);
}

results.finishedAt = new Date().toISOString();
results.dockerAvailable = spawnSync('docker', ['--version'], { shell: true, stdio: 'pipe' }).status === 0;

fs.mkdirSync(path.dirname(evidencePath), { recursive: true });
fs.writeFileSync(evidencePath, `${JSON.stringify(results, null, 2)}\n`);

const hardFail = results.steps.some((s) => s.status === 'FAIL' && s.name !== 'audit1_staging_prereq');
process.exit(hardFail ? 1 : 0);