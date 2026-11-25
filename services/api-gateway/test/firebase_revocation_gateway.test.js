'use strict';

const { describe, it, before, after, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');
const {
  setAdminAuthForTesting,
  resetFirebaseAdminForTesting,
} = require('../src/firebase_revocation');

describe('Gateway + Firebase revocation (SEC-04)', () => {
  let mockPostgrestServer;
  let mockPostgrestPort;
  let gatewayInstance;
  let gatewayServer;
  let gatewayPort;
  let testPrivateKey;
  let testPublicKey;
  const testKid = 'revocation-test-kid';
  const testProjectId = 'medibond-45fad';

  function createTestFirebaseToken(sub = 'uid_patient') {
    const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
    const payload = {
      iss: `https://securetoken.google.com/${testProjectId}`,
      aud: testProjectId,
      sub,
      app_role: 'patient',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000) - 10,
    };
    const headerB64 = base64UrlEncode(JSON.stringify(header));
    const payloadB64 = base64UrlEncode(JSON.stringify(payload));
    const signingInput = `${headerB64}.${payloadB64}`;
    const signer = crypto.createSign('RSA-SHA256');
    signer.update(signingInput);
    signer.end();
    const signatureB64 = base64UrlEncode(signer.sign(testPrivateKey));
    return `${signingInput}.${signatureB64}`;
  }

  before(async () => {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    testPrivateKey = privateKey;
    testPublicKey = publicKey;

    mockPostgrestServer = http.createServer((_req, res) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('[]');
    });
    await new Promise((resolve) => {
      mockPostgrestServer.listen(0, '127.0.0.1', () => {
        mockPostgrestPort = mockPostgrestServer.address().port;
        resolve();
      });
    });

    const mockJwksClient = new JwksClient({ jwksUri: 'http://unused', cacheTtlMs: 60_000 });
    mockJwksClient.getSigningKey = async (kid) => {
      if (kid === testKid) return testPublicKey;
      throw new Error('unknown kid');
    };

    gatewayInstance = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      postgrestJwtSecret: 'test-postgrest-jwt-secret-min32chars',
      firebaseProjectId: testProjectId,
      jwksClient: mockJwksClient,
      firebaseRevocationCheck: true,
      requireFirebaseRevocationCheck: true,
    });
    gatewayServer = gatewayInstance.server;
    await new Promise((resolve) => gatewayServer.listen(0, '127.0.0.1', resolve));
    gatewayPort = gatewayServer.address().port;
  });

  after(async () => {
    if (gatewayInstance?.rateLimiter?.dispose) gatewayInstance.rateLimiter.dispose();
    if (gatewayInstance?.anonRateLimiter?.dispose) gatewayInstance.anonRateLimiter.dispose();
    if (gatewayServer) await new Promise((resolve) => gatewayServer.close(resolve));
    if (mockPostgrestServer) await new Promise((resolve) => mockPostgrestServer.close(resolve));
    resetFirebaseAdminForTesting();
  });

  beforeEach(() => resetFirebaseAdminForTesting());
  afterEach(() => resetFirebaseAdminForTesting());

  it('returns 401 when Admin reports token revoked', async () => {
    setAdminAuthForTesting({
      verifyIdToken: async () => {
        const err = new Error('Revoked');
        err.code = 'auth/id-token-revoked';
        throw err;
      },
    });

    const token = createTestFirebaseToken();
    const status = await new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '127.0.0.1',
        port: gatewayPort,
        path: '/rest/v1/doctors',
        method: 'GET',
        headers: { Authorization: `Bearer ${token}` },
      }, (res) => {
        res.resume();
        resolve(res.statusCode);
      });
      req.on('error', reject);
      req.end();
    });
    assert.equal(status, 401);
  });
});