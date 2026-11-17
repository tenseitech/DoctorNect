'use strict';

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');

describe('Gateway deny-by-default per app role', () => {
  let mockPostgrestServer;
  let mockPostgrestPort;
  let receivedPostgrestRequests = [];
  let gatewayInstance;
  let gatewayServer;
  let gatewayPort;
  let testPrivateKey;
  let testPublicKey;
  const testKid = 'role-access-key';
  const testProjectId = 'medibond-45fad';
  const testServiceRoleKey = 'test-super-secret-service-role-key-32chars';
  const testPostgrestJwtSecret = 'test-postgrest-jwt-secret-min32chars';
  let mockJwksClient;

  function createTestFirebaseToken({ sub, appRole = 'patient', verified = true }) {
    const header = { alg: 'RS256', typ: 'JWT', kid: testKid };
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      iss: `https://securetoken.google.com/${testProjectId}`,
      aud: testProjectId,
      sub,
      exp: now + 3600,
      iat: now,
      firebase: { sign_in_provider: 'phone' },
      app_role: appRole,
      appRole,
      verified,
      email_verified: verified,
    };
    const headerB64 = base64UrlEncode(JSON.stringify(header));
    const payloadB64 = base64UrlEncode(JSON.stringify(payload));
    const signingInput = `${headerB64}.${payloadB64}`;
    const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput), testPrivateKey);
    return `${signingInput}.${base64UrlEncode(signature)}`;
  }

  function makeRequest({ method = 'GET', path = '/', headers = {} } = {}) {
    return new Promise((resolve, reject) => {
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port: gatewayPort,
          path,
          method,
          headers,
        },
        (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            let json = null;
            try {
              json = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            } catch (_) {}
            resolve({ statusCode: res.statusCode, json });
          });
        },
      );
      req.on('error', reject);
      req.end();
    });
  }

  before(async () => {
    const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    testPrivateKey = keyPair.privateKey;
    testPublicKey = keyPair.publicKey;
    mockJwksClient = new JwksClient();
    mockJwksClient.setMockKeys(new Map([[testKid, testPublicKey]]));

    mockPostgrestServer = http.createServer((req, res) => {
      receivedPostgrestRequests.push({ url: req.url });
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('[]');
    });
    await new Promise((resolve) => mockPostgrestServer.listen(0, '127.0.0.1', resolve));
    mockPostgrestPort = mockPostgrestServer.address().port;

    gatewayInstance = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      firebaseProjectId: testProjectId,
      serviceRoleKey: testServiceRoleKey,
      postgrestJwtSecret: testPostgrestJwtSecret,
      jwksClient: mockJwksClient,
      firebaseRevocationCheck: false,
      rateLimitMaxRequests: 500,
    });
    gatewayServer = gatewayInstance.server;
    await new Promise((resolve) => gatewayServer.listen(0, '127.0.0.1', resolve));
    gatewayPort = gatewayServer.address().port;
  });

  after(async () => {
    gatewayInstance.rateLimiter.dispose();
    await new Promise((resolve) => gatewayServer.close(resolve));
    await new Promise((resolve) => mockPostgrestServer.close(resolve));
  });

  beforeEach(() => {
    receivedPostgrestRequests = [];
    gatewayInstance.rateLimiter.reset();
  });

  const roles = [
    { label: 'patient', appRole: 'patient', allowedTable: 'patients' },
    { label: 'doctor', appRole: 'doctor', allowedTable: 'doctors' },
    { label: 'pharmacy', appRole: 'medicalStore', allowedTable: 'medical_stores' },
    { label: 'lab', appRole: 'lab', allowedTable: 'labs' },
    { label: 'ambulance', appRole: 'ambulance', allowedTable: 'ambulances' },
  ];

  for (const role of roles) {
    it(`${role.label}: allowlisted table proxies (200)`, async () => {
      const token = createTestFirebaseToken({ sub: `${role.label}_uid`, appRole: role.appRole });
      const res = await makeRequest({
        path: `/rest/v1/${role.allowedTable}`,
        headers: { authorization: `Bearer ${token}` },
      });
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it(`${role.label}: service_role-only table denied (403)`, async () => {
      const token = createTestFirebaseToken({ sub: `${role.label}_uid`, appRole: role.appRole });
      const res = await makeRequest({
        path: '/rest/v1/mail_queue',
        headers: { authorization: `Bearer ${token}` },
      });
      assert.strictEqual(res.statusCode, 403);
      assert.strictEqual(res.json.error, 'Forbidden');
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it(`${role.label}: unlisted table denied (403)`, async () => {
      const token = createTestFirebaseToken({ sub: `${role.label}_uid`, appRole: role.appRole });
      const res = await makeRequest({
        path: '/rest/v1/otp_challenges',
        headers: { authorization: `Bearer ${token}` },
      });
      assert.strictEqual(res.statusCode, 403);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });
  }

  it('admin app_role still denied backend-only admin_users at gateway (403)', async () => {
    const token = createTestFirebaseToken({ sub: 'admin_uid', appRole: 'admin' });
    const res = await makeRequest({
      path: '/rest/v1/admin_users',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.strictEqual(res.statusCode, 403);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });
});