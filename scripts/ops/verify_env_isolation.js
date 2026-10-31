#!/usr/bin/env node
'use strict';

/**
 * FAIL when APP_ENV=production but config still references known staging identifiers.
 * Does not print secret values — only key names and pattern matches.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

const STAGING_MARKERS = [
  { label: 'Supabase staging project ref', pattern: /irpkyedfmdsuvapfnrim/i },
  { label: 'Firebase staging project id', pattern: /medibond-staging/i },
  { label: 'Razorpay test key', pattern: /rzp_test_/i },
  { label: 'Placeholder Supabase URL', pattern: /your-project-ref\.supabase\.co/i },
];

function loadEnvFiles() {
  const chunks = [];
  for (const rel of ['.env', 'frontend/.env', 'backend/functions/.env']) {
    const p = path.join(ROOT, rel);
    if (!fs.existsSync(p)) continue;
    chunks.push(fs.readFileSync(p, 'utf8'));
  }
  return chunks.join('\n');
}

function main() {
  const appEnv = String(process.env.APP_ENV || '').trim().toLowerCase();
  if (appEnv !== 'production') {
    console.log('PASS (skipped): APP_ENV is not production');
    process.exit(0);
  }

  const haystack = [
    loadEnvFiles(),
    process.env.SUPABASE_URL || '',
    process.env.PROD_GATEWAY_URL || '',
    process.env.FIREBASE_PROJECT_ID || '',
    process.env.AWS_S3_BUCKET || '',
    process.env.REDIS_HOST || '',
  ].join('\n');

  const hits = [];
  for (const marker of STAGING_MARKERS) {
    if (marker.pattern.test(haystack)) {
      hits.push(marker.label);
    }
  }

  if (hits.length) {
    console.error('FAIL: production APP_ENV with staging markers detected:');
    for (const h of hits) console.error(`  - ${h}`);
    process.exit(1);
  }

  console.log('PASS: no known staging markers in production config snapshot');
  process.exit(0);
}

main();
