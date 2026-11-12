'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { isSyncFlagEnabled, isSupabaseSyncEnabled } = require('../sync_flags');

test('Postgres-only: Firestore sync bridge is not exported from index.js', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');

  assert.doesNotMatch(src, /exports\.\w+\s*=\s*onDocumentWritten/);
  assert.match(src, /processNotificationOutboxScheduled/);
  assert.doesNotMatch(src, /exports\.sync\w+ToSupabase\s*=/);
  assert.match(src, /exports\.supabaseDatabaseWebhook\s*=/);
  assert.match(src, /firestore_forbidden_guard/);

  assert.equal(isSyncFlagEnabled(undefined), false);
  assert.equal(isSyncFlagEnabled('1'), true);

  const originalEnv = process.env.ENABLE_SUPABASE_SYNC;
  try {
    delete process.env.ENABLE_SUPABASE_SYNC;
    assert.equal(isSupabaseSyncEnabled(), false);

    process.env.ENABLE_SUPABASE_SYNC = '1';
    assert.equal(isSupabaseSyncEnabled(), true);

    process.env.APP_ENV = 'production';
    assert.equal(isSupabaseSyncEnabled(), false, 'bridge must stay disabled in APP_ENV=production');
    delete process.env.APP_ENV;
  } finally {
    if (originalEnv !== undefined) {
      process.env.ENABLE_SUPABASE_SYNC = originalEnv;
    } else {
      delete process.env.ENABLE_SUPABASE_SYNC;
    }
  }
});
