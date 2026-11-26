'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('index.js does not require repo scripts when Cloud Run env is set', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(
    src,
    /K_SERVICE/,
    'index must skip repo bootstrap when K_SERVICE or FUNCTION_TARGET is set',
  );
  assert.doesNotMatch(
    src,
    /^require\('\.\.\/\.\.\/scripts\/lib\/bootstrap_root_env'\)/m,
    'index must not unconditionally require repo-only bootstrap',
  );
});