#!/usr/bin/env node
'use strict';

/**
 * Validate an env file against the production/staging boot requirements BEFORE deploying.
 *
 *   npm run check:boot-env -- <env-file> [--target functions|gateway|all] [--app-env staging|production]
 *
 * Runs the real boot assertions of backend/functions (index.js cold-start sequence) and of the
 * API gateway (assert_production_config.js) in a child process whose environment contains ONLY
 * the variables from <env-file> (plus a simulated Cloud Functions runtime), then adds checklist
 * checks that have no boot assertion yet (see PRODUCTION_BOOT_CHECKLIST.md).
 *
 * Secret values are never printed: every value from the file is redacted from all output.
 * Exit code: 0 = no FAIL, 1 = at least one FAIL, 2 = usage error.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '../..');
const FUNCTIONS_DIR = path.join(REPO, 'backend/functions');
const GATEWAY_DIR = path.join(REPO, 'services/api-gateway');

/** Firebase defineSecret() names: must come from Secret Manager, never a plain env file. */
const FUNCTIONS_SECRET_MANAGER_KEYS = [
  'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'DEMO_SUPABASE_SERVICE_ROLE_KEY',
  'PROD_GATEWAY_SERVICE_KEY', 'RAZORPAY_WEBHOOK_SECRET', 'REDIS_PASSWORD', 'REVIEW_FIXED_OTP',
  'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_WEBHOOK_SECRET',
];

function parseEnvFile(file) {
  const out = {};
  const text = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const m = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    let v = m[2];
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    } else {
      v = v.replace(/\s+#.*$/, '').trim();
    }
    out[m[1]] = v;
  }
  return out;
}

function makeRedactor(env) {
  const plain = new Set(['production', 'staging', 'test', 'true', 'false', 'on', 'off', 'yes']);
  const values = Object.values(env).map(String)
    .filter((v) => v.length >= 4 && !plain.has(v.trim().toLowerCase()))
    .sort((a, b) => b.length - a.length);
  return (text) => {
    let s = String(text);
    for (const v of values) s = s.split(v).join('<redacted>');
    return s;
  };
}

function baseChildEnv(fileEnv) {
  const keep = {};
  for (const k of ['PATH', 'Path', 'SystemRoot', 'TEMP', 'TMP', 'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA']) {
    if (process.env[k]) keep[k] = process.env[k];
  }
  return { ...keep, ...fileEnv };
}

const FUNCTIONS_PROBE = `
const results = [];
const run = (name, fn) => {
  try { fn(); results.push({ name, status: 'PASS' }); }
  catch (e) { results.push({ name, status: 'FAIL', message: e && e.message }); }
};
const warn = [];
const a = require('./src/db/assert_app_env');
const otp = require('./production_otp_guard');
run('production OTP backdoor guard (OTP_TEST_MODE / DEMO_PHONE_*)', () => otp.assertProductionOtpSafety());
run('FIRESTORE_FORBIDDEN=1 in production', () => a.assertProductionFirestoreForbidden());
if (a.shouldRunCutoverBootAsserts()) {
  const appEnv = String(process.env.APP_ENV || 'staging').trim().toLowerCase();
  run('database routing (PROD_GATEWAY_URL / staging Supabase)', () => a.assertAppEnvDatabaseRouting({ requireStagingDb: appEnv === 'staging' }));
  run('staging/production resource isolation (S3 bucket, Redis host)', () => a.assertStagingProductionResourceIsolation());
  run('Redis TLS (rediss://, REDIS_TLS, cert verification)', () => a.assertProductionRedisTls());
  run('OTP HMAC only (no ALLOW_LEGACY_UNSALTED_OTP_HASH)', () => a.assertProductionOtpHmacOnly());
  a.warnProductionOtpHmacFallback(process.env, (m) => warn.push(m));
  run('App Check enforcement', () => a.assertProductionAppCheckEnforcement());
  run('reviewer OTP policy', () => a.assertProductionReviewerOtpPolicy());
  run('no .env.example placeholder secrets', () => a.assertProductionNoPlaceholderSecrets());
  try { a.assertProductionCutoverBoot(); results.push({ name: 'cutover completeness (DATABASE_URL, Redis, MSG91)', status: 'PASS' }); }
  catch (e) { results.push({ name: 'cutover completeness (DATABASE_URL, Redis, MSG91)', status: 'WARN', message: e.message + ' [checklist item; not yet enforced at cold start]' }); }
} else {
  results.push({ name: 'cutover boot asserts', status: 'WARN', message: 'skipped (APP_ENV=test or SKIP_APP_ENV_DB_ASSERT=true)' });
}
for (const m of warn) results.push({ name: 'OTP HMAC pepper', status: 'WARN', message: m });
process.stdout.write('@@RESULTS@@' + JSON.stringify(results));
`;

