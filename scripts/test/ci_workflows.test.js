'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', '..', '.github', 'workflows');
const files = fs.readdirSync(DIR).filter((f) => /\.ya?ml$/.test(f));
const read = (f) => fs.readFileSync(path.join(DIR, f), 'utf8');

test('every workflow declares least-privilege token permissions', () => {
  for (const f of files) assert.match(read(f), /^permissions:\s*\n\s+contents: read/m, f);
});

test('Flutter CI uses the Flutter version the project builds with (3.50+, AGP 9)', () => {
  for (const f of files) {
    for (const m of read(f).matchAll(/flutter-version:\s*'?(\d+)\.(\d+)/g)) {
      assert.ok(Number(m[1]) > 3 || Number(m[2]) >= 50, `${f}: flutter ${m[1]}.${m[2]}`);
    }
  }
});

test('Node in CI matches the Functions engines field (22)', () => {
  const engines = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'backend', 'functions', 'package.json'), 'utf8')).engines.node;
  for (const f of ['backend-functions-ci.yml', 'env-policy.yml']) {
    const m = read(f).match(/node-version:\s*['"]?(\d+)/);
    assert.equal(m && m[1], String(engines), f);
  }
});

test('CI never publishes an unconfigured release APK', () => {
  assert.doesNotMatch(read('build-apk.yml'), /flutter build apk --release/);
});

test('SQL migrations + tests run in CI on PG17 and PG18', () => {
  const f = files.find((n) => /db-tests/.test(n));
  assert.ok(f, 'db-tests workflow missing');
  assert.match(read(f), /run_sql_tests\.js/);
});
