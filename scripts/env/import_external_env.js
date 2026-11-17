#!/usr/bin/env node
'use strict';

/**
 * Overlay non-empty keys from an external env file onto repo root `.env`.
 * Usage: node scripts/env/import_external_env.js --from=C:\path\to\env.example
 * Never prints secret values — only key names and counts.
 */

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');

function main() {
  const fromArg = process.argv.find((a) => a.startsWith('--from='));
  if (!fromArg) {
    console.error('Usage: node scripts/env/import_external_env.js --from=<absolute-path>');
    process.exit(1);
  }
  const fromPath = fromArg.slice('--from='.length);
  const root = findRepoRoot();
  const envPath = path.join(root, '.env');

  const ext = parseEnvFile(fromPath);
  const cur = parseEnvFile(envPath);
  const merged = { ...cur };

  for (const [k, v] of Object.entries(ext)) {
    if (v != null && String(v).trim() !== '') merged[k] = String(v).trim();
  }

  const db = merged.STAGING_SUPABASE_DB_URL || merged.SUPABASE_DB_URL || merged.DATABASE_URL;
  if (db) {
    merged.STAGING_SUPABASE_DB_URL = db;
    merged.SUPABASE_DB_URL = db;
    merged.DATABASE_URL = db;
  }
  if (merged.SUPABASE_URL) {
    merged.STAGING_SUPABASE_URL = merged.STAGING_SUPABASE_URL || merged.SUPABASE_URL;
  }
  if (merged.SUPABASE_ANON_KEY) {
    merged.STAGING_SUPABASE_ANON_KEY = merged.STAGING_SUPABASE_ANON_KEY || merged.SUPABASE_ANON_KEY;
  }
  const sr =
    merged.SUPABASE_SERVICE_ROLE_KEY ||
    merged.SUPABASE_SERVICE_KEY ||
    merged.STAGING_SUPABASE_SERVICE_ROLE_KEY;
  if (sr && !String(sr).includes('supabase.com/dashboard')) {
    merged.STAGING_SUPABASE_SERVICE_ROLE_KEY = sr;
    merged.SUPABASE_SERVICE_ROLE_KEY = sr;
  }
  if (merged.S3_BUCKET) {
    merged.S3_BUCKET_STAGING = merged.S3_BUCKET_STAGING || merged.S3_BUCKET;
  }
  if (merged.REDIS_HOST) {
    merged.REDIS_HOST_STAGING = merged.REDIS_HOST_STAGING || merged.REDIS_HOST;
  }
  merged.MSG91_AUTH_KEY = merged.MSG91_AUTH_KEY || merged.MSG91_AUTHKEY || cur.MSG91_AUTH_KEY;
  if (
    merged.FIREBASE_SERVICE_ACCOUNT_PATH &&
    merged.FIREBASE_SERVICE_ACCOUNT_PATH.includes('backend/scripts')
  ) {
    merged.FIREBASE_SERVICE_ACCOUNT_PATH = './scripts/service-account.json';
  }
  if (!merged.GOOGLE_APPLICATION_CREDENTIALS) {
    merged.GOOGLE_APPLICATION_CREDENTIALS = './scripts/service-account.json';
  }
  if (ext.RAZORPAY_WEBHOOK_SECRET) {
    merged.RAZORPAY_WEBHOOK_SECRET = ext.RAZORPAY_WEBHOOK_SECRET;
  }
  if (ext.RECAPTCHA_SITE_KEY) merged.RECAPTCHA_SITE_KEY = ext.RECAPTCHA_SITE_KEY;
  if (ext.APP_CHECK_DEBUG_TOKEN) merged.APP_CHECK_DEBUG_TOKEN = ext.APP_CHECK_DEBUG_TOKEN;
  if (ext.ENFORCE_OTP_APP_CHECK != null) merged.ENFORCE_OTP_APP_CHECK = String(ext.ENFORCE_OTP_APP_CHECK);

  let lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  const changed = [];
  lines = lines.map((line) => {
    const t = line.trim();
    if (!t || t.startsWith('#')) return line;
    const eq = t.indexOf('=');
    if (eq === -1) return line;
    const key = t.slice(0, eq).trim();
    if (!Object.prototype.hasOwnProperty.call(merged, key)) return line;
    const val = merged[key] ?? '';
    const old = cur[key] ?? '';
    if (String(val) !== String(old)) changed.push(key);
    const indent = (line.match(/^(\s*)/) || ['', ''])[1];
    const needsQuote = /[\s#]/.test(String(val)) && String(val) !== '';
    const out = needsQuote ? `"${String(val).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"` : String(val);
    return `${indent}${key}=${out}`;
  });
  fs.writeFileSync(envPath, lines.join('\n').endsWith('\n') ? lines.join('\n') : `${lines.join('\n')}\n`);

  console.log(`import_external_env: ${changed.length} key(s) updated in ${envPath}`);
  console.log(`Keys (names only): ${changed.sort().join(', ')}`);
}

main();