const GATEWAY_PROBE = `
const results = [];
try {
  require('./src/assert_production_config').assertProductionGatewayConfig({}, process.env);
  results.push({ name: 'gateway production config (PGRST_JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY)', status: 'PASS' });
} catch (e) {
  results.push({ name: 'gateway production config (PGRST_JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY)', status: 'FAIL', message: e.message });
}
process.stdout.write('@@RESULTS@@' + JSON.stringify(results));
`;

function runProbe(cwd, code, env, label, redact) {
  const r = spawnSync(process.execPath, ['-e', code], { cwd, env, encoding: 'utf8', timeout: 60000 });
  const out = r.stdout || '';
  const idx = out.indexOf('@@RESULTS@@');
  if (idx < 0) {
    return [{ name: `${label} probe`, status: 'FAIL', message: redact(`probe crashed: ${(r.stderr || out).split(/\r?\n/).slice(0, 6).join(' | ')}`) }];
  }
  return JSON.parse(out.slice(idx + '@@RESULTS@@'.length)).map((x) => ({ ...x, message: x.message ? redact(x.message) : undefined }));
}

function has(env, k) {
  return String(env[k] || '').trim().length > 0;
}

function checklistFunctions(env, appEnv) {
  const r = [];
  const prod = appEnv === 'production';
  const need = (keys, label, sev = 'FAIL') => {
    const ok = keys.some((k) => has(env, k));
    r.push({ name: label, status: ok ? 'PASS' : sev, message: ok ? undefined : `missing ${keys.join(' or ')}` });
  };
  need(['APP_ENV'], 'APP_ENV set');
  need(['MSG91_AUTH_KEY', 'MSG91_AUTHKEY'], 'MSG91 auth key (OTP SMS)');
  need(['MSG91_TEMPLATE_ID_LOGIN', 'MSG91_TEMPLATE_ID'], 'MSG91 login template', 'WARN');
  need(['MSG91_TEMPLATE_ID_REGISTRATION', 'MSG91_TEMPLATE_ID'], 'MSG91 registration template', 'WARN');
  need(['RAZORPAY_KEY_ID'], 'RAZORPAY_KEY_ID (promoted ad payments)', prod ? 'FAIL' : 'WARN');
  need(['RAZORPAY_KEY_SECRET'], 'RAZORPAY_KEY_SECRET (promoted ad payments)', prod ? 'FAIL' : 'WARN');
  if (prod) {
    need(['S3_BUCKET_PRODUCTION', 'S3_BUCKET'], 'S3 production bucket');
    need(['OTP_HMAC_SECRET'], 'OTP_HMAC_SECRET (dedicated OTP pepper)', 'WARN');
    need(['SUPER_ADMIN_EMAILS'], 'SUPER_ADMIN_EMAILS (super-admin allow-list; empty = no email super admins)', 'WARN');
    const hops = String(env.TRUSTED_PROXY_HOPS || '').trim();
    if (hops && !/^(10|[1-9])$/.test(hops)) r.push({ name: 'TRUSTED_PROXY_HOPS', status: 'FAIL', message: 'must be an integer 1-10' });
  } else {
    need(['S3_BUCKET_STAGING', 'S3_BUCKET'], 'S3 staging bucket');
  }
  r.push(...checklistDemoAccounts(env, prod));
  const inFile = FUNCTIONS_SECRET_MANAGER_KEYS.filter((k) => has(env, k));
  r.push({
    name: 'Secret Manager secrets not stored in the env file',
    status: inFile.length ? 'WARN' : 'PASS',
    message: inFile.length ? `move to Firebase Secret Manager: ${inFile.join(', ')}` : undefined,
  });
  return r;
}

