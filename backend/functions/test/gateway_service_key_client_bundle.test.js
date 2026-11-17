'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '../../..');
const clientLib = path.join(repoRoot, 'frontend', 'lib');
const forbidden = 'PROD_GATEWAY_SERVICE_KEY';

function grepDir(dir) {
  const hits = [];
  if (!fs.existsSync(dir)) return hits;
  const walk = (d) => {
    for (const name of fs.readdirSync(d)) {
      const full = path.join(d, name);
      const stat = fs.statSync(full);
      if (stat.isDirectory()) {
        walk(full);
        continue;
      }
      if (!/\.dart$/i.test(name)) continue;
      const text = fs.readFileSync(full, 'utf8');
      if (text.includes(forbidden)) hits.push(path.relative(repoRoot, full));
    }
  };
  walk(dir);
  return hits;
}

test('PROD_GATEWAY_SERVICE_KEY does not appear in frontend/lib Dart sources', () => {
  const hits = grepDir(clientLib);
  assert.deepEqual(hits, [], `Service key must not ship in client bundle: ${hits.join(', ')}`);
});

test('generate_flutter_dart_defines blocks PROD_GATEWAY_SERVICE_KEY', () => {
  const scriptPath = path.join(repoRoot, 'scripts', 'env', 'generate_flutter_dart_defines.js');
  const text = fs.readFileSync(scriptPath, 'utf8');
  assert.match(text, /FORBIDDEN_IN_CLIENT[\s\S]*PROD_GATEWAY_SERVICE_KEY/);
});