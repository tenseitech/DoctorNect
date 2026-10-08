'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('ENABLE_SUPABASE_SYNC defaults off and sync exports are registered only inside that gate', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(
    src,
    /const ENABLE_SUPABASE_SYNC = String\(process\.env\.ENABLE_SUPABASE_SYNC \|\| ''\)\.trim\(\)\.toLowerCase\(\) === 'on'/,
  );

  const enabled = (value) => String(value || '').trim().toLowerCase() === 'on';
  assert.equal(enabled(undefined), false);
  assert.equal(enabled(''), false);
  assert.equal(enabled('off'), false);
  assert.equal(enabled('on'), true);

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
