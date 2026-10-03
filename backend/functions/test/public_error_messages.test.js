'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  clientFacingHttpsMessage,
  GENERIC_AMBULANCE_LOGIN_FAILED,
} = require('../public_error_messages');

test('clientFacingHttpsMessage hides internal error details', () => {
  const err = new HttpsError(
    'internal',
    'FirebaseAuthError: socket hang up at admin.googleapis.com',
  );
  assert.equal(
    clientFacingHttpsMessage(err, GENERIC_AMBULANCE_LOGIN_FAILED),
    GENERIC_AMBULANCE_LOGIN_FAILED,
  );
  assert.equal(
    clientFacingHttpsMessage(err, GENERIC_AMBULANCE_LOGIN_FAILED).includes('FirebaseAuthError'),
    false,
  );
});

test('clientFacingHttpsMessage keeps intentional user-facing HttpsError text', () => {
  const err = new HttpsError('resource-exhausted', 'Please wait a minute before trying again.');
  assert.equal(
    clientFacingHttpsMessage(err, GENERIC_AMBULANCE_LOGIN_FAILED),
    'Please wait a minute before trying again.',
  );
});

test('clientFacingHttpsMessage uses fallback for non-HttpsError', () => {
  assert.equal(
    clientFacingHttpsMessage(new Error('db timeout'), GENERIC_AMBULANCE_LOGIN_FAILED),
    GENERIC_AMBULANCE_LOGIN_FAILED,
  );
});
