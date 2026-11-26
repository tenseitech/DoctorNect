'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

// Firebase uploads only backend/functions. A require() that resolves outside it works locally
// but crashes index.js (every function) in production (PROJECT_ANALYSIS.md C2).
const ROOT = path.join(__dirname, '..');
// Guarded local-dev fallback after require('pg') fails: never reached in the deployed bundle.
const ALLOWED = new Set(['src/db/pg_pool.js|../../../scripts/node_modules/pg']);

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === 'test' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.js')) out.push(p);
  }
  return out;
}

test('no deployed module requires a file outside backend/functions', () => {
  const bad = [];
  for (const file of walk(ROOT, [])) {
    const rel = path.relative(ROOT, file).split(path.sep).join('/');
    if (rel.startsWith('scripts/')) continue;
    const src = fs.readFileSync(file, 'utf8');
    for (const m of src.matchAll(/require\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
      const target = path.resolve(path.dirname(file), m[1]);
      if (!target.startsWith(ROOT + path.sep) && !ALLOWED.has(`${rel}|${m[1]}`)) bad.push(`${rel} -> ${m[1]}`);
    }
  }
  assert.deepEqual(bad, []);
});