/**
 * Demo / reviewer accounts (docs/DEMO_ACCOUNTS.md). Numbers and roles are fixed in code; these
 * variables only switch the demo OTP on and point at the staging plane.
 */
function checklistDemoAccounts(env, prod) {
  const r = [];
  const on = String(env.REVIEWER_OTP_ENABLED || '').trim().toLowerCase() === 'true';
  const obsolete = ['REVIEW_PATIENT_PHONES', 'REVIEW_DOCTOR_PHONES', 'REVIEW_MEDICAL_STORE_PHONES',
    'REVIEW_MEDICALSTORE_PHONES', 'REVIEW_LAB_PHONES', 'REVIEW_AMBULANCE_PHONES', 'REVIEW_TEST_NUMBERS',
    'DEMO_PHONE_NUMBERS', 'DEMO_FIXED_OTP'].filter((k) => has(env, k));
  if (obsolete.length) {
    r.push({ name: 'obsolete demo variables', status: 'WARN', message: `ignored now (numbers are fixed in code), remove: ${obsolete.join(', ')}` });
  }
  if (!on) {
    r.push({ name: 'demo OTP (REVIEWER_OTP_ENABLED)', status: 'PASS', message: 'off: demo numbers cannot log in' });
    return r;
  }
  const until = String(env.REVIEW_ACCESS_UNTIL || '').trim();
  const t = new Date(until).getTime();
  r.push({
    name: 'REVIEW_ACCESS_UNTIL (demo OTP on)',
    status: until && !Number.isNaN(t) && t > Date.now() ? 'PASS' : 'FAIL',
    message: !until ? 'missing' : (Number.isNaN(t) ? 'not an ISO 8601 date' : (t <= Date.now() ? 'in the past' : undefined)),
  });
  if (prod) {
    r.push({ name: 'DEMO_SUPABASE_URL (demo OTP on)', status: has(env, 'DEMO_SUPABASE_URL') ? 'PASS' : 'FAIL',
      message: has(env, 'DEMO_SUPABASE_URL') ? undefined : 'missing: demo logins have no staging plane' });
    r.push({ name: 'DEMO_SUPABASE_SERVICE_ROLE_KEY secret (demo OTP on)', status: 'WARN',
      message: 'must be set in Secret Manager: firebase functions:secrets:get DEMO_SUPABASE_SERVICE_ROLE_KEY (cannot be checked from a file)' });
  }
  const fixed = String(env.REVIEW_FIXED_OTP || '').trim();
  if (fixed) {
    r.push({ name: 'REVIEW_FIXED_OTP location', status: prod ? 'FAIL' : 'WARN',
      message: 'must be a Firebase secret, not a plain env value (firebase functions:secrets:set REVIEW_FIXED_OTP)' });
    if (!/^\d{6}$/.test(fixed)) r.push({ name: 'REVIEW_FIXED_OTP format', status: 'FAIL', message: 'must be exactly 6 digits' });
  } else {
    r.push({ name: 'REVIEW_FIXED_OTP secret (demo OTP on)', status: 'WARN',
      message: 'must be set in Secret Manager (6 digits); the OTP functions refuse to start without it' });
  }
  return r;
}

