'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const frontendLib = path.join(root, '..', '..', 'frontend', 'lib');

function clientCallables() {
  const names = new Set();
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.dart')) {
        const src = fs.readFileSync(p, 'utf8');
        for (const m of src.matchAll(/httpsCallable\(\s*['"]([A-Za-z0-9_]+)['"]/g)) names.add(m[1]);
      }
    }
  };
  walk(frontendLib);
  return [...names].sort();
}

test('every Cloud Function the app calls is exported from index.js (deploy keeps it)', () => {
  const script = `
    const m = require('./index.js');
    process.stdout.write('@@' + JSON.stringify(Object.keys(m).filter((k) => m[k] && m[k].__endpoint)));
  `;
  const res = spawnSync(process.execPath, ['-e', script], {
    cwd: root,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, APP_ENV: 'test', NODE_ENV: 'test', GCLOUD_PROJECT: 'demo-test', FIREBASE_CONFIG: '{"projectId":"demo-test"}' },
    timeout: 120000,
  });
  const out = String(res.stdout || '');
  assert.ok(out.includes('@@'), `index.js failed to load: ${String(res.stderr).slice(0, 300)}`);
  const exported = new Set(JSON.parse(out.slice(out.indexOf('@@') + 2)));
  const used = clientCallables();
  assert.ok(used.length >= 20, 'expected to find the client callables');
  const missing = used.filter((n) => !exported.has(n));
  assert.deepEqual(missing, [], `called by the app but not deployed: ${missing.join(', ')}`);
});
