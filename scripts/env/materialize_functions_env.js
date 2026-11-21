'use strict';

/**
 * Firebase deploy: copy Cloud Functions runtime keys from root .env → backend/functions/.env
 * Postdeploy: scripts/env/cleanup_functions_env.js removes it.
 */

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const {
  filterBaselineRuntimeEnv,
  assertFunctionsEnvFilePassesFirebaseValidation,
} = require('../lib/firebase_tools_reserved_env');
const {
  filterSecretBoundEnv,
  assertNoSecretBoundEnvKeys,
  collectDefineSecretNames,
} = require('../lib/functions_define_secrets');

const FUNCTIONS_KEYS = new Set([
  'APP_ENV',
  'OTP_TEST_MODE',
  'ENFORCE_OTP_APP_CHECK',
  'ENFORCE_ABUSE_APP_CHECK',
  'ENFORCE_AMBULANCE_HTTP_APP_CHECK',
  'AMBULANCE_HTTP_ALLOWED_ORIGINS',
  'DEMO_PHONE_PATIENT',
  'DEMO_PHONE_DOCTOR',
  'DEMO_PHONE_MEDICAL_STORE',
  'DEMO_PHONE_LAB',
  'DEMO_PHONE_AMBULANCE',
  'DEMO_PHONE_SUPER_ADMIN',
  'REVIEWER_OTP_ENABLED',
  'REVIEW_ACCESS_UNTIL',
  'REVIEW_FIXED_OTP',
  'REVIEW_PATIENT_PHONES',
  'REVIEW_DOCTOR_PHONES',
  'REVIEW_LAB_PHONES',
  'REVIEW_MEDICAL_STORE_PHONES',
  'REVIEW_MEDICALSTORE_PHONES',
  'REVIEW_AMBULANCE_PHONES',
  'MSG91_AUTH_KEY',
  'MSG91_TEMPLATE_ID',
  'MSG91_TEMPLATE_ID_REGISTRATION',
  'MSG91_TEMPLATE_ID_LOGIN',
  'MSG91_TEMPLATE_ID_PASSWORD_RESET',
  'MSG91_SENDER_ID',
  'MSG91_FROM_EMAIL',
  'MSG91_EMAIL_DOMAIN',
  'MSG91_PROXY_URL',
  'PROXY_SECRET',
  'MSG91_TEMPLATE_ID_APPROVAL',
  'MSG91_TEMPLATE_ID_REJECTION',
  'VPC_CONNECTOR',
  'ALLOW_LEGACY_UNSALTED_OTP_HASH',
  'ACCOUNT_APPROVAL_ADMIN_EMAILS',
  'PATIENT_APPROVAL_ADMIN_EMAILS',
  'BACKFILL_ADMIN_EMAILS',
  'RAZORPAY_KEY_ID',
  'RAZORPAY_KEY_SECRET',
  'RAZORPAY_WEBHOOK_SECRET',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_REGION',
  'S3_BUCKET',
  'S3_URL_CACHE',
  'USE_S3_STORAGE',
  'S3_BUCKET_STAGING',
  'S3_BUCKET_PRODUCTION',
  'FIRESTORE_TRIGGER_REGION',
  'FIRESTORE_FORBIDDEN',
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_PASSWORD',
  'REDIS_TLS',
  'REDIS_CA_CERT',
  'REDIS_CA_PATH',
  'REDIS_HOST_STAGING',
  'REDIS_HOST_PRODUCTION',
  'OTP_REDIS_MIRROR',
  'RATE_LIMIT_BACKEND',
  'STAGING_SUPABASE_URL',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'PROD_GATEWAY_URL',
  'PROD_GATEWAY_SERVICE_KEY',
  'PROD_GATEWAY_ANON_KEY',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_DB_URL',
  'DATABASE_URL',
  'SUPABASE_WEBHOOK_SECRET',
  'ENABLE_SUPABASE_SYNC',
  'FORCE_ENABLE_SUPABASE_SYNC_IN_PROD',
  'ENABLE_REVIEW_DEMO',
  'NOTIFICATION_DISPATCH_MODE',
  'ADMIN_CONSOLE_CORS_ORIGINS_STAGING',
  'ADMIN_CONSOLE_CORS_ORIGINS_PRODUCTION',
  'ADMIN_CONSOLE_CORS_ORIGINS',
  'SKIP_APP_ENV_DB_ASSERT',
]);

const REVIEWER_OVERLAY_KEYS = new Set([
  'REVIEWER_OTP_ENABLED',
  'REVIEW_ACCESS_UNTIL',
  'REVIEW_FIXED_OTP',
  'REVIEW_PATIENT_PHONES',
  'REVIEW_DOCTOR_PHONES',
  'REVIEW_LAB_PHONES',
  'REVIEW_MEDICAL_STORE_PHONES',
  'REVIEW_MEDICALSTORE_PHONES',
  'REVIEW_AMBULANCE_PHONES',
]);