function checklistGateway(env, appEnv) {
  const r = [];
  const prod = appEnv === 'production';
  const need = (k, label, sev = 'FAIL') => r.push({ name: label, status: has(env, k) ? 'PASS' : sev, message: has(env, k) ? undefined : `missing ${k}` });
  need('PGRST_URL', 'PGRST_URL (upstream PostgREST for RDS)', prod ? 'FAIL' : 'WARN');
  need('FIREBASE_PROJECT_ID', 'FIREBASE_PROJECT_ID (token audience)', 'WARN');
  need('CORS_ALLOWED_ORIGINS', 'CORS_ALLOWED_ORIGINS', 'WARN');
  need('TRUSTED_PROXY_HOPS', 'TRUSTED_PROXY_HOPS (ALB = 1)', 'WARN');
  if (prod && String(env.FIREBASE_REVOCATION_CHECK || '').trim().toLowerCase() === 'false') {
    r.push({ name: 'FIREBASE_REVOCATION_CHECK', status: 'FAIL', message: 'must not be false in production' });
  }
  if (prod) {
    // The five demo UIDs always route to the demo upstream in production.
    const sev = String(env.DEMO_REAL_ROUTING_ENABLED || '').trim() === '1' ? 'FAIL' : 'WARN';
    need('DEMO_PGRST_URL', 'DEMO_PGRST_URL (demo accounts get 503 without it)', sev);
    need('DEMO_PGRST_JWT_SECRET', 'DEMO_PGRST_JWT_SECRET (demo accounts get 503 without it)', sev);
  }
  if (has(env, 'PGRST_URL') && prod && /\.supabase\.co/i.test(env.PGRST_URL)) {
    r.push({ name: 'PGRST_URL target', status: 'FAIL', message: 'production gateway must not point at supabase.co' });
  }
  return r;
}

function main() {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith('--'));
  const target = ((args.find((a) => a.startsWith('--target=')) || '').split('=')[1])
    || (args.includes('--target') ? args[args.indexOf('--target') + 1] : 'all');
  const appEnvOverride = ((args.find((a) => a.startsWith('--app-env=')) || '').split('=')[1]) || null;
  if (!file || !fs.existsSync(file) || !['functions', 'gateway', 'all'].includes(target)) {
    console.error('usage: npm run check:boot-env -- <env-file> [--target=functions|gateway|all] [--app-env=staging|production]');
    process.exit(2);
  }

  const fileEnv = parseEnvFile(file);
  if (appEnvOverride) fileEnv.APP_ENV = appEnvOverride;
  const appEnv = String(fileEnv.APP_ENV || 'staging').trim().toLowerCase();
  const redact = makeRedactor(fileEnv);
  const results = [];

  if (target === 'functions' || target === 'all') {
    const env = {
      ...baseChildEnv(fileEnv),
      K_SERVICE: 'boot-env-check',
      FUNCTION_TARGET: 'bootEnvCheck',
    };
    if (appEnv === 'production' && !env.GCLOUD_PROJECT && !env.FIREBASE_CONFIG) env.GCLOUD_PROJECT = 'medibond-45fad';
    for (const x of runProbe(FUNCTIONS_DIR, FUNCTIONS_PROBE, env, 'functions', redact)) results.push({ scope: 'functions', ...x });
    for (const x of checklistFunctions(fileEnv, appEnv)) results.push({ scope: 'functions', ...x });
  }
  if (target === 'gateway' || target === 'all') {
    const env = baseChildEnv(fileEnv);
    for (const x of runProbe(GATEWAY_DIR, GATEWAY_PROBE, env, 'gateway', redact)) results.push({ scope: 'gateway', ...x });
    for (const x of checklistGateway(fileEnv, appEnv)) results.push({ scope: 'gateway', ...x });
  }

  console.log(`check:boot-env  file=${path.basename(file)}  APP_ENV=${appEnv}  target=${target}  keys=${Object.keys(fileEnv).length}`);
  for (const r of results) {
    console.log(`${r.status.padEnd(4)}  [${r.scope}] ${r.name}${r.message ? `\n        ${redact(r.message)}` : ''}`);
  }
  const fails = results.filter((r) => r.status === 'FAIL').length;
  const warns = results.filter((r) => r.status === 'WARN').length;
  console.log(`\n${fails} FAIL, ${warns} WARN, ${results.length - fails - warns} PASS`);
  process.exit(fails ? 1 : 0);
}

if (require.main === module) main();

module.exports = { parseEnvFile, makeRedactor };
