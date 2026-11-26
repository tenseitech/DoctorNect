#!/usr/bin/env node
'use strict';

/**
 * Validate an env file against the production/staging boot requirements BEFORE deploying.
 *
 *   npm run check:boot-env -- <env-file> [--target functions|gateway|all] [--app-env staging|production] [--check-secret-manager]
 *
 * --check-secret-manager asks Firebase (firebase functions:secrets:get, metadata only) whether every
 * secret the deploy binds exists with an enabled version. Without it those show as CHECK (exit 1).
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
const crypto = require('crypto');

const REPO = path.resolve(__dirname, '../..');
const FUNCTIONS_DIR = path.join(REPO, 'backend/functions');
const GATEWAY_DIR = path.join(REPO, 'services/api-gateway');

/** Firebase defineSecret() names: must come from Secret Manager, never a plain env file. */
const FUNCTIONS_SECRET_MANAGER_KEYS = [
  'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'DEMO_SUPABASE_SERVICE_ROLE_KEY', 'OTP_HMAC_SECRET',
  'PROD_GATEWAY_SERVICE_KEY', 'RAZORPAY_WEBHOOK_SECRET', 'REDIS_PASSWORD', 'REVIEW_FIXED_OTP',
  'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_WEBHOOK_SECRET',
];

const FIREBASE_PROJECT = 'medibond-45fad';
/** Where each Secret Manager value comes from (shown when one is missing). */
const SECRET_SOURCE_HINT = {
  PROD_GATEWAY_SERVICE_KEY: 'infra/aws/set_gateway_secrets.ps1 (same value as the gateway service_key)',
};
/** Bound names that are not secrets in the assertion sense (host/port): never simulated. */
const NOT_SIMULATED = new Set(['REDIS_HOST', 'REDIS_PORT']);

/**
 * Secret names the deploy binds, read from the real function manifests (index.js loaded in test
 * mode). The set depends on OTP_REDIS_MIRROR in the checked file. Falls back to the static list.
 */
function collectBoundSecrets(fileEnv) {
  const code = "const m=require('./index.js');const s=new Set();" +
    'for(const v of Object.values(m)){if(v&&v.__endpoint)for(const x of v.__endpoint.secretEnvironmentVariables||[])s.add(x.key)}' +
    "process.stdout.write('@@BOUND@@'+JSON.stringify([...s].sort()))";
  const env = {
    ...baseChildEnv({}),
    APP_ENV: 'test', NODE_ENV: 'test', K_SERVICE: 'boot-env-manifest',
    GCLOUD_PROJECT: 'boot-env-check', FIREBASE_CONFIG: '{"projectId":"boot-env-check"}',
    OTP_REDIS_MIRROR: String(fileEnv.OTP_REDIS_MIRROR || 'off'),
  };
  const r = spawnSync(process.execPath, ['-e', code], { cwd: FUNCTIONS_DIR, env, encoding: 'utf8', timeout: 120000 });
  const out = r.stdout || '';
  const idx = out.indexOf('@@BOUND@@');
  if (idx < 0) return { names: [...FUNCTIONS_SECRET_MANAGER_KEYS].sort(), fromManifest: false };
  return { names: JSON.parse(out.slice(idx + '@@BOUND@@'.length)), fromManifest: true };
}

/** Metadata only (`firebase functions:secrets:get --json`): never reads or prints a value. */
function secretManagerState(name, project = FIREBASE_PROJECT) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name) || !/^[a-z0-9-]+$/.test(project)) return { ok: false, why: 'invalid name' };
  const r = spawnSync(`firebase functions:secrets:get ${name} --project ${project} --json`, {
    encoding: 'utf8', shell: true, timeout: 120000,
  });
  let j = null;
  try { j = JSON.parse(r.stdout || ''); } catch (_) { /* not JSON */ }
  if (!j) return { ok: false, why: 'firebase CLI did not answer (installed? logged in? firebase login)' };
  const versions = (j.result && j.result.secrets) || [];
  const enabled = versions.filter((v) => v.state === 'ENABLED').length;
  if (j.status === 'success' && enabled > 0) return { ok: true, why: `${enabled} enabled version(s)` };
  return { ok: false, why: j.status === 'success' ? 'no enabled version' : 'not found' };
}

