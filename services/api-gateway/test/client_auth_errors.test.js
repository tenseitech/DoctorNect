'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { clientAuthErrorMessage } = require('../src/client_auth_errors');

describe('clientAuthErrorMessage (SEC-04)', () => {
  it('does not echo Firebase Admin unavailable details', () => {
    const msg = clientAuthErrorMessage(new Error('Firebase Admin unavailable; cannot verify token revocation.'));
    assert.doesNotMatch(msg, /Admin unavailable/);
    assert.match(msg, /Authentication failed/);
  });

  it('maps revoked tokens clearly', () => {
    assert.match(clientAuthErrorMessage(new Error('Token has been revoked.')), /revoked/);
  });
});