'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { collectNarrowOtpBoundSecretKeys } = require('../lib/functions_bound_secrets');

test('narrow OTP deploy binds only SUPABASE_SERVICE_ROLE_KEY when OTP_REDIS_MIRROR off', () => {
  const root = findRepoRoot();
  const prev = process.env.OTP_REDIS_MIRROR;
  delete process.env.OTP_REDIS_MIRROR;
  try {
    const keys = collectNarrowOtpBoundSecretKeys(path.join(root, 'backend', 'functions'));
    assert.equal(keys.size, 1);
    assert.ok(keys.has('SUPABASE_SERVICE_ROLE_KEY'));
    assert.equal(keys.has('REDIS_HOST'), false);
  } finally {
    if (prev === undefined) delete process.env.OTP_REDIS_MIRROR;
    else process.env.OTP_REDIS_MIRROR = prev;
  }
});