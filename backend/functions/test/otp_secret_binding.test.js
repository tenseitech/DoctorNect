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
