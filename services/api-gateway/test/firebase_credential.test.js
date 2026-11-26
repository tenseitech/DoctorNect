'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { resolveCredential } = require('../src/firebase_revocation');

function fakeServiceAccount(projectId = 'medibond-45fad') {
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  return {
    type: 'service_account',
    project_id: projectId,
    client_email: 'gateway-revocation@medibond-45fad.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  };
}

test('FIREBASE_SERVICE_ACCOUNT_JSON (ECS, from Secrets Manager) yields a cert credential', () => {
  const cred = resolveCredential({ FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify(fakeServiceAccount()) });
  assert.equal(typeof cred.getAccessToken, 'function');
  assert.equal(cred.clientEmail, 'gateway-revocation@medibond-45fad.iam.gserviceaccount.com');
});

test('without FIREBASE_SERVICE_ACCOUNT_JSON falls back to Application Default Credentials', () => {
  const cred = resolveCredential({});
  assert.equal(typeof cred.getAccessToken, 'function');
  assert.equal(cred.clientEmail, undefined);
});

test('malformed or wrong-project JSON is refused without echoing the value', () => {
  assert.throws(() => resolveCredential({ FIREBASE_SERVICE_ACCOUNT_JSON: '{not json secret-material' }),
    (e) => /not valid JSON/.test(e.message) && !e.message.includes('secret-material'));
  assert.throws(() => resolveCredential({ FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({ type: 'authorized_user' }) }),
    /not a service-account key/);
  assert.throws(() => resolveCredential({
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify(fakeServiceAccount('other-project')),
    FIREBASE_PROJECT_ID: 'medibond-45fad',
  }), /another project/);
});
