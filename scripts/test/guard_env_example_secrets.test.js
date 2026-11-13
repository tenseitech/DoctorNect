'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const {
  looksSecret,
  isPostgresUrlPlaceholder,
  REPLAY_DB_URL_PLACEHOLDER,
} = require('../env/guard_env_example_secrets');

test('REPLAY_DB_URL bracket placeholder in .env.example is not flagged', () => {
  const v = 'postgresql://[USER]:[PASSWORD]@127.0.0.1:[PORT]/[DB]';
  assert.ok(REPLAY_DB_URL_PLACEHOLDER.test(v));
  assert.ok(isPostgresUrlPlaceholder(v));
  assert.strictEqual(looksSecret('REPLAY_DB_URL', v), false);
});

test('realistic postgres URL with password still flagged', () => {
  const v = 'postgresql://postgres:postgres@127.0.0.1:5440/postgres';
  assert.strictEqual(isPostgresUrlPlaceholder(v), false);
  assert.strictEqual(looksSecret('REPLAY_DB_URL', v), true);
});

test('STAGING URL with bracket password placeholder allowed', () => {
  const v = 'postgresql://postgres.[PROJECT_REF]:[PASSWORD]@aws-0.example.pooler.supabase.com:5432/postgres';
  assert.ok(isPostgresUrlPlaceholder(v));
  assert.strictEqual(looksSecret('STAGING_SUPABASE_DB_URL', v), false);
});
