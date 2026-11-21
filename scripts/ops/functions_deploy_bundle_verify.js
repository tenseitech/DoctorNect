'use strict';

/**
 * Simulates Firebase upload bundle (backend/functions only) and verifies index.js loads
 * under Cloud Run env (K_SERVICE / FUNCTION_TARGET) without repo-root scripts/.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const { findRepoRoot } = require('../lib/repo_root');

const OTP_EXPORTS = [
  'sendUserRegistrationOtp',
  'verifyUserRegistrationOtp',
  'completeMobileOtpLogin',
  'completeAmbulanceMobileOtpLogin',
];

const FIREBASE_IGNORE = [
  'node_modules',
  '.git',
  'firebase-debug.log',
  '*.local',
  '.env',
  '.env.local',
  '.env.production',
  '.env.medibond-45fad',
  '**/.env*',
  '**/*.bak*',
  '**/.secret*',
  '**/service-account*',
  '.secret.local',
  'secrets/**',
  '*.p12',
  'service-account*.json',
];

function globMatch(rel, pattern) {
  const norm = rel.replace(/\\/g, '/');
  const pat = pattern.replace(/\\/g, '/');
  if (pat.includes('**')) {
    const suffix = pat.replace(/^\*\*\//, '');
    if (suffix && norm.includes(suffix)) return true;
    const re = new RegExp(
      `^${pat
        .replace(/\./g, '\\.')
        .replace(/\*\*/g, '.*')
        .replace(/\*/g, '[^/]*')}$`,
    );
    return re.test(norm);
  }
  if (pat.startsWith('*.')) {
    return norm.endsWith(pat.slice(1));
  }
  return norm === pat || norm.endsWith(`/${pat}`);
}

function shouldIgnore(relPath) {
  const r = relPath.replace(/\\/g, '/');
  return FIREBASE_IGNORE.some((p) => globMatch(r, p));
}

function copyFunctionsBundle(src, dest) {
  function walk(relDir) {
    const abs = path.join(src, relDir);
    for (const ent of fs.readdirSync(abs, { withFileTypes: true })) {
      const rel = relDir ? `${relDir}/${ent.name}` : ent.name;
      if (shouldIgnore(rel)) continue;
      const destPath = path.join(dest, rel);
      if (ent.isDirectory()) {
        fs.mkdirSync(destPath, { recursive: true });
        walk(rel);
      } else {
        fs.mkdirSync(path.dirname(destPath), { recursive: true });
        fs.copyFileSync(path.join(abs, ent.name), destPath);
      }
    }
  }
  fs.mkdirSync(dest, { recursive: true });
  walk('');
}

function loadEnvFileIntoProcess(envPath) {
  if (!fs.existsSync(envPath)) return 0;
  let n = 0;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const k = t.slice(0, eq);
    if (process.env[k] !== undefined) continue;
    process.env[k] = t.slice(eq + 1);
    n += 1;
  }
  return n;
}

function runChildLoad({ bundleDir, functionsEnvPath, service, target, secretEnvKeys = [] }) {
  const envPath = functionsEnvPath.replace(/\\/g, '/');
  const secretSet = secretEnvKeys
    .map((k) => `process.env[${JSON.stringify(k)}]='mock-secret';`)
    .join('');
  const script = `
    const fs = require('fs');
    const envPath = ${JSON.stringify(envPath)};
    if (fs.existsSync(envPath)) {
      for (const line of fs.readFileSync(envPath, 'utf8').split(/\\r?\\n/)) {
        const t = line.trim();
        if (!t || t.startsWith('#')) continue;
        const eq = t.indexOf('=');
        if (eq <= 0) continue;
        const k = t.slice(0, eq);
        if (process.env[k] === undefined) process.env[k] = t.slice(eq + 1);
      }
    }
    ${secretSet}
    process.env.K_SERVICE = ${JSON.stringify(service)};
    process.env.FUNCTION_TARGET = ${JSON.stringify(target)};
    process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'medibond-45fad';
    process.env.SKIP_APP_ENV_DB_ASSERT = process.env.SKIP_APP_ENV_DB_ASSERT || 'true';
    const t0 = Date.now();
    const mod = require('./index.js');
    const missing = ${JSON.stringify(OTP_EXPORTS)}.filter((n) => typeof mod[n] !== 'function');
    if (missing.length) throw new Error('Missing exports: ' + missing.join(','));
    console.log('BUNDLE_LOAD_MS=' + (Date.now() - t0));
    console.log('BUNDLE_LOAD_OK=1');
  `;
  return spawnSync(process.execPath, ['-e', script], {
    cwd: bundleDir,
    encoding: 'utf8',
    timeout: 120000,
    env: { ...process.env, NODE_ENV: 'production' },
  });
}

