'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { collectBoundSecrets, secretManagerResults, secretManagerState } = require('../env/check_boot_env');

const SCRIPT = path.join(__dirname, '../env/check_boot_env.js');

test('bound secrets come from the real function manifests', () => {
  const bound = collectBoundSecrets({});
  assert.equal(bound.fromManifest, true);
  for (const n of ['PROD_GATEWAY_SERVICE_KEY', 'DEMO_SUPABASE_SERVICE_ROLE_KEY', 'OTP_HMAC_SECRET', 'REVIEW_FIXED_OTP']) {
    assert.ok(bound.names.includes(n), n);
  }
  assert.equal(bound.names.includes('DEMO_SUPABASE_URL'), false, 'DEMO_SUPABASE_URL is plain env');
});

test('without --check-secret-manager the secrets are a CHECK (not a pass), listing every bound name', () => {
  const r = secretManagerResults({ names: ['A_SECRET', 'B_SECRET'] }, { A_SECRET: 'in-file' }, { verify: false });
  assert.equal(r.length, 1);
  assert.equal(r[0].status, 'CHECK');
  assert.match(r[0].message, /A_SECRET, B_SECRET/);
  assert.match(r[0].message, /--check-secret-manager/);
});

test('secretManagerState refuses names that could inject shell syntax', () => {
  assert.deepEqual(secretManagerState('X; rm -rf /'), { ok: false, why: 'invalid name' });
  assert.deepEqual(secretManagerState('OK_NAME', 'proj && whoami'), { ok: false, why: 'invalid name' });
});

test('an unverified run exits non-zero and never prints file values', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bootenv-'));
  const file = path.join(dir, 'prod.env');
  const marker = 'zz-unique-secret-value-0123456789';
  fs.writeFileSync(file, [
    'APP_ENV=production', 'FIRESTORE_FORBIDDEN=1', 'PROD_GATEWAY_URL=https://api.example.org',
    `MSG91_AUTH_KEY=${marker}`, 'RAZORPAY_KEY_ID=rzp_live_x', `RAZORPAY_KEY_SECRET=${marker}2`,
    'S3_BUCKET_STAGING=stage-bucket', 'S3_BUCKET_PRODUCTION=stage-bucket',
  ].join('\n'));
  try {
    const r = spawnSync(process.execPath, [SCRIPT, file, '--target=functions'], { encoding: 'utf8', timeout: 180000 });
    const out = `${r.stdout}${r.stderr}`;
    assert.equal(r.status, 1);
    assert.match(out, /CHECK +\[functions\] Secret Manager secrets/);
    assert.match(out, /Production must not use the staging S3 bucket: S3_BUCKET_PRODUCTION/);
    assert.ok(!out.includes(marker), 'secret value leaked');
    // Bound secrets are stood in for, so routing is judged on PROD_GATEWAY_URL alone.
    assert.match(out, /PASS +\[functions\] database routing/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('routing still FAILS without PROD_GATEWAY_URL (stand-in secrets do not weaken it)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bootenv-'));
  const file = path.join(dir, 'prod.env');
  fs.writeFileSync(file, ['APP_ENV=production', 'FIRESTORE_FORBIDDEN=1', 'S3_BUCKET_PRODUCTION=prod-bucket'].join('\n'));
  try {
    const r = spawnSync(process.execPath, [SCRIPT, file, '--target=functions'], { encoding: 'utf8', timeout: 180000 });
    assert.equal(r.status, 1);
    assert.match(r.stdout, /FAIL +\[functions\] database routing[\s\S]*requires PROD_GATEWAY_URL/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
