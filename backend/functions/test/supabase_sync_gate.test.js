'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { isSyncFlagEnabled, isSupabaseSyncEnabled } = require('../sync_flags');

test('ENABLE_SUPABASE_SYNC defaults off and sync exports are registered only inside that gate', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(
    src,
    /const ENABLE_SUPABASE_SYNC = isSupabaseSyncEnabled\(\)/,
  );

  // Requirement: unset, empty, '0', 'false', 'off', 'on' -> dormant; '1', 'true', 'TRUE' -> enabled
  assert.equal(isSyncFlagEnabled(undefined), false);
  assert.equal(isSyncFlagEnabled(null), false);
  assert.equal(isSyncFlagEnabled(''), false);
  assert.equal(isSyncFlagEnabled('0'), false);
  assert.equal(isSyncFlagEnabled('false'), false);
  assert.equal(isSyncFlagEnabled('off'), false);
  assert.equal(isSyncFlagEnabled('on'), false);

  assert.equal(isSyncFlagEnabled('1'), true);
  assert.equal(isSyncFlagEnabled('true'), true);
  assert.equal(isSyncFlagEnabled('TRUE'), true);
  assert.equal(isSyncFlagEnabled('  True  '), true);

  // Environment binding test
  const originalEnv = process.env.ENABLE_SUPABASE_SYNC;
  try {
    delete process.env.ENABLE_SUPABASE_SYNC;
    assert.equal(isSupabaseSyncEnabled(), false);

    process.env.ENABLE_SUPABASE_SYNC = '0';
    assert.equal(isSupabaseSyncEnabled(), false);

    process.env.ENABLE_SUPABASE_SYNC = 'off';
    assert.equal(isSupabaseSyncEnabled(), false);

    process.env.ENABLE_SUPABASE_SYNC = 'on';
    assert.equal(isSupabaseSyncEnabled(), false);

    process.env.ENABLE_SUPABASE_SYNC = '1';
    assert.equal(isSupabaseSyncEnabled(), true);

    process.env.ENABLE_SUPABASE_SYNC = 'true';
    assert.equal(isSupabaseSyncEnabled(), true);

    process.env.ENABLE_SUPABASE_SYNC = 'TRUE';
    assert.equal(isSupabaseSyncEnabled(), true);
  } finally {
    if (originalEnv !== undefined) {
      process.env.ENABLE_SUPABASE_SYNC = originalEnv;
    } else {
      delete process.env.ENABLE_SUPABASE_SYNC;
    }
  }

  let depth = 0;
  let gateDepth = null;
  const gated = [];
  const ungated = [];
  for (const line of src.split(/\r?\n/)) {
    if (gateDepth === null && line.includes('if (ENABLE_SUPABASE_SYNC)')) {
      gateDepth = depth;
    }
    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;
    const match = line.match(/exports\.(sync\w+ToSupabase)\s*=/);
    if (match) {
      if (gateDepth !== null && depth > gateDepth) gated.push(match[1]);
      else ungated.push(match[1]);
    }
    depth += opens - closes;
    if (gateDepth !== null && depth === gateDepth) gateDepth = null;
  }

  assert.equal(ungated.length, 0, `ungated sync exports: ${ungated.join(', ')}`);
  assert.ok(gated.length >= 16, `expected the sync exports to be gated, saw ${gated.length}`);
  assert.equal(new Set(gated).size, gated.length);
});
