'use strict';

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');

describe('API Gateway Token Claims Provenance Test Suite', () => {
  let mockPostgrestServer;
  let mockPostgrestPort;
  let receivedPostgrestRequests = [];

  let gatewayInstance;
  let gatewayServer;
  let gatewayPort;

  // Test RSA key pair for Firebase token signing
  let testPrivateKey;
  let testPublicKey;
  const testKid = 'provenance-key-id-001';
  const testProjectId = 'medibond-45fad';
  const testServiceRoleKey = 'test-service-key-provenance-32chars';
  const testPostgrestJwtSecret = 'test-postgrest-jwt-secret-min32chars';
  let mockJwksClient;

  function createTestFirebaseToken({
    kid = testKid,
    alg = 'RS256',
    iss = `https://securetoken.google.com/${testProjectId}`,
    aud = testProjectId,
    sub = 'test_patient_uid',
    appRole = 'patient',
    verified = false,
    exp = Math.floor(Date.now() / 1000) + 3600,
    iat = Math.floor(Date.now() / 1000) - 10,
  } = {}) {
    const header = { alg, kid, typ: 'JWT' };
    const payload = {
      iss,
      aud,
      sub,
      app_role: appRole,
      user_role: appRole,
      verified,
      exp,
      iat,
    };

    const headerB64 = base64UrlEncode(JSON.stringify(header));
    const payloadB64 = base64UrlEncode(JSON.stringify(payload));
    const signingInput = `${headerB64}.${payloadB64}`;

    const signer = crypto.createSign('RSA-SHA256');
    signer.update(signingInput);
    signer.end();
    const signature = signer.sign(testPrivateKey);
    const signatureB64 = base64UrlEncode(signature);

    return `${signingInput}.${signatureB64}`;
  }

  function makeRequest({
    method = 'GET',
    path = '/rest/v1/doctors',
    headers = {},
    body = null,
  }) {
    return new Promise((resolve, reject) => {
      const opts = {
        hostname: '127.0.0.1',
        port: gatewayPort,
        path,
        method,
        headers,
      };

      const req = http.request(opts, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString();
          let json = null;
          try {
            json = JSON.parse(raw);
          } catch (_) {}
          resolve({ status: res.statusCode, headers: res.headers, body: json, raw });
        });
      });

      req.on('error', reject);
      if (body) {
        req.write(typeof body === 'string' ? body : JSON.stringify(body));
      }
      req.end();
    });
  }

  before(async () => {
    // 1. Generate RSA key pair
    const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    testPrivateKey = privateKey;
    testPublicKey = publicKey;

    // 2. Start mock PostgREST upstream server
    mockPostgrestServer = http.createServer((req, res) => {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        receivedPostgrestRequests.push({
          method: req.method,
          url: req.url,
          headers: req.headers,
          body: Buffer.concat(chunks).toString(),
        });
        res.writeHead(200, {
          'Content-Type': 'application/json',
          'Content-Range': '0-0/1',
        });
        res.end(JSON.stringify([{ id: 'test_row_1' }]));
      });
    });

    await new Promise((resolve) => {
      mockPostgrestServer.listen(0, '127.0.0.1', () => {
        mockPostgrestPort = mockPostgrestServer.address().port;
        resolve();
      });
    });

    // 3. Mock JWKS Client
    mockJwksClient = new JwksClient({
      jwksUri: 'http://mock-jwks-unused',
      cacheTtlMs: 60000,
    });
    mockJwksClient.getSigningKey = async (kid) => {
      if (kid === testKid) {
        return testPublicKey;
      }
      throw new Error(`Unknown kid: ${kid}`);
    };

    // 4. Start Gateway Server
    gatewayInstance = createGatewayServer({
      port: 0,
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      postgrestJwtSecret: testPostgrestJwtSecret,
      serviceRoleKey: testServiceRoleKey,
      firebaseProjectId: testProjectId,
      jwksClient: mockJwksClient,
      firebaseRevocationCheck: false,
      requireFirebaseRevocationCheck: false,
      corsAllowedOrigins: ['http://127.0.0.1', 'http://localhost'],
    });

    gatewayServer = gatewayInstance.server;
    await new Promise((resolve) => gatewayServer.listen(0, '127.0.0.1', resolve));
    gatewayPort = gatewayServer.address().port;
  });

  after(async () => {
    if (gatewayInstance?.rateLimiter) gatewayInstance.rateLimiter.dispose();
    if (gatewayInstance?.anonRateLimiter) gatewayInstance.anonRateLimiter.dispose();
    if (gatewayServer) await new Promise((resolve) => gatewayServer.close(resolve));
    if (mockPostgrestServer) {
      await new Promise((resolve) => mockPostgrestServer.close(resolve));
    }
  });

  beforeEach(() => {
    receivedPostgrestRequests = [];
  });

  it('claims provenance: request with forged x-user-role/app_role headers and valid patient token mints JWT with app_role: "patient"', async () => {
    const validPatientToken = createTestFirebaseToken({
      sub: 'test_patient_uid_123',
      appRole: 'patient',
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/doctors',
      headers: {
        Authorization: `Bearer ${validPatientToken}`,
        'x-user-role': 'admin',
        'app_role': 'super_admin',
        'x-role': 'service_role',
        'role': 'admin',
      },
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);

    const proxiedReq = receivedPostgrestRequests[0];
    const authHeader = proxiedReq.headers.authorization;
    assert.ok(authHeader && authHeader.startsWith('Bearer '));

    const postgrestToken = authHeader.slice(7);
    const parts = postgrestToken.split('.');
    assert.strictEqual(parts.length, 3);

    const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));

    // Verify token claims provenance
    assert.strictEqual(payload.role, 'authenticated');
    assert.strictEqual(payload.sub, 'test_patient_uid_123');
    assert.strictEqual(payload.app_role, 'patient');
    assert.strictEqual(payload.user_role, 'patient');

    // Prove forged header claims were completely ignored
    assert.notStrictEqual(payload.app_role, 'admin');
    assert.notStrictEqual(payload.app_role, 'super_admin');
    assert.notStrictEqual(payload.role, 'service_role');
  });
});
