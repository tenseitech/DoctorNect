'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('getValidationRules is publicly invokable for browser CORS preflight', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');
  const block = source.match(
    /exports\.getValidationRules = onCall\([\s\S]*?\),\r?\n\);/,
  );
  assert.ok(block, 'getValidationRules export not found');
  assert.match(block[0], /invoker:\s*'public'/);
  assert.doesNotMatch(block[0], /requireAuth\(request\)/);
});
