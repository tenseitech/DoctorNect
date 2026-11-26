'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');

test('OTP_HMAC_SECRET is a Secret Manager binding on the OTP send/verify callables', () => {
  assert.match(read('otp_secrets.js'), /defineSecret\('OTP_HMAC_SECRET'\)/);
  const index = read('index.js');
  const block = index.match(/const OTP_DATA_PLANE_SECRETS = \[([\s\S]*?)\];/);
  assert.ok(block, 'OTP_DATA_PLANE_SECRETS present');
  assert.match(block[1], /\botpHmacSecret\b/);
  for (const fn of ['sendUserRegistrationOtp', 'verifyUserRegistrationOtp']) {
    const start = index.indexOf(`exports.${fn} = onCall(`);
    assert.ok(start > 0, fn);
    assert.match(index.slice(start, start + 800), /\.\.\.OTP_DATA_PLANE_SECRETS/, `${fn} binds OTP_DATA_PLANE_SECRETS`);
  }
});

test('DEMO_SUPABASE_URL is plain env (not a secret), so the materialized .env keeps it for the OTP functions', () => {
  const { collectDefineSecretNames } = require('../../../scripts/lib/functions_define_secrets');
  const names = collectDefineSecretNames(root);
  assert.equal(names.has('DEMO_SUPABASE_URL'), false);
  assert.equal(names.has('OTP_HMAC_SECRET'), true);
  assert.equal(names.has('DEMO_SUPABASE_SERVICE_ROLE_KEY'), true);
});

test('every deployed function binds the data-plane secrets the production cold start requires', () => {
  const { spawnSync } = require('child_process');
  const script = `
    const m = require('./index.js');
    const out = {};
    for (const [k, v] of Object.entries(m)) {
      if (v && v.__endpoint) out[k] = (v.__endpoint.secretEnvironmentVariables || []).map((x) => x.key);
    }
    process.stdout.write('@@' + JSON.stringify(out));
  `;
  const res = spawnSync(process.execPath, ['-e', script], {
    cwd: root,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, APP_ENV: 'test', NODE_ENV: 'test', GCLOUD_PROJECT: 'demo-test', FIREBASE_CONFIG: '{"projectId":"demo-test"}' },
    timeout: 120000,
  });
  const raw = String(res.stdout || '');
  assert.ok(raw.includes('@@'), `index.js failed to load: ${String(res.stderr).slice(0, 400)}`);
  const fns = JSON.parse(raw.slice(raw.indexOf('@@') + 2));
  assert.ok(Object.keys(fns).length >= 40, 'expected the full function set');
  for (const [name, keys] of Object.entries(fns)) {
    assert.ok(keys.includes('PROD_GATEWAY_SERVICE_KEY'), `${name} must bind PROD_GATEWAY_SERVICE_KEY`);
    assert.ok(keys.includes('DEMO_SUPABASE_SERVICE_ROLE_KEY'), `${name} must bind DEMO_SUPABASE_SERVICE_ROLE_KEY`);
    assert.equal(new Set(keys).size, keys.length, `${name} has duplicate secret bindings`);
  }
  for (const otp of ['sendUserRegistrationOtp', 'verifyUserRegistrationOtp']) {
    assert.ok(fns[otp].includes('OTP_HMAC_SECRET'), `${otp} must bind OTP_HMAC_SECRET`);
  }
});
