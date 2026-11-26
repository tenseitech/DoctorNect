'use strict';

/**
 * Security Audit 1 staging prerequisite check (no secrets printed).
 * Exit 0 only when documented staging validation can run safely.
 */
const fs = require('fs');
const path = require('path');

require(path.join(__dirname, '..', 'lib', 'bootstrap_root_env')).loadRootEnv();

const REQUIRED = {
  SEC_04: [
    'AUDIT1_STAGING_GATEWAY_URL',
    'AUDIT1_TEST_FIREBASE_EMAIL',
    'AUDIT1_TEST_FIREBASE_PASSWORD',
    'AUDIT1_FIREBASE_PROJECT_ID',
    'AUDIT1_FIREBASE_WEB_API_KEY',
    'GOOGLE_APPLICATION_CREDENTIALS',
  ],
  SEC_07: ['AUDIT1_STAGING_HOSTING_URL'],
  SEC_08: [
    'AUDIT1_STAGING_GATEWAY_URL',
    'AWS_REGION',
  ],
};

function isSet(key) {
  const v = String(process.env[key] || '').trim();
  return Boolean(v);
}

function credsFileOk() {
  const p = String(process.env.GOOGLE_APPLICATION_CREDENTIALS || '').trim();
  if (!p) return false;
  const abs = path.isAbsolute(p) ? p : path.join(path.join(__dirname, '..', '..'), p);
  return fs.existsSync(abs);
}

const report = { ok: true, checks: {} };

for (const [section, keys] of Object.entries(REQUIRED)) {
  const missing = keys.filter((k) => !isSet(k));
  if (section === 'SEC_04' && isSet('GOOGLE_APPLICATION_CREDENTIALS') && !credsFileOk()) {
    missing.push('GOOGLE_APPLICATION_CREDENTIALS (file not found)');
  }
  if (section === 'SEC_08') {
    const hasAws = isSet('AWS_ACCESS_KEY_ID') || isSet('AWS_PROFILE');
    if (!hasAws) missing.push('AWS credentials (CLI/profile not configured in env)');
    try {
      const { spawnSync } = require('child_process');
      const r = spawnSync('aws', ['--version'], { encoding: 'utf8', shell: true });
      if (r.error || r.status !== 0) missing.push('AWS CLI (aws) not available on PATH');
    } catch (_) {
      missing.push('AWS CLI (aws) not available on PATH');
    }
  }
  report.checks[section] = { ready: missing.length === 0, missing };
  if (missing.length) report.ok = false;
}

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
process.exit(report.ok ? 0 : 2);