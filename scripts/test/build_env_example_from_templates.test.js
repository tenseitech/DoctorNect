'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const {
  placeholderForKey,
  auditOutputForRealSecrets,
  SECRET_VALUE_HEURISTIC,
} = require('../env/build_env_example_from_templates');

const FORBIDDEN_OUTPUT_PATTERNS = [
  { name: 'stripe_sk', re: /sk_(live|test)_/ },
  { name: 'aws_akia', re: /AKIA[0-9A-Z]{16}/ },
  { name: 'jwt_eyj', re: /eyJ[A-Za-z0-9_-]{20,}\.eyJ/ },
  { name: 'sb_secret', re: /sb_secret_/ },
  { name: 'long_random', re: /[A-Za-z0-9+/]{48,}={0,2}/ },
];

test('placeholderForKey never returns heuristic secrets', () => {
  const keys = [
    'STAGING_SUPABASE_SERVICE_ROLE_KEY',
    'PROD_GATEWAY_SERVICE_KEY',
    'AWS_SECRET_ACCESS_KEY',
    'PGRST_JWT_SECRET',
    'OTP_HMAC_SECRET',
  ];
  for (const key of keys) {
    const val = placeholderForKey(key);
    assert.ok(!SECRET_VALUE_HEURISTIC.test(val), `${key} placeholder looked like a secret`);
  }
});

test('auditOutputForRealSecrets flags realistic tokens only', () => {
  const bad = auditOutputForRealSecrets(['FOO=sk_live_abc123xyz']);
  assert.deepEqual(bad, ['FOO']);
  const ok = auditOutputForRealSecrets(['FOO=your_foo_here', 'BAR=']);
  assert.deepEqual(ok, []);
});

test('boolean and enum keys use safe defaults not your-* placeholders', () => {
  for (const key of [
    'REDIS_TLS',
    'ALLOW_LEGACY_UNSALTED_OTP_HASH',
    'REVIEWER_OTP_ENABLED',
    'OTP_TEST_MODE',
  ]) {
    const val = placeholderForKey(key);
    assert.ok(!/^your-/i.test(val), `${key} must not use your-* (got ${val})`);
  }
  assert.equal(placeholderForKey('REDIS_TLS'), 'true');
  assert.equal(placeholderForKey('ALLOW_LEGACY_UNSALTED_OTP_HASH'), 'false');
});

test('generated-style lines contain no forbidden patterns', () => {
  const sample = [
    'STAGING_SUPABASE_SERVICE_ROLE_KEY=',
    'PROD_RDS_HOST=example-db.xxxxxxxx.ap-south-1.rds.amazonaws.com',
    'OTP_HMAC_SECRET=',
    'AWS_ACCESS_KEY_ID=',
  ];
  for (const line of sample) {
    for (const pat of FORBIDDEN_OUTPUT_PATTERNS) {
      assert.ok(!pat.re.test(line), `unexpected ${pat.name} in ${line.split('=')[0]}`);
    }
  }
});