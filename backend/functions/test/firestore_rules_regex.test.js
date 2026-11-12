'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');

test('firestore.rules deny-all: no client read/write to any document', () => {
  const rulesContent = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');
  assert.match(rulesContent, /allow read, write: if false/);
  assert.doesNotMatch(rulesContent, /function validPatientProfileStorage/);
});

test('storage.rules deny-all: Firebase Storage not used for PHI', () => {
  const rulesContent = fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8');
  assert.match(rulesContent, /allow read, write: if false/);
});
