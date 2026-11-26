'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { AMBULANCE_REAL_ACCOUNT_SIGNIN, classifyAmbulanceSession } = require('../ambulance_session');

test('real-account sign-in groundwork is OFF', () => {
  assert.equal(AMBULANCE_REAL_ACCOUNT_SIGNIN, false);
});

test('classifyAmbulanceSession: anonymous / owner / other / none', () => {
  const anon = { uid: 'a1', token: { firebase: { sign_in_provider: 'anonymous' } } };
  const owner = { uid: 'u_owner', token: { firebase: { sign_in_provider: 'custom' } } };
  assert.equal(classifyAmbulanceSession(anon, 'u_owner'), 'anonymous');
  assert.equal(classifyAmbulanceSession(owner, 'u_owner'), 'owner');
  assert.equal(classifyAmbulanceSession(owner, 'someone_else'), 'other');
  assert.equal(classifyAmbulanceSession(owner, null), 'other');
  assert.equal(classifyAmbulanceSession(null, 'u_owner'), 'none');
});
