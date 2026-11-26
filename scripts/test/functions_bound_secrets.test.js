'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { collectNarrowOtpBoundSecretKeys } = require('../lib/functions_bound_secrets');

test('narrow OTP deploy binds SUPABASE_SERVICE_ROLE_KEY + OTP data-plane secrets (no Redis) when OTP_REDIS_MIRROR off', () => {
  const root = findRepoRoot();
  const prev = process.env.OTP_REDIS_MIRROR;
  delete process.env.OTP_REDIS_MIRROR;
  try {
    const keys = collectNarrowOtpBoundSecretKeys(path.join(root, 'backend', 'functions'));
    assert.equal(keys.size, 5, `expected 5 bound keys, got ${[...keys].join(',')}`);
    assert.equal(keys.has('SUPABASE_SERVICE_ROLE_KEY'), true);
    assert.equal(keys.has('REVIEW_FIXED_OTP'), true);
    assert.equal(keys.has('DEMO_SUPABASE_SERVICE_ROLE_KEY'), true);
    assert.equal(keys.has('PROD_GATEWAY_SERVICE_KEY'), true);
    assert.equal(keys.has('OTP_HMAC_SECRET'), true);
    assert.equal(keys.has('REDIS_HOST'), false);
  } finally {
    if (prev === undefined) delete process.env.OTP_REDIS_MIRROR;
    else process.env.OTP_REDIS_MIRROR = prev;
  }
});