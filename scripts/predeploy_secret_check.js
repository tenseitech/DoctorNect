#!/usr/bin/env node
/**
 * scripts/predeploy_secret_check.js
 *
 * Pre-deployment validator that prevents deploying Cloud Functions with:
 * 1. Missing or empty required secrets / environment variables.
 * 2. Secret environment variable overlaps (variables defined both in .env and bound via secrets: [...] in code).
 * 3. SUPABASE_SERVICE_ROLE_KEY leaking into .env (must strictly be in Secret Manager).
 *
 * STRICT SECURITY INVARIANT:
 * NEVER print, log, or copy real secret values.
 * Output status strictly as PRESENT, EMPTY, or MISSING.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const FUNCTIONS_DIR = path.resolve(ROOT_DIR, 'backend/functions');
const ENV_PATH = path.resolve(FUNCTIONS_DIR, '.env');

/** Paths that must never appear in the Cloud Functions upload bundle (see firebase.json ignore). */
function isForbiddenUploadRelativePath(relPosix) {
  const p = relPosix.replace(/\\/g, '/');
  if (p.endsWith('.env.example') || p.endsWith('.secret.local.example')) {
    return false;
  }
  if (p.includes('/node_modules/') || p.startsWith('node_modules/')) {
    return false;
  }
  if (p.includes('.env') && !p.endsWith('.env.example')) {
    return true;
  }
  if (p.includes('.bak')) {
    return true;
  }
  if (p.includes('.secret') && !p.endsWith('.secret.local.example')) {
    return true;
  }
  if (p.includes('service-account')) {
    return true;
  }
  return false;
}

function listFunctionsSourceFiles(dir, base = '') {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const name of fs.readdirSync(dir, { withFileTypes: true })) {
    if (name.name === 'node_modules' || name.name === '.git') continue;
    const rel = base ? `${base}/${name.name}` : name.name;
    const full = path.join(dir, name.name);
    if (name.isDirectory()) {
      out.push(...listFunctionsSourceFiles(full, rel));
    } else {
      out.push(rel.replace(/\\/g, '/'));
    }
  }
  return out;
}
const STAGING_REF = 'irpkyedfmdsuvapfnrim';
const PROD_REF = 'rnltknemwnjrjxthtull';

