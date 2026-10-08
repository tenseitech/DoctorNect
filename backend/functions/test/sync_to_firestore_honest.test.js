'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('sync-to-firestore does not report success for a write it does not perform', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../../supabase/functions/sync-to-firestore/index.ts'),
    'utf8',
  );
  assert.match(src, /status:\s*501/);
  assert.match(src, /not_implemented/);
  assert.equal(src.includes('success: true'), false);
  assert.match(src, /DO NOT register a Database Webhook/);
});
