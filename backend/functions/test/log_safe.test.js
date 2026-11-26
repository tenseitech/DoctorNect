'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { safeErrorForLog } = require('../log_safe');

test('safeErrorForLog drops details/hint/stack and masks phone-like digit runs', () => {
  const err = Object.assign(new Error('duplicate key: Key (mobile)=(9876543210) already exists'), {
    code: '23505', details: 'Key (mobile)=(9876543210)', hint: 'patient Ravi, diagnosis X',
  });
  const out = safeErrorForLog(err);
  const text = JSON.stringify(out);
  assert.equal(out.code, '23505');
  assert.doesNotMatch(text, /9876543210/);
  assert.doesNotMatch(text, /diagnosis|stack|details|hint/);
  assert.match(out.message, /\*\*\*10/);
  assert.equal(safeErrorForLog(null).message, 'null');
  assert.equal(safeErrorForLog('plain').message, 'plain');
});

test('no Function logs a raw error object', () => {
  const dir = path.join(__dirname, '..');
  const offenders = [];
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.js'))) {
    const src = fs.readFileSync(path.join(dir, f), 'utf8');
    src.split('\n').forEach((line, i) => {
      if (/console\.(error|warn)\([^)]*, (err|e|error)\)\s*;/.test(line)) offenders.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(offenders, []);
});
