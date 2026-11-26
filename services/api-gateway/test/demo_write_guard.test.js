'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { writeContainsDemoMobile } = require('../src/demo_write_guard');

test('refuses RDS writes that store a reserved demo number in any spelling', () => {
  for (const body of [
    { mobile: '9999900001' },
    { mobile: '+919999900002' },
    { phone: '+91 99999 00003' },
    [{ users: { contact: { mobile: 919999900004 } } }],
    { mobile: '09999900005' },
  ]) {
    assert.equal(writeContainsDemoMobile(Buffer.from(JSON.stringify(body))), true, JSON.stringify(body));
  }
});

test('allows normal writes and does not join digits across fields', () => {
  for (const body of [
    { mobile: '9876543210' },
    { a: 9999, b: 900001 },
    { note: 'room 9999900001A2' },
    { amount: 99999000010000 },
  ]) {
    assert.equal(writeContainsDemoMobile(JSON.stringify(body)), false, JSON.stringify(body));
  }
  assert.equal(writeContainsDemoMobile(''), false);
  assert.equal(writeContainsDemoMobile('not json'), false);
});
