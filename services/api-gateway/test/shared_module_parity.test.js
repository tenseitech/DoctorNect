'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'src');
const LIB = path.join(__dirname, '..', '..', '..', 'scripts', 'lib');
const body = (p) => fs.readFileSync(p, 'utf8').replace(/^\/\*\* Deploy bundle copy[^\n]*\n/, '').replace(/\r\n/g, '\n');

for (const name of ['demo_accounts', 'demo_routing', 'rds_demo_uid_guard']) {
  test(`src/shared/${name}.js matches scripts/lib/${name}.js`, () => {
    assert.equal(body(path.join(SRC, 'shared', `${name}.js`)), body(path.join(LIB, `${name}.js`)));
  });
}

test('gateway source only requires files inside the image (src/), except the guarded local .env loader', () => {
  const bad = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (!e.name.endsWith('.js')) continue;
      const src = fs.readFileSync(p, 'utf8');
      for (const m of src.matchAll(/require\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
        const target = path.resolve(path.dirname(p), m[1]);
        const ok = target.startsWith(SRC + path.sep) || m[1].endsWith('scripts/lib/bootstrap_root_env');
        if (!ok) bad.push(`${path.relative(SRC, p)} -> ${m[1]}`);
      }
    }
  };
  walk(SRC);
  assert.deepEqual(bad, []);
});
