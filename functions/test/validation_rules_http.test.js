'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..', '..');

test('web loads validation rules through same-origin hosting rewrite', () => {
  const firebaseJson = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'firebase.json'), 'utf8'),
  );
  const rewrite = firebaseJson.hosting.rewrites.find(
    (entry) => entry.source === '/api/validation-rules',
  );
  assert.ok(rewrite, 'Missing /api/validation-rules hosting rewrite');
  assert.equal(rewrite.function.functionId, 'getValidationRulesHttp');
  assert.equal(rewrite.function.region, 'asia-south1');
});

test('getValidationRulesHttp serves declarative rules over GET', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');
  assert.match(source, /exports\.getValidationRulesHttp = onRequest\(/);
  assert.match(source, /rules: RULES, vitalThresholds: VITAL_THRESHOLDS, version: 1/);
});

test('web client fetches validation rules from hosting proxy path', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'lib', 'core', 'validation', 'server_validation_service.dart'),
    'utf8',
  );
  assert.match(source, /kIsWeb/);
  assert.match(source, /\/api\/validation-rules/);
});
