'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { verifyFirebaseIdToken } = require('../src/token_verifier');
const { base64UrlEncode } = require('../src/jwt_minter');

describe('token_verifier app role resolution (SEC-06)', () => {
  let privateKey;
  let publicKey;
  const kid = 'role-test-kid';

  it('does not map generic Firebase role claim to app role', async () => {
    const { privateKey: priv, publicKey: pub } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    privateKey = priv;
    publicKey = pub;

    const headerB64 = base64UrlEncode(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' }));
    const payloadB64 = base64UrlEncode(JSON.stringify({
      iss: 'https://securetoken.google.com/medibond-45fad',
      aud: 'medibond-45fad',
      sub: 'uid_test',
      role: 'admin',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000) - 10,
    }));
    const signingInput = `${headerB64}.${payloadB64}`;
    const signer = crypto.createSign('RSA-SHA256');
    signer.update(signingInput);
    signer.end();
    const signatureB64 = base64UrlEncode(signer.sign(privateKey));
    const token = `${signingInput}.${signatureB64}`;

    const verified = await verifyFirebaseIdToken(token, {
      projectId: 'medibond-45fad',
      jwksClient: {
        getSigningKey: async () => publicKey,
      },
    });

    assert.equal(verified.appRole, 'patient');
    assert.notEqual(verified.appRole, 'admin');
  });
});