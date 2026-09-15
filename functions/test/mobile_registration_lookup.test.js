'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveMobileLookupConflict,
  REGISTRATION_MOBILE_EXISTS_MESSAGE,
  LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE,
} = require('../registration_otp');

test('resolveMobileLookupConflict returns false when mobile is not registered', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: false,
      registeredRole: null,
      requestedRole: 'patient',
      intent: 'login',
    }),
    false,
  );
});

test('resolveMobileLookupConflict blocks registration when mobile exists', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'doctor',
      requestedRole: 'patient',
      intent: 'registration',
    }),
    true,
  );
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'patient',
      requestedRole: 'patient',
      intent: 'registration',
    }),
    true,
  );
});

test('resolveMobileLookupConflict allows login when role matches', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'doctor',
      requestedRole: 'doctor',
      intent: 'login',
    }),
    false,
  );
});

test('resolveMobileLookupConflict blocks login when role differs', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'patient',
      requestedRole: 'doctor',
      intent: 'login',
    }),
    true,
  );
});

test('resolveMobileLookupConflict treats missing requested role as conflict on login', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'patient',
      requestedRole: '',
      intent: 'login',
    }),
    true,
  );
});

test('generic OTP messages do not disclose account roles', () => {
  const roleTerms = ['Doctor', 'Patient', 'Medical Store', 'Diagnostic Lab', 'Ambulance'];
  for (const term of roleTerms) {
    assert.equal(REGISTRATION_MOBILE_EXISTS_MESSAGE.includes(term), false);
    assert.equal(LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE.includes(term), false);
  }
  assert.match(REGISTRATION_MOBILE_EXISTS_MESSAGE, /may already be registered/i);
  assert.match(LOGIN_WRONG_ACCOUNT_TYPE_MESSAGE, /different account type/i);
});
