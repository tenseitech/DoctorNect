'use strict';

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');
const { base64UrlDecode } = require('../src/token_verifier');

describe('DoctorNect Auth Gateway & Token Security Suite', () => {
  let mockPostgrestServer;
  let mockPostgrestPort;
  let receivedPostgrestRequests = [];

  let gatewayInstance;
  let gatewayServer;
  let gatewayPort;

  // Test RSA key pair
  let testPrivateKey;
  let testPublicKey;
  const testKid = 'test-key-id-001';
  const testProjectId = 'medibond-45fad';
  const testServiceRoleKey = 'test-super-secret-service-role-key-32chars';
  const testPostgrestJwtSecret = 'test-postgrest-jwt-secret-min32chars';
  let mockJwksClient;

  function createTestFirebaseToken({
    kid = testKid,
    alg = 'RS256',
    iss = `https://securetoken.google.com/${testProjectId}`,
    aud = testProjectId,
    sub = 'user_firebase_123',
    appRole = 'patient',
    verified = false,
    exp = Math.floor(Date.now() / 1000) + 3600,
    iat = Math.floor(Date.now() / 1000) - 10,
    tamper = false,
    privateKey = null,
  } = {}) {
    const signingKey = privateKey || testPrivateKey;
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

    if (alg === 'none') {
      return `${signingInput}.`;
    }

    const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput), signingKey);
    let signatureB64 = base64UrlEncode(signature);

    if (tamper) {
      // Modify first char to guarantee corrupted signature byte
      signatureB64 = (signatureB64[0] === 'A' ? 'B' : 'A') + signatureB64.slice(1);
    }

    return `${signingInput}.${signatureB64}`;
  }

  function makeRequest({
    method = 'GET',
    path = '/',
    headers = {},
    body = null,
  } = {}) {
    return new Promise((resolve, reject) => {
      const reqHeaders = { ...headers };
      if (body) {
        reqHeaders['content-length'] = Buffer.byteLength(body);
      }
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port: gatewayPort,
          path,
          method,
          headers: reqHeaders,
        },
        (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            const resBody = Buffer.concat(chunks).toString('utf8');
            let json = null;
            try {
              json = JSON.parse(resBody);
            } catch (_) {}
            resolve({
              statusCode: res.statusCode,
              headers: res.headers,
              body: resBody,
              json,
            });
          });
        }
      );
      req.on('error', reject);
      if (body) req.write(body);
      req.end();
    });
  }

  before(async () => {
    // 1. Generate RSA key pair for testing
    const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    testPrivateKey = keyPair.privateKey;
    testPublicKey = keyPair.publicKey;

    mockJwksClient = new JwksClient();
    mockJwksClient.setMockKeys(new Map([[testKid, testPublicKey]]));

    // 2. Start mock PostgREST backend
    mockPostgrestServer = http.createServer((req, res) => {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        receivedPostgrestRequests.push({
          method: req.method,
          url: req.url,
          headers: req.headers,
          body,
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify([{ id: 1, name: 'ok' }]));
      });
    });

    await new Promise((resolve) => mockPostgrestServer.listen(0, '127.0.0.1', resolve));
    mockPostgrestPort = mockPostgrestServer.address().port;

    // 3. Start Gateway Server
    gatewayInstance = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      firebaseProjectId: testProjectId,
      serviceRoleKey: testServiceRoleKey,
      postgrestJwtSecret: testPostgrestJwtSecret,
      jwksClient: mockJwksClient,
      rateLimitMaxRequests: 10, // Small limit for testing
      maxBodySizeBytes: 1024, // 1 KB limit for testing
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

  it('serves /healthz with 200 OK and healthy status', async () => {
    const res = await makeRequest({ path: '/healthz' });
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.json.status, 'healthy');
    assert.strictEqual(res.json.service, 'doctornect-auth-gateway');
  });

  it('handles OPTIONS preflight with CORS headers', async () => {
    const res = await makeRequest({ method: 'OPTIONS', path: '/rest/v1/doctor_directory' });
    assert.strictEqual(res.statusCode, 204);
    assert.strictEqual(res.headers['access-control-allow-origin'], '*');
  });

  it('returns 404 for paths outside /rest/v1', async () => {
    const res = await makeRequest({ path: '/some/other/api' });
    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(res.json.error, 'Not Found');
  });

  it('allows anonymous read for allowlisted public paths', async () => {
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/doctor_directory?select=*',
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);

    const postgrestReq = receivedPostgrestRequests[0];
    assert.strictEqual(postgrestReq.url, '/doctor_directory?select=*');

    // Decode PostgREST JWT
    const token = postgrestReq.headers.authorization.slice(7);
    const [, payloadB64] = token.split('.');
    const payload = JSON.parse(base64UrlDecode(payloadB64));

    assert.strictEqual(payload.role, 'anon');
    assert.strictEqual(payload.sub, 'anon');
  });

  it('denies anonymous access to protected paths with 401', async () => {
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/users?select=*',
    });

    assert.strictEqual(res.statusCode, 401);
    assert.strictEqual(res.json.error, 'Unauthorized');
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('authenticates with service role key via apikey header', async () => {
    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/users',
      headers: {
        apikey: testServiceRoleKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ name: 'Admin Created' }),
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);

    const postgrestReq = receivedPostgrestRequests[0];
    assert.strictEqual(postgrestReq.url, '/users');

    const token = postgrestReq.headers.authorization.slice(7);
    const [, payloadB64] = token.split('.');
    const payload = JSON.parse(base64UrlDecode(payloadB64));

    assert.strictEqual(payload.role, 'service_role');
    assert.strictEqual(payload.verified, true);
  });

  it('authenticates valid Firebase ID token and forwards claims to PostgREST', async () => {
    const validToken = createTestFirebaseToken({
      sub: 'patient_firebase_456',
      appRole: 'patient',
      verified: true,
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments?patient_id=eq.patient_firebase_456',
      headers: {
        authorization: `Bearer ${validToken}`,
      },
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);

    const postgrestReq = receivedPostgrestRequests[0];
    const token = postgrestReq.headers.authorization.slice(7);
    const [, payloadB64] = token.split('.');
    const payload = JSON.parse(base64UrlDecode(payloadB64));

    assert.strictEqual(payload.role, 'authenticated');
    assert.strictEqual(payload.sub, 'patient_firebase_456');
    assert.strictEqual(payload.app_role, 'patient');
    assert.strictEqual(payload.verified, true);
    assert.ok(payload.exp - payload.iat <= 60); // 60s max validity
  });

  it('rejects expired Firebase token with 401', async () => {
    const expiredToken = createTestFirebaseToken({
      exp: Math.floor(Date.now() / 1000) - 100, // 100s in the past
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${expiredToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /expired/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('rejects token with invalid issuer', async () => {
    const badIssToken = createTestFirebaseToken({
      iss: 'https://securetoken.google.com/malicious-project',
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${badIssToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /issuer/i);
  });

  it('rejects token with invalid audience', async () => {
    const badAudToken = createTestFirebaseToken({
      aud: 'other-project-id',
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${badAudToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /audience/i);
  });

  it('rejects token with alg: none', async () => {
    const noneToken = createTestFirebaseToken({
      alg: 'none',
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${noneToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /algorithm/i);
  });

  it('rejects tampered token signature', async () => {
    const tamperedToken = createTestFirebaseToken({
      tamper: true,
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${tamperedToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /signature/i);
  });

  it('enforces payload size limits with 413 Payload Too Large', async () => {
    const largeBody = 'A'.repeat(2048); // Configured limit is 1024 bytes
    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/doctor_directory',
      headers: { 'content-type': 'text/plain' },
      body: largeBody,
    });

    assert.strictEqual(res.statusCode, 413);
    assert.strictEqual(res.json.error, 'Payload Too Large');
  });

  it('enforces rate limits with 429 Too Many Requests', async () => {
    for (let i = 0; i < 10; i++) {
      const res = await makeRequest({ path: '/rest/v1/doctor_directory' });
      assert.strictEqual(res.statusCode, 200);
    }

    // 11th request should be rate-limited
    const rateLimitedRes = await makeRequest({ path: '/rest/v1/doctor_directory' });
    assert.strictEqual(rateLimitedRes.statusCode, 429);
    assert.strictEqual(rateLimitedRes.json.error, 'Too Many Requests');
  });

  it('rejects token signed by another key not registered in JWKS', async () => {
    // Generate a different RSA key pair
    const untrustedKeyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    const untrustedToken = createTestFirebaseToken({
      kid: testKid, // claims to be testKid, but signed with foreign key
      privateKey: untrustedKeyPair.privateKey,
    });

    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${untrustedToken}` },
    });

    assert.strictEqual(res.statusCode, 401);
    assert.match(res.json.message, /signature verification failed/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('sanitizes forged role headers and claims, enforcing authenticated role', async () => {
    // User tries to claim admin/service_role via headers and token payload
    const forgedToken = createTestFirebaseToken({
      sub: 'attacker_123',
      appRole: 'admin',
    });

    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/appointments',
      headers: {
        authorization: `Bearer ${forgedToken}`,
        role: 'service_role',
        'x-role': 'admin',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ reason: 'Checkup' }),
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);

    const postgrestReq = receivedPostgrestRequests[0];
    // Gateway must strip caller-supplied role and x-role headers
    assert.strictEqual(postgrestReq.headers.role, undefined);
    assert.strictEqual(postgrestReq.headers['x-role'], undefined);

    // Decoded PostgREST JWT must strictly enforce role = 'authenticated'
    const token = postgrestReq.headers.authorization.slice(7);
    const [, payloadB64] = token.split('.');
    const payload = JSON.parse(base64UrlDecode(payloadB64));

    assert.strictEqual(payload.role, 'authenticated');
    assert.strictEqual(payload.sub, 'attacker_123');
  });

  it('supports JWKS key rotation dynamically', async () => {
    const rotatedKeyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    const rotatedKid = 'test-key-id-002-rotated';

    // Simulate key rotation in JWKS: both old and new keys active
    mockJwksClient.setMockKeys(
      new Map([
        [testKid, testPublicKey],
        [rotatedKid, rotatedKeyPair.publicKey],
      ])
    );

    // Token signed with newly rotated key succeeds
    const rotatedToken = createTestFirebaseToken({
      kid: rotatedKid,
      privateKey: rotatedKeyPair.privateKey,
      sub: 'rotated_user_789',
    });

    const res1 = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${rotatedToken}` },
    });
    assert.strictEqual(res1.statusCode, 200);

    // Now retire the old key from JWKS
    mockJwksClient.setMockKeys(
      new Map([
        [rotatedKid, rotatedKeyPair.publicKey],
      ])
    );

    // Token signed with old retired key is now rejected
    const oldKeyToken = createTestFirebaseToken({
      kid: testKid,
      sub: 'old_key_user',
    });

    const res2 = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${oldKeyToken}` },
    });
    assert.strictEqual(res2.statusCode, 401);
    assert.match(res2.json.message, /unable to find public key/i);

    // Restore original mock key state for subsequent tests
    mockJwksClient.setMockKeys(new Map([[testKid, testPublicKey]]));
  });
});
