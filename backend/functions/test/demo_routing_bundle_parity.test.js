'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function bodyHash(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const body = raw.replace(/^\/\*\* Deploy bundle copy[\s\S]*?\*\/\s*/m, '');
  return crypto.createHash('sha256').update(body).digest('hex');
}

test('lib/demo_routing.js matches scripts/lib/demo_routing.js (deploy bundle parity)', () => {
  const root = path.join(__dirname, '..', '..', '..');
  const a = path.join(root, 'scripts', 'lib', 'demo_routing.js');
  const b = path.join(__dirname, '..', 'lib', 'demo_routing.js');
  assert.equal(bodyHash(a), bodyHash(b));
});
test('lib/demo_accounts.js matches scripts/lib/demo_accounts.js (deploy bundle parity)', () => {
  const root = path.join(__dirname, '..', '..', '..');
  const a = path.join(root, 'scripts', 'lib', 'demo_accounts.js');
  const b = path.join(__dirname, '..', 'lib', 'demo_accounts.js');
  assert.equal(bodyHash(a), bodyHash(b));
});