function simulateLegacyBootstrapFailure(bundleDir) {
  const script = `
    try {
      require('../../scripts/lib/bootstrap_root_env').loadRootEnv();
      console.log('LEGACY_UNEXPECTED_OK=1');
    } catch (e) {
      console.log('LEGACY_EXPECTED_FAIL=1');
      console.log('LEGACY_ERR=' + (e.code || 'error'));
    }
  `;
  return spawnSync(process.execPath, ['-e', script], {
    cwd: bundleDir,
    encoding: 'utf8',
    timeout: 15000,
    env: { ...process.env },
  });
}

function main() {
  const root = findRepoRoot();
  const src = path.join(root, 'backend', 'functions');
  const envPath = path.join(src, '.env');
  const tmpBase = fs.mkdtempSync(path.join(os.tmpdir(), 'fn-bundle-'));
  const bundleDir = path.join(tmpBase, 'functions');
  copyFunctionsBundle(src, bundleDir);
  const srcModules = path.join(src, 'node_modules');
  const destModules = path.join(bundleDir, 'node_modules');
  if (fs.existsSync(srcModules) && !fs.existsSync(destModules)) {
    fs.cpSync(srcModules, destModules, { recursive: true });
  }

  const legacy = simulateLegacyBootstrapFailure(bundleDir);
  const legacyOut = (legacy.stdout || '') + (legacy.stderr || '');
  const legacyFail = legacyOut.includes('LEGACY_EXPECTED_FAIL') || legacyOut.includes('MODULE_NOT_FOUND');

  const targets = [
    ['senduserregistrationotp', 'sendUserRegistrationOtp', []],
    ['verifyuserregistrationotp', 'verifyUserRegistrationOtp', []],
    ['completemobileotplogin', 'completeMobileOtpLogin', ['SUPABASE_SERVICE_ROLE_KEY']],
    ['completeambulancemobileotplogin', 'completeAmbulanceMobileOtpLogin', []],
  ];

  const sendSecrets = [];
  const mirrorOn = String(process.env.OTP_REDIS_MIRROR || '').trim().toLowerCase() === 'on';
  if (mirrorOn) {
    sendSecrets.push('REDIS_HOST', 'REDIS_PORT', 'REDIS_PASSWORD');
  }
  targets[0][2] = [...sendSecrets, 'SUPABASE_SERVICE_ROLE_KEY'];
  targets[1][2] = [...sendSecrets, 'SUPABASE_SERVICE_ROLE_KEY'];

  let pass = 0;
  let fail = 0;
  const timings = [];

  for (const [service, target, secrets] of targets) {
    const res = runChildLoad({
      bundleDir,
      functionsEnvPath: fs.existsSync(envPath) ? envPath : '',
      service,
      target,
      secretEnvKeys: secrets,
    });
    const out = (res.stdout || '') + (res.stderr || '');
  if (res.status === 0 && out.includes('BUNDLE_LOAD_OK=1')) {
      pass += 1;
      const m = out.match(/BUNDLE_LOAD_MS=(\d+)/);
      if (m) timings.push(Number(m[1]));
    } else {
      fail += 1;
      console.error(`FAIL ${target} exit=${res.status}`);
      console.error(out.trim().split('\n').slice(-6).join('\n'));
    }
  }

  const report = {
    bundleDir,
    legacyBootstrapReproducedFail: legacyFail,
    otpExportsPass: pass,
    otpExportsFail: fail,
    loadMsMin: timings.length ? Math.min(...timings) : null,
    loadMsMax: timings.length ? Math.max(...timings) : null,
    envKeysFromFile: fs.existsSync(envPath) ? 'present' : 'missing',
  };

  console.log(JSON.stringify(report, null, 2));

  try {
    fs.rmSync(tmpBase, { recursive: true, force: true });
  } catch (_) {}

  if (fail > 0 || !legacyFail) {
    process.exit(2);
  }
  process.exit(0);
}

if (require.main === module) {
  main();
}

module.exports = {
  copyFunctionsBundle,
  runChildLoad,
  simulateLegacyBootstrapFailure,
  OTP_EXPORTS,
};