function secretManagerResults(bound, fileEnv, { verify, project = FIREBASE_PROJECT }) {
  const names = bound.names;
  if (!verify) {
    return [{
      name: 'Secret Manager secrets (cannot be verified from a file)',
      status: 'CHECK',
      message: `the deploy binds: ${names.join(', ')}. Verify before deploying: npm run check:boot-env -- <file> --target=functions --check-secret-manager (metadata only, no values)`,
    }];
  }
  return names.map((n) => {
    const s = secretManagerState(n, project);
    return {
      name: `Secret Manager: ${n}`,
      status: s.ok ? 'PASS' : 'FAIL',
      message: s.ok ? s.why : `${s.why}; set it with ${SECRET_SOURCE_HINT[n] || 'scripts/env/set_functions_secrets.ps1'}`,
    };
  });
}

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
    // OTP_HMAC_SECRET is a bound Secret Manager secret: checked in the Secret Manager section.
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
    message: inFile.length
      ? `plain copies in this file: ${inFile.join(', ')}. The deploy never uploads them from here (secret names are dropped from the generated .env), `
        + 'but they should not live on disk: confirm they are in Secret Manager (--check-secret-manager), delete these lines, and rotate them.'
      : undefined,
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
    // DEMO_SUPABASE_SERVICE_ROLE_KEY: bound secret, checked in the Secret Manager section.
  }
  const fixed = String(env.REVIEW_FIXED_OTP || '').trim();
  if (fixed) {
    r.push({ name: 'REVIEW_FIXED_OTP location', status: prod ? 'FAIL' : 'WARN',
      message: 'must be a Firebase secret, not a plain env value (firebase functions:secrets:set REVIEW_FIXED_OTP)' });
    if (!/^\d{6}$/.test(fixed)) r.push({ name: 'REVIEW_FIXED_OTP format', status: 'FAIL', message: 'must be exactly 6 digits' });
  }
  // Not in the file: it is a bound secret, checked in the Secret Manager section (the OTP
  // functions refuse to start without a 6-digit value).
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
  const checkSecretManager = args.includes('--check-secret-manager');
  if (!file || !fs.existsSync(file) || !['functions', 'gateway', 'all'].includes(target)) {
    console.error('usage: npm run check:boot-env -- <env-file> [--target=functions|gateway|all] [--app-env=staging|production] [--check-secret-manager]');
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
    if (appEnv === 'production' && !env.GCLOUD_PROJECT && !env.FIREBASE_CONFIG) env.GCLOUD_PROJECT = FIREBASE_PROJECT;
    // Cloud Run injects bound Secret Manager values at runtime; a file never has them. Stand in
    // a random value (never printed) so the boot asserts judge everything else, and verify the
    // real secrets separately (Secret Manager section: CHECK, or PASS/FAIL with the flag).
    const bound = collectBoundSecrets(fileEnv);
    for (const n of bound.names) {
      if (has(fileEnv, n) || NOT_SIMULATED.has(n)) continue;
      env[n] = n === 'REVIEW_FIXED_OTP' ? String(crypto.randomInt(100000, 1000000)) : crypto.randomBytes(48).toString('base64');
    }
    for (const x of runProbe(FUNCTIONS_DIR, FUNCTIONS_PROBE, env, 'functions', redact)) results.push({ scope: 'functions', ...x });
    for (const x of checklistFunctions(fileEnv, appEnv)) results.push({ scope: 'functions', ...x });
    if (!bound.fromManifest) {
      results.push({ scope: 'functions', name: 'bound secret list', status: 'WARN', message: 'could not load index.js manifests; using the static list' });
    }
    for (const x of secretManagerResults(bound, fileEnv, { verify: checkSecretManager })) results.push({ scope: 'functions', ...x });
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
  const checks = results.filter((r) => r.status === 'CHECK').length;
  console.log(`\n${fails} FAIL, ${warns} WARN, ${checks} CHECK, ${results.length - fails - warns - checks} PASS`);
  if (checks) console.log('CHECK = not verified (Secret Manager is invisible to a file). Re-run with --check-secret-manager before deploying.');
  // Unverified secrets are not a pass: exit non-zero until they are verified.
  process.exit(fails || checks ? 1 : 0);
}

if (require.main === module) main();

module.exports = { parseEnvFile, makeRedactor, collectBoundSecrets, secretManagerResults, secretManagerState };