function parseDotEnv(content) {
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    let val = trimmed.slice(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
  return env;
}

function getVarStatus(env, key) {
  if (!(key in env)) return 'MISSING';
  const val = String(env[key] || '').trim();
  return val.length > 0 ? 'PRESENT' : 'EMPTY';
}

/**
 * Returns the list of secrets that are actively bound to exported functions in code.
 * Sourced from analysis of backend/functions/index.js, s3_storage.js, promoted_ads.js, delete_my_account.js.
 */
function getActiveBoundSecrets(env) {
  const bound = new Map(); // secretName -> Array of function names

  // 1. deleteMyAccount: binds awsAccessKeyId, awsSecretAccessKey, supabaseServiceRoleKey
  bound.set('SUPABASE_SERVICE_ROLE_KEY', ['deleteMyAccount', 'getS3UploadUrl', 'getS3DownloadUrl', 'getS3DownloadUrls', 'deleteS3Object', 'confirmS3Upload']);
  bound.set('AWS_ACCESS_KEY_ID', ['deleteMyAccount', 'getS3UploadUrl', 'getS3DownloadUrl', 'getS3DownloadUrls', 'deleteS3Object']);
  bound.set('AWS_SECRET_ACCESS_KEY', ['deleteMyAccount', 'getS3UploadUrl', 'getS3DownloadUrl', 'getS3DownloadUrls', 'deleteS3Object']);

  // 2. razorpayWebhook: binds razorpayWebhookSecret if deployed
  bound.set('RAZORPAY_WEBHOOK_SECRET', ['razorpayWebhook']);

  // 3. Redis secrets: only bound if OTP_REDIS_MIRROR is 'on'
  const otpRedisMirrorOn = String(env.OTP_REDIS_MIRROR || '').trim().toLowerCase() === 'on';
  if (otpRedisMirrorOn) {
    bound.set('REDIS_HOST', ['completeMobileOtpLogin', 'completeAmbulanceMobileOtpLogin']);
    bound.set('REDIS_PORT', ['completeMobileOtpLogin', 'completeAmbulanceMobileOtpLogin']);
    bound.set('REDIS_PASSWORD', ['completeMobileOtpLogin', 'completeAmbulanceMobileOtpLogin']);
  }

  // 4. Supabase sync secrets: only bound if ENABLE_SUPABASE_SYNC is enabled
  const supabaseSyncOn = String(env.ENABLE_SUPABASE_SYNC || '').trim() === '1' || String(env.ENABLE_SUPABASE_SYNC || '').trim().toLowerCase() === 'true';
  if (supabaseSyncOn) {
    bound.set('SUPABASE_SERVICE_ROLE_KEY', [...(bound.get('SUPABASE_SERVICE_ROLE_KEY') || []), 'sync*ToSupabase']);
  }

  return bound;
}

function runCheck(options = {}) {
  const targetBatch = options.batch || 'all';

  console.log('================================================================');
  console.log('DOCTORNECT: PRE-DEPLOY SECRETS & ENVIRONMENT GUARD');
  console.log(`Target: Batch [${targetBatch}]`);
  console.log('STRICT POLICY: Zero secret values are ever displayed');
  console.log('================================================================');

  if (!fs.existsSync(ENV_PATH)) {
    console.error(`❌ FATAL: Env file not found at ${ENV_PATH}`);
    process.exit(1);
  }

  const envContent = fs.readFileSync(ENV_PATH, 'utf8');
  const env = parseDotEnv(envContent);
  const errors = [];
  const warnings = [];

  // ---------------------------------------------------------------------------
  // Check 0: Secret Overlap Protection (defineSecret vs .env)
  // Google Cloud Functions v2 aborts deployment if any variable is defined
  // both in .env (plain environmentVariables) and as a Secret Manager secret
  // (secretEnvironmentVariables).
  // ---------------------------------------------------------------------------
  console.log('\n--- 0. Secret vs Plain Env Overlap Verification ---');
  const activeSecrets = getActiveBoundSecrets(env);

  for (const [secName, fns] of activeSecrets.entries()) {
    if (secName in env && String(env[secName] || '').trim().length > 0) {
      // Overlap detected: variable is defined in .env AND mounted as secret
      errors.push(
        `Secret environment variable overlaps non-secret environment variable: '${secName}'. ` +
        `Bound as Secret Manager secret on [${fns.join(', ')}] in code, but ALSO defined non-empty in backend/functions/.env. ` +
        `Cloud Functions deploy will abort with an overlap error. Remove '${secName}' from backend/functions/.env to source strictly from Secret Manager.`
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Check 1: Supabase Configuration
  // ---------------------------------------------------------------------------
  console.log('\n--- 1. Supabase PostgreSQL Configuration ---');
  const supabaseUrlStatus = getVarStatus(env, 'SUPABASE_URL');
  console.log(`  SUPABASE_URL: ${supabaseUrlStatus}`);
  if (supabaseUrlStatus !== 'PRESENT') {
    errors.push('SUPABASE_URL is missing or empty in .env.');
  } else if (env.SUPABASE_URL.includes(STAGING_REF)) {
    errors.push(`SUPABASE_URL contains stale staging reference '${STAGING_REF}'. Must point to '${PROD_REF}'.`);
  } else if (!env.SUPABASE_URL.includes(PROD_REF)) {
    warnings.push(`SUPABASE_URL does not contain expected production project ref '${PROD_REF}'.`);
  }

  const anonKeyStatus = getVarStatus(env, 'SUPABASE_ANON_KEY');
  console.log(`  SUPABASE_ANON_KEY: ${anonKeyStatus}`);
  if (anonKeyStatus !== 'PRESENT') errors.push('SUPABASE_ANON_KEY is missing or empty in .env.');

  // SUPABASE_SERVICE_ROLE_KEY: Must strictly be in Secret Manager, NOT in .env
  const serviceRoleInEnv = getVarStatus(env, 'SUPABASE_SERVICE_ROLE_KEY');
  if (serviceRoleInEnv === 'PRESENT') {
    errors.push(
      'SUPABASE_SERVICE_ROLE_KEY is present in backend/functions/.env! ' +
      'It must NOT be in .env (to prevent baking the master secret into plain Cloud Run env vars). ' +
      'It must strictly be provided via Secret Manager.'
    );
  } else {
    // Verify it is bound in code on deleteMyAccount
    const isBound = activeSecrets.has('SUPABASE_SERVICE_ROLE_KEY');
    if (isBound) {
      console.log('  SUPABASE_SERVICE_ROLE_KEY: PRESENT in Secret Manager (code-bound; absent from .env as required)');
    } else {
      errors.push('SUPABASE_SERVICE_ROLE_KEY is not declared via defineSecret() in backend/functions code.');
    }
  }

  // ---------------------------------------------------------------------------
  // Check 2: SMS Gateway (MSG91)
  // ---------------------------------------------------------------------------
  console.log('\n--- 2. SMS Gateway (MSG91) ---');
  const msg91KeyStatus = getVarStatus(env, 'MSG91_AUTH_KEY');
  console.log(`  MSG91_AUTH_KEY: ${msg91KeyStatus}`);
  if (msg91KeyStatus !== 'PRESENT') errors.push('MSG91_AUTH_KEY is missing or empty in .env.');

  const msg91SenderStatus = getVarStatus(env, 'MSG91_SENDER_ID');
  console.log(`  MSG91_SENDER_ID: ${msg91SenderStatus}`);
  if (msg91SenderStatus !== 'PRESENT') errors.push('MSG91_SENDER_ID is missing or empty in .env.');

  const msg91RegTplStatus = getVarStatus(env, 'MSG91_TEMPLATE_ID_REGISTRATION');
  console.log(`  MSG91_TEMPLATE_ID_REGISTRATION: ${msg91RegTplStatus}`);
  if (msg91RegTplStatus !== 'PRESENT') errors.push('MSG91_TEMPLATE_ID_REGISTRATION is missing or empty in .env.');

  const msg91LoginTplStatus = getVarStatus(env, 'MSG91_TEMPLATE_ID_LOGIN');
  console.log(`  MSG91_TEMPLATE_ID_LOGIN: ${msg91LoginTplStatus}`);
  if (msg91LoginTplStatus !== 'PRESENT') errors.push('MSG91_TEMPLATE_ID_LOGIN is missing or empty in .env.');

  // ---------------------------------------------------------------------------
  // Check 3: Redis Cache & Throttling
  // ---------------------------------------------------------------------------
  console.log('\n--- 3. Redis / Memorystore ---');
  const redisHostStatus = getVarStatus(env, 'REDIS_HOST');
  console.log(`  REDIS_HOST: ${redisHostStatus}`);
  if (redisHostStatus !== 'PRESENT') errors.push('REDIS_HOST is missing or empty in .env.');

  const redisPortStatus = getVarStatus(env, 'REDIS_PORT');
  console.log(`  REDIS_PORT: ${redisPortStatus}`);
  if (redisPortStatus !== 'PRESENT') errors.push('REDIS_PORT is missing or empty in .env.');

  const redisPasswordStatus = getVarStatus(env, 'REDIS_PASSWORD');
  console.log(`  REDIS_PASSWORD: ${redisPasswordStatus}`);
  if (redisPasswordStatus !== 'PRESENT') errors.push('REDIS_PASSWORD is missing or empty in .env.');

  // ---------------------------------------------------------------------------
  // Check 4: Payments (Razorpay)
  // ---------------------------------------------------------------------------
  console.log('\n--- 4. Payments (Razorpay) ---');
  const rzpIdStatus = getVarStatus(env, 'RAZORPAY_KEY_ID');
  console.log(`  RAZORPAY_KEY_ID: ${rzpIdStatus}`);
  if (rzpIdStatus !== 'PRESENT') errors.push('RAZORPAY_KEY_ID is missing or empty in .env.');

  const rzpSecretStatus = getVarStatus(env, 'RAZORPAY_KEY_SECRET');
  console.log(`  RAZORPAY_KEY_SECRET: ${rzpSecretStatus}`);
  if (rzpSecretStatus !== 'PRESENT') errors.push('RAZORPAY_KEY_SECRET is missing or empty in .env.');

  const rzpWebhookInSecretManager = activeSecrets.has('RAZORPAY_WEBHOOK_SECRET');
  if (rzpWebhookInSecretManager) {
    console.log('  RAZORPAY_WEBHOOK_SECRET: PRESENT in Secret Manager (code-bound; absent from .env as required)');
  } else {
    const rzpWebhookStatus = getVarStatus(env, 'RAZORPAY_WEBHOOK_SECRET');
    console.log(`  RAZORPAY_WEBHOOK_SECRET: ${rzpWebhookStatus} (in .env)`);
    if ((targetBatch === 'all' || targetBatch === 'webhook') && rzpWebhookStatus !== 'PRESENT') {
      errors.push('RAZORPAY_WEBHOOK_SECRET is EMPTY or MISSING. Set in Secret Manager (defineSecret) or in .env.');
    }
  }

  // ---------------------------------------------------------------------------
  // Check 5: AWS S3 Storage
  // ---------------------------------------------------------------------------
  console.log('\n--- 5. AWS S3 Storage ---');
  const s3BucketStatus = getVarStatus(env, 'S3_BUCKET');
  console.log(`  S3_BUCKET: ${s3BucketStatus}`);
  if (s3BucketStatus !== 'PRESENT') errors.push('S3_BUCKET is missing or empty in .env.');

  const awsInSecretManager = activeSecrets.has('AWS_ACCESS_KEY_ID') && activeSecrets.has('AWS_SECRET_ACCESS_KEY');
  if (awsInSecretManager) {
    console.log('  AWS Credentials: Bound via Secret Manager in code (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)');
  }

  // ---------------------------------------------------------------------------
  // Check 6: Forbidden files in functions upload tree
  // ---------------------------------------------------------------------------
  console.log('\n--- 6. Functions Upload Bundle Forbidden Files ---');
  const uploadFiles = listFunctionsSourceFiles(FUNCTIONS_DIR);
  const forbiddenInTree = uploadFiles.filter(isForbiddenUploadRelativePath);
  if (forbiddenInTree.length > 0) {
    forbiddenInTree.forEach((rel) => {
      errors.push(
        `Forbidden file would be uploaded with Cloud Functions source: backend/functions/${rel}. ` +
          'Remove or relocate it (see firebase.json functions.ignore).',
      );
    });
    console.log(`  Found ${forbiddenInTree.length} forbidden path(s) (names only in error list above).`);
  } else {
    console.log('  No forbidden backup/env/secret paths under backend/functions/.');
  }

  // ---------------------------------------------------------------------------
  // Validation Summary & Exit Code
  // ---------------------------------------------------------------------------
  console.log('\n================================================================');
  console.log('VALIDATION RESULT');
  console.log('================================================================');

  if (warnings.length > 0) {
    console.log('⚠️  WARNINGS:');
    warnings.forEach((w) => console.log(`   - ${w}`));
  }

  if (errors.length > 0) {
    console.error('❌ FATAL PRE-DEPLOY VALIDATION ERRORS:');
    errors.forEach((e) => console.error(`   - ${e}`));
    console.error('\nABORTING: Fix the configuration issues above before running firebase deploy.\n');
    process.exit(1);
  }

  console.log('✅ ALL PRE-DEPLOY CHECKS PASSED: Environment configuration is valid for deployment.');
  process.exit(0);
}

const args = process.argv.slice(2);
let batch = 'all';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--batch' && args[i + 1]) {
    batch = args[i + 1];
    i++;
  } else if (args[i].startsWith('--batch=')) {
    batch = args[i].slice(8);
  } else if (args[i] === '--core-only') {
    batch = 'core';
  }
}

runCheck({ batch });
