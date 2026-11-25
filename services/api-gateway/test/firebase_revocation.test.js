'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFirebaseTokenNotRevoked,
  resetFirebaseAdminForTesting,
  setAdminAuthForTesting,
} = require('../src/firebase_revocation');

describe('firebase_revocation (SEC-04)', () => {
  beforeEach(() => {
    process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
    resetFirebaseAdminForTesting();
  });

  afterEach(() => {
    process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
    resetFirebaseAdminForTesting();
  });

  it('skips Admin check when not required and Admin unavailable', async () => {
    await assert.doesNotReject(() => assertFirebaseTokenNotRevoked('fake.token', { required: false }));
  });

  it('fails closed when required and Admin unavailable', async () => {
    await assert.rejects(
      () => assertFirebaseTokenNotRevoked('fake.token', { required: true }),
      /Firebase Admin unavailable/,
    );
  });

  it('rejects revoked tokens via Admin verifyIdToken', async () => {
    setAdminAuthForTesting({
      verifyIdToken: async () => {
        const err = new Error('Revoked');
        err.code = 'auth/id-token-revoked';
        throw err;
      },
    });
    await assert.rejects(
      () => assertFirebaseTokenNotRevoked('valid-shaped.token', { required: true }),
      /revoked/i,
    );
  });

  it('accepts valid tokens via Admin verifyIdToken', async () => {
    setAdminAuthForTesting({
      verifyIdToken: async (_token, checkRevoked) => {
        assert.equal(checkRevoked, true);
        return { uid: 'uid_test' };
      },
    });
    await assert.doesNotReject(() => assertFirebaseTokenNotRevoked('valid.token', { required: true }));
  });

  it('maps invalid Admin errors to authentication failure', async () => {
    setAdminAuthForTesting({
      verifyIdToken: async () => {
        const err = new Error('ID token has expired');
        err.code = 'auth/id-token-expired';
        throw err;
      },
    });
    await assert.rejects(
      () => assertFirebaseTokenNotRevoked('expired.token', { required: true }),
      /expired/i,
    );
  });
});