function materializeNarrowOtpDeploy(root, parsed, lines) {
  const baselinePath =
    process.env.DEPLOYED_ENV_BASELINE ||
    path.join(root, '.artifacts', 'baselines', 'sendUserRegistrationOtp.deployed.json');
  if (!fs.existsSync(baselinePath)) {
    throw new Error(`NARROW_OTP_DEPLOY: missing deployed baseline at ${baselinePath}`);
  }
  const raw = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
  let base = filterBaselineRuntimeEnv(raw.serviceConfig?.environmentVariables || raw);
  base = filterSecretBoundEnv(base);
  for (const key of REVIEWER_OVERLAY_KEYS) {
    const val = process.env[key] ?? parsed[key] ?? '';
    if (val !== '') {
      base[key] = val;
    }
  }
  const secretNames = collectDefineSecretNames(path.join(root, 'backend', 'functions'));
  for (const key of Object.keys(base).sort()) {
    if (secretNames.has(key)) continue;
    const val = base[key];
    if (val === undefined || val === null || String(val) === '') continue;
    lines.push(`${key}=${String(val)}`);
  }
  lines.splice(2, 0, '# NARROW_OTP_DEPLOY=1 — baseline + reviewer overlay only');
}

function assertGeneratedEnvPolicy(envPath) {
  assertFunctionsEnvFilePassesFirebaseValidation(envPath);
  const body = fs.readFileSync(envPath, 'utf8');
  const parsed = {};
  for (const line of body.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    parsed[t.slice(0, eq)] = t.slice(eq + 1);
  }
  assertNoSecretBoundEnvKeys(parsed);
}

function tryFunctionsIndexBootSmoke(functionsDir, { timeoutMs = 25000 } = {}) {
  const { spawnSync } = require('child_process');
  const envFile = path.join(functionsDir, '.env').replace(/\\/g, '/');
  const script = `
    const fs = require('fs');
    const envPath = '${envFile}';
    if (fs.existsSync(envPath)) {
      for (const line of fs.readFileSync(envPath, 'utf8').split(/\\r?\\n/)) {
        const t = line.trim();
        if (!t || t.startsWith('#')) continue;
        const eq = t.indexOf('=');
        if (eq <= 0) continue;
        const k = t.slice(0, eq);
        let v = t.slice(eq + 1);
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.slice(1, -1);
        }
        if (process.env[k] === undefined) process.env[k] = v;
      }
    }
    process.env.K_SERVICE = 'senduserregistrationotp';
    process.env.FUNCTION_TARGET = 'sendUserRegistrationOtp';
    process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'medibond-45fad';
    const t0 = Date.now();
    require('./index.js');
    console.log('FUNCTIONS_INDEX_LOAD_MS=' + (Date.now() - t0));
  `;
  const res = spawnSync(process.execPath, ['-e', script], {
    cwd: functionsDir,
    encoding: 'utf8',
    timeout: timeoutMs,
    env: { ...process.env, NODE_ENV: 'production' },
  });
  if (res.status !== 0) {
    const err = (res.stderr || res.stdout || '').trim().split('\n').slice(-8).join('\n');
    throw new Error(`functions index.js load failed:\n${err}`);
  }
  const msLine = (res.stdout || '').split('\n').find((l) => l.startsWith('FUNCTIONS_INDEX_LOAD_MS='));
  return msLine ? Number(msLine.split('=')[1]) : null;
}

function main() {
  const root = findRepoRoot(path.join(__dirname, '../..'));
  loadRootEnv({ startDir: root, force: true });
  const parsed = parseEnvFile(path.join(root, '.env'));
  const lines = [
    '# Generated by scripts/env/materialize_functions_env.js — do not commit',
    `# Source: ${path.join(root, '.env')}`,
    '',
  ];
  const narrowOtp = String(process.env.NARROW_OTP_DEPLOY || '').trim() === '1';
  if (narrowOtp) {
    materializeNarrowOtpDeploy(root, parsed, lines);
  } else {
    const secretNames = collectDefineSecretNames(path.join(root, 'backend', 'functions'));
    for (const key of [...FUNCTIONS_KEYS].sort()) {
      if (secretNames.has(key)) continue;
      const val = process.env[key] ?? parsed[key] ?? '';
      if (val === '') continue;
      lines.push(`${key}=${val}`);
    }
  }
  const out = path.join(root, 'backend', 'functions', '.env');
  fs.writeFileSync(out, `${lines.join('\n')}\n`);
  assertGeneratedEnvPolicy(out);
  console.log('Materialize policy OK: no reserved keys, no defineSecret overlaps in .env.');
  if (String(process.env.MATERIALIZE_SKIP_INDEX_SMOKE || '').trim() !== '1') {
    const loadMs = tryFunctionsIndexBootSmoke(path.join(root, 'backend', 'functions'));
    console.log(`functions index.js load smoke OK (${loadMs != null ? `${loadMs}ms` : 'timing n/a'}).`);
  }
  console.log(`Materialized ${path.relative(root, out)} (${lines.length - 3} keys, values not logged).`);
}

main();
