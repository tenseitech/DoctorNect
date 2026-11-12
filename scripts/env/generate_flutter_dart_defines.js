#!/usr/bin/env node
'use strict';

/**
 * Build client-safe dart-define JSON from repo root `.env` (never includes service-role / RDS / AWS secrets).
 * Output: frontend/build/dart_defines.local.json (gitignored) unless --stdout.
 */

const fs = require('fs');
const path = require('path');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');

const CLIENT_SAFE_KEYS = [
  'APP_ENV',
  'FIREBASE_API_KEY_ANDROID',
  'FIREBASE_API_KEY_IOS',
  'FIREBASE_API_KEY_WEB',
  'GOOGLE_MAPS_API_KEY',
  'RECAPTCHA_SITE_KEY',
  'SUPABASE_URL',
  'STAGING_SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'STAGING_SUPABASE_ANON_KEY',
  'PROD_GATEWAY_URL',
  'RAZORPAY_KEY_ID',
];

const FORBIDDEN_IN_CLIENT = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'STAGING_SUPABASE_SERVICE_ROLE_KEY',
  'PROD_GATEWAY_SERVICE_KEY',
  'PROD_RDS_PASSWORD',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_ACCESS_KEY_ID',
  'RAZORPAY_KEY_SECRET',
  'REDIS_PASSWORD',
  'MSG91_AUTH_KEY',
];

function main() {
  const stdout = process.argv.includes('--stdout');
  const root = loadRootEnv();
  const out = {};

  for (const key of FORBIDDEN_IN_CLIENT) {
    const v = getEnv(key);
    if (v && String(v).trim()) {
      console.error(`SECURITY: ${key} must not be used for Flutter client defines.`);
      process.exit(1);
    }
  }

  for (const key of CLIENT_SAFE_KEYS) {
    const v = getEnv(key);
    if (v && String(v).trim()) {
      out[key] = String(v).trim();
    }
  }

  const payload = JSON.stringify(out, null, 2);
  if (stdout) {
    process.stdout.write(`${payload}\n`);
    return;
  }

  const outPath = path.join(root, 'frontend', 'build', 'dart_defines.local.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${payload}\n`, 'utf8');
  console.log(`Wrote client dart-defines (${Object.keys(out).length} keys) -> frontend/build/dart_defines.local.json`);
}

main();
