'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('sync-to-firestore implements authenticated reverse sync bridge with loop prevention', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../../supabase/functions/sync-to-firestore/index.ts'),
    'utf8',
  );

  // 1. Authenticated webhook check: 401 on missing or invalid secret
  assert.match(src, /status:\s*401/);
  assert.match(src, /unauthorized/);

  // 2. Loop prevention for Firestore / Reconciler origins
  assert.match(src, /doctor_firestore/);
  assert.match(src, /patient_firestore/);
  assert.match(src, /firestore_cloud_function/);
  assert.match(src, /supabase_bridge/);

  // 3. Sets syncedBy: 'supabase_bridge' on Firestore write
  assert.match(src, /syncedBy:\s*["']supabase_bridge["']/);

  // 4. Returns non-2xx status on write failure so Supabase retries
  assert.match(src, /status:\s*500/);
  assert.match(src, /retriable:\s*true/);
});
