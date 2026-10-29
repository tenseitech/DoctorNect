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
    if (gatewayInstance.anonRateLimiter) gatewayInstance.anonRateLimiter.dispose();
    await new Promise((resolve) => gatewayServer.close(resolve));
    await new Promise((resolve) => mockPostgrestServer.close(resolve));
  });

  beforeEach(() => {
    receivedPostgrestRequests = [];
    gatewayInstance.rateLimiter.reset();
    if (gatewayInstance.anonRateLimiter) gatewayInstance.anonRateLimiter.reset();
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

  it('forwards only allowlisted headers and drops forbidden/untrusted headers', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_headers_1' });
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: {
        authorization: `Bearer ${validToken}`,
        accept: 'application/json',
        prefer: 'return=representation',
        range: '0-9',
        'x-client-info': 'doctornect-flutter/2.0.0',
        cookie: 'session_id=fake_cookie',
        'x-custom-attack': 'malicious-value',
        'x-forwarded-for': '1.2.3.4',
      },
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);
    const postgrestReq = receivedPostgrestRequests[0];

    // Allowed headers must be forwarded
    assert.strictEqual(postgrestReq.headers.accept, 'application/json');
    assert.strictEqual(postgrestReq.headers.prefer, 'return=representation');
    assert.strictEqual(postgrestReq.headers.range, '0-9');
    assert.strictEqual(postgrestReq.headers['x-client-info'], 'doctornect-flutter/2.0.0');

    // Forbidden / un-allowlisted headers must be stripped
    assert.strictEqual(postgrestReq.headers.cookie, undefined);
    assert.strictEqual(postgrestReq.headers['x-custom-attack'], undefined);
    assert.strictEqual(postgrestReq.headers['x-forwarded-for'], undefined);

    // Schema profiles must be forced to public
    assert.strictEqual(postgrestReq.headers['accept-profile'], 'public');
    assert.strictEqual(postgrestReq.headers['content-profile'], 'public');
  });

  it('rejects non-public Accept-Profile with 400 Bad Request', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_profile_1' });
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: {
        authorization: `Bearer ${validToken}`,
        'accept-profile': 'private',
      },
    });

    assert.strictEqual(res.statusCode, 400);
    assert.strictEqual(res.json.error, 'Bad Request');
    assert.match(res.json.message, /only 'public' schema is permitted/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('rejects non-public Content-Profile with 400 Bad Request', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_profile_2' });
    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/appointments',
      headers: {
        authorization: `Bearer ${validToken}`,
        'content-type': 'application/json',
        'content-profile': 'auth',
      },
      body: JSON.stringify({ notes: 'test' }),
    });

    assert.strictEqual(res.statusCode, 400);
    assert.strictEqual(res.json.error, 'Bad Request');
    assert.match(res.json.message, /only 'public' schema is permitted/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('accepts explicit Accept-Profile: public and forwards it', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_profile_3' });
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: {
        authorization: `Bearer ${validToken}`,
        'accept-profile': 'public',
      },
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);
    assert.strictEqual(receivedPostgrestRequests[0].headers['accept-profile'], 'public');
  });

  it('rejects disallowed HTTP methods with 405 Method Not Allowed', async () => {
    const res = await makeRequest({
      method: 'TRACE',
      path: '/rest/v1/doctor_directory',
    });

    assert.strictEqual(res.statusCode, 405);
    assert.strictEqual(res.json.error, 'Method Not Allowed');
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('rejects access to unallowlisted table with 404 Not Found', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_table_1' });
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/unauthorized_table_xyz',
      headers: { authorization: `Bearer ${validToken}` },
    });

    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(res.json.error, 'Not Found');
    assert.match(res.json.message, /Resource table 'unauthorized_table_xyz' is not allowed/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('allows access to allowlisted table with 200 OK', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_table_2' });
    const res = await makeRequest({
      method: 'GET',
      path: '/rest/v1/appointments',
      headers: { authorization: `Bearer ${validToken}` },
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);
    assert.strictEqual(receivedPostgrestRequests[0].url, '/appointments');
  });

  it('rejects access to unallowlisted RPC with 404 Not Found', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_rpc_1' });
    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/rpc/drop_all_tables',
      headers: {
        authorization: `Bearer ${validToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({}),
    });

    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(res.json.error, 'Not Found');
    assert.match(res.json.message, /RPC function 'drop_all_tables' is not allowed/i);
    assert.strictEqual(receivedPostgrestRequests.length, 0);
  });

  it('allows access to allowlisted RPC with 200 OK', async () => {
    const validToken = createTestFirebaseToken({ sub: 'user_rpc_2' });
    const res = await makeRequest({
      method: 'POST',
      path: '/rest/v1/rpc/book_appointment_atomic',
      headers: {
        authorization: `Bearer ${validToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ p_appointment_id: 'appt_1' }),
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(receivedPostgrestRequests.length, 1);
    assert.strictEqual(receivedPostgrestRequests[0].url, '/rpc/book_appointment_atomic');
  });

  describe('Path Normalization and Resource Embedding', () => {
    it('normalizes multiple/double slashes (//rest//v1//doctors)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_1' });
      const res = await makeRequest({
        method: 'GET',
        path: '//rest//v1//doctors',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
    });

    it('normalizes dot segments (/rest/v1/./doctors)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_2' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/./doctors',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
    });

    it('normalizes URL-encoded characters in table name (/rest/v1/%64octors)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_3' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/%64octors', // %64 = 'd' -> 'doctors'
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
    });

    it('normalizes trailing slashes (/rest/v1/doctors/)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_4' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctors/',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
    });

    it('normalizes uppercase table names to lowercase (/rest/v1/DOCTORS)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_5' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/DOCTORS',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
    });

    it('permits resource embedding queries via an allowlisted table (/rest/v1/appointments?select=*,patients(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_6' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,patients(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/appointments?select=*,patients(*)');
    });
    it('rejects client embedding of service_role-only relation (/appointments?select=*,razorpay_orders(*)) with 404', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_1' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,razorpay_orders(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.strictEqual(res.json.error, 'Not Found');
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows service_role to embed service_role-only tables (/appointments?select=*,razorpay_orders(*))', async () => {
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,razorpay_orders(*)',
        headers: { apikey: testServiceRoleKey },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/appointments?select=*,razorpay_orders(*)');
    });

    it('rejects nested unallowlisted embed (/appointments?select=*,doctors(*,doctor_facilities(*))) for client', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_2' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,doctors(*,doctor_facilities(*))',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'doctor_facilities' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows nested allowlisted embed (/appointments?select=*,doctors(*,reviews(*))) for client', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_3' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,doctors(*,reviews(*))',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/appointments?select=*,doctors(*,reviews(*))');
    });

    it('rejects aliased embed pointing to unallowlisted table (/appointments?select=*,payment:razorpay_orders(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_4' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,payment:razorpay_orders(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows aliased embed pointing to allowlisted table (/appointments?select=*,my_doctor:doctors(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_5' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,my_doctor:doctors(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/appointments?select=*,my_doctor:doctors(*)');
    });

    it('rejects unallowlisted embedded table referenced in or= filter', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_6' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,patients(*)&or=(status.eq.active,razorpay_orders.id.eq.1)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('rejects service_role-only embedded table referenced in and= filter', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_7' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,patients(*)&and=(status.eq.active,razorpay_orders.order_id.eq.1)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows allowlisted embedded table referenced in or= filter', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_8' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,patients(*)&or=(status.eq.active,doctors.id.eq.1)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('asserts upstream forwarded path strictly equals normalized path and not raw path', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_norm_strict' });

      // Case 1: Double slashes
      receivedPostgrestRequests = [];
      const res1 = await makeRequest({
        method: 'GET',
        path: '//rest//v1//doctors',
        headers: { authorization: `Bearer ${validToken}` },
      });
      assert.strictEqual(res1.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
      assert.notStrictEqual(receivedPostgrestRequests[0].url, '//rest//v1//doctors');

      // Case 2: URL encoding %64octors -> doctors
      receivedPostgrestRequests = [];
      const res2 = await makeRequest({
        method: 'GET',
        path: '/rest/v1/%64octors',
        headers: { authorization: `Bearer ${validToken}` },
      });
      assert.strictEqual(res2.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
      assert.notStrictEqual(receivedPostgrestRequests[0].url, '/rest/v1/%64octors');
      assert.notStrictEqual(receivedPostgrestRequests[0].url, '/%64octors');

      // Case 3: Dot segment /./
      receivedPostgrestRequests = [];
      const res3 = await makeRequest({
        method: 'GET',
        path: '/rest/v1/./doctors',
        headers: { authorization: `Bearer ${validToken}` },
      });
      assert.strictEqual(res3.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/doctors');
      assert.notStrictEqual(receivedPostgrestRequests[0].url, '/rest/v1/./doctors');
      assert.notStrictEqual(receivedPostgrestRequests[0].url, '/./doctors');
    });

    it('strictly denies client access to serviceRoleOnlyTables (razorpay_*, mail_queue, etc.)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_service_tables' });
      const serviceRoleOnly = [
        'razorpay_orders',
        'razorpay_payments',
        'razorpay_webhook_events',
        'mail_queue',
        'security_events',
        'storage_audit_logs',
      ];

      for (const table of serviceRoleOnly) {
        receivedPostgrestRequests = [];
        const res = await makeRequest({
          method: 'GET',
          path: `/rest/v1/${table}`,
          headers: { authorization: `Bearer ${validToken}` },
        });
        assert.strictEqual(res.statusCode, 404, `Client should receive 404 on service_role-only table ${table}`);
        assert.strictEqual(receivedPostgrestRequests.length, 0);
      }
    });

    it('allows service_role access to serviceRoleOnlyTables', async () => {
      const serviceRoleOnly = [
        'razorpay_orders',
        'razorpay_payments',
        'mail_queue',
        'security_events',
      ];

      for (const table of serviceRoleOnly) {
        receivedPostgrestRequests = [];
        const res = await makeRequest({
          method: 'GET',
          path: `/rest/v1/${table}`,
          headers: { apikey: testServiceRoleKey },
        });
        assert.strictEqual(res.statusCode, 200, `Service role should access ${table}`);
        assert.strictEqual(receivedPostgrestRequests.length, 1);
        assert.strictEqual(receivedPostgrestRequests[0].url, `/${table}`);
      }
    });

    it('allows authenticated client to access /rest/v1/user_devices for FCM device token registration and denies anonymous access with 401', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_fcm_123' });

      // 1. Authenticated client can upsert device token
      receivedPostgrestRequests = [];
      const postRes = await makeRequest({
        method: 'POST',
        path: '/rest/v1/user_devices?on_conflict=user_id,platform',
        headers: {
          authorization: `Bearer ${validToken}`,
          'content-type': 'application/json',
          prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify({
          user_id: 'user_fcm_123',
          platform: 'android',
          fcm_token: 'test_token_val_123',
          updated_at: new Date().toISOString(),
        }),
      });
      assert.strictEqual(postRes.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/user_devices?on_conflict=user_id,platform');
      assert.strictEqual(receivedPostgrestRequests[0].method, 'POST');
      const postToken = receivedPostgrestRequests[0].headers.authorization.slice(7);
      const postPayload = JSON.parse(base64UrlDecode(postToken.split('.')[1]));
      assert.strictEqual(postPayload.role, 'authenticated');
      assert.strictEqual(postPayload.sub, 'user_fcm_123');

      // 2. Authenticated client can delete device token
      receivedPostgrestRequests = [];
      const delRes = await makeRequest({
        method: 'DELETE',
        path: '/rest/v1/user_devices?user_id=eq.user_fcm_123&platform=eq.android',
        headers: { authorization: `Bearer ${validToken}` },
      });
      assert.strictEqual(delRes.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.strictEqual(receivedPostgrestRequests[0].url, '/user_devices?user_id=eq.user_fcm_123&platform=eq.android');
      assert.strictEqual(receivedPostgrestRequests[0].method, 'DELETE');

      // 3. Anonymous client is strictly blocked with 401 Unauthorized
      receivedPostgrestRequests = [];
      const anonRes = await makeRequest({
        method: 'POST',
        path: '/rest/v1/user_devices?on_conflict=user_id,platform',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ user_id: 'user_fcm_123', platform: 'android', fcm_token: 'test' }),
      });
      assert.strictEqual(anonRes.statusCode, 401);
      assert.strictEqual(receivedPostgrestRequests.length, 0);

      // 4. Service role caller can access user_devices
      receivedPostgrestRequests = [];
      const srvRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/user_devices?select=*',
        headers: { apikey: testServiceRoleKey },
      });
      assert.strictEqual(srvRes.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      const srvToken = receivedPostgrestRequests[0].headers.authorization.slice(7);
      const srvPayload = JSON.parse(base64UrlDecode(srvToken.split('.')[1]));
      assert.strictEqual(srvPayload.role, 'service_role');
    });

    it('rejects requests with duplicate select params with 400 Bad Request', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_dup_select' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*&select=razorpay_orders(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 400);
      assert.match(res.json.message, /Duplicate select parameter is not permitted/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('rejects double-quoted unallowlisted embedded identifiers ("razorpay_orders"(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_quoted_embed' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,"razorpay_orders"(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows double-quoted allowlisted embedded identifiers ("doctors"(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_quoted_allow' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,"doctors"(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('rejects spread unallowlisted embed (...razorpay_orders(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_spread_embed' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,...razorpay_orders(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows spread allowlisted embed (...doctors(*))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_spread_allow' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,...doctors(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('rejects unallowlisted embedded relation in order= query (order=razorpay_orders(created_at.desc))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_order_embed' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,patients(*)&order=razorpay_orders(created_at.desc)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows allowlisted embedded relation in order= query (order=doctors(rating.desc))', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_order_allow' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,doctors(*)&order=doctors(rating.desc)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('rejects unallowlisted embedded relation with !hint!inner combo (!fk!inner)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_hint_inner' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,razorpay_orders!fk_order!inner(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Embedded resource 'razorpay_orders' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows allowlisted embedded relation with !hint!inner combo (!fk!inner)', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_hint_inner_allow' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments?select=*,doctors!fk_doctor!inner(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('rejects direct top-level access to embed-only child tables with 404 Not Found', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_only_direct' });
      const embedOnly = [
        'prescription_medicines',
        'prescription_investigations',
        'prescription_referrals',
        'pharmacy_delivery_medicines',
      ];

      for (const table of embedOnly) {
        const res = await makeRequest({
          method: 'GET',
          path: `/rest/v1/${table}`,
          headers: { authorization: `Bearer ${validToken}` },
        });

        assert.strictEqual(res.statusCode, 404, `Expected 404 for direct access to ${table}`);
        assert.match(res.json.message, new RegExp(`Resource table '${table}' is not allowed`));
      }
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('allows embedded queries on embed-only child tables via parent table with 200 OK', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_embed_only_ok' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/prescriptions?select=*,prescription_medicines(*),prescription_investigations(*)',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
    });

    it('rejects access to removed RPCs (cancel_ambulance_trip, helpful counts) with 404', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_removed_rpcs' });
      const removedRpcs = [
        'cancel_ambulance_trip',
        'increment_review_helpful_count',
        'decrement_review_helpful_count',
      ];

      for (const rpc of removedRpcs) {
        const res = await makeRequest({
          method: 'POST',
          path: `/rest/v1/rpc/${rpc}`,
          headers: { authorization: `Bearer ${validToken}`, 'content-type': 'application/json' },
          body: JSON.stringify({ p_id: '123' }),
        });

        assert.strictEqual(res.statusCode, 404, `Expected 404 for removed RPC ${rpc}`);
        assert.match(res.json.message, new RegExp(`RPC function '${rpc}' is not allowed`));
      }
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('rejects removed pharmacies table alias with 404 Not Found', async () => {
      const validToken = createTestFirebaseToken({ sub: 'user_pharmacies_removed' });
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/pharmacies',
        headers: { authorization: `Bearer ${validToken}` },
      });

      assert.strictEqual(res.statusCode, 404);
      assert.match(res.json.message, /Resource table 'pharmacies' is not allowed/);
      assert.strictEqual(receivedPostgrestRequests.length, 0);
    });

    it('enforces UID-based rate limiting across requests for authenticated user', async () => {
      const uidToken = createTestFirebaseToken({ sub: 'rate_limited_user_test' });

      // Gateway instance is configured with rateLimitMaxRequests: 10 in beforeEach
      // Send 10 requests from distinct IPs to verify that UID-based limiter tracks across IPs
      for (let i = 0; i < 10; i++) {
        const res = await makeRequest({
          method: 'GET',
          path: '/rest/v1/appointments',
          headers: {
            authorization: `Bearer ${uidToken}`,
            'x-forwarded-for': `192.168.1.${i + 1}`,
          },
        });
        assert.strictEqual(res.statusCode, 200);
      }

      // 11th request with same UID from another distinct IP should be rate limited by UID
      const rateLimitedRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/appointments',
        headers: {
          authorization: `Bearer ${uidToken}`,
          'x-forwarded-for': '192.168.1.99',
        },
      });
      assert.strictEqual(rateLimitedRes.statusCode, 429);
      assert.strictEqual(rateLimitedRes.json.error, 'Too Many Requests');
      assert.match(rateLimitedRes.json.message, /Rate limit exceeded for user/);
    });

    it('fails if any table referenced by delete_my_account.js is missing from serviceRoleAllowedTables', () => {
      const config = require('../src/config');
      const deleteMyAccountTables = [
        'users',
        'patients',
        'doctors',
        'medical_stores',
        'labs',
        'ambulances',
        'pharmacy_deliveries',
        'pharmacy_delivery_medicines',
        'lab_orders',
        'lab_bookings',
        'lab_connections',
        'pharmacy_connections',
        'referrals',
        'prescriptions',
        'prescription_medicines',
        'prescription_investigations',
        'prescription_referrals',
        'health_records',
        'family_members',
        'review_votes',
        'reviews',
        'patient_doctor_links',
        'patient_care_team',
        'appointments',
        'ambulance_requests',
        'ambulance_broadcasts',
        'ambulance_trip_contacts',
        'doctor_invites',
        'pharmacy_doctor_invites',
        'doctor_private',
        'doctor_availability',
        'doctor_facilities',
        'doctor_education',
        'doctor_blocked_dates',
        'ambulance_private_settings',
        'ambulance_invites',
        'ambulance_locations',
        'support_tickets',
        'support_ticket_messages',
        'user_devices',
        'in_app_notifications',
        'razorpay_orders',
        'admin_users',
        'provisioning_errors',
      ];

      const serviceRoleAllowedSet = new Set(config.serviceRoleAllowedTables);
      const missingTables = deleteMyAccountTables.filter((t) => !serviceRoleAllowedSet.has(t));

      assert.deepStrictEqual(
        missingTables,
        [],
        `The following tables referenced in delete_my_account.js are missing from serviceRoleAllowedTables: ${missingTables.join(', ')}`
      );
    });

    it('enforces rate limiting using rightmost trusted XFF hop and defeats spoofed client IPs', async () => {
      const realClientIp = '203.0.113.195';

      // Send 10 anonymous requests to public doctor_directory with spoofed leftmost IPs
      for (let i = 0; i < 10; i++) {
        const spoofedIp = `10.0.0.${i + 1}`;
        const res = await makeRequest({
          method: 'GET',
          path: '/rest/v1/doctor_directory',
          headers: {
            'x-forwarded-for': `${spoofedIp}, ${realClientIp}`,
          },
        });
        assert.strictEqual(res.statusCode, 200);
      }

      // 11th request with a new spoofed leftmost IP is still blocked because the rightmost hop is 203.0.113.195
      const rateLimitedRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctor_directory',
        headers: {
          'x-forwarded-for': `10.0.0.99, ${realClientIp}`,
        },
      });
      assert.strictEqual(rateLimitedRes.statusCode, 429);
      assert.strictEqual(rateLimitedRes.json.error, 'Too Many Requests');
      assert.match(rateLimitedRes.json.message, /Rate limit exceeded/);

      // Distinct real client IP is NOT rate-limited
      const otherClientRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctor_directory',
        headers: {
          'x-forwarded-for': '10.0.0.1, 198.51.100.22',
        },
      });
      assert.strictEqual(otherClientRes.statusCode, 200);
    });

    it('service_role traffic is exempt from rate limiting and succeeds for 500 requests in a minute', async () => {
      const sharedIp = '198.51.100.99';

      // Send 500 requests with service_role key from the same IP (in batches of 25 to respect socket pools)
      const responses = [];
      const batchSize = 25;
      for (let i = 0; i < 500; i += batchSize) {
        const batch = [];
        for (let j = 0; j < batchSize && (i + j) < 500; j++) {
          batch.push(
            makeRequest({
              method: 'GET',
              path: '/rest/v1/doctors',
              headers: {
                apikey: testServiceRoleKey,
                authorization: `Bearer ${testServiceRoleKey}`,
                'x-forwarded-for': sharedIp,
              },
            })
          );
        }
        const batchRes = await Promise.all(batch);
        responses.push(...batchRes);
      }

      assert.strictEqual(responses.length, 500);

      // Verify that all 500 requests succeeded with status 200 and none received 429
      for (const res of responses) {
        assert.strictEqual(res.statusCode, 200, `Expected 200 OK but got ${res.statusCode}: ${JSON.stringify(res.json)}`);
      }
    });

    it('rate-limits failed service-key attempts per IP after exceeding limit', async () => {
      const attackerIp = '198.51.100.111';
      const wrongKey = 'totally-wrong-service-key-attempt';

      // 1..4 failed attempts receive 401 Unauthorized
      for (let i = 1; i <= 4; i++) {
        const res = await makeRequest({
          method: 'GET',
          path: '/rest/v1/doctors',
          headers: {
            apikey: wrongKey,
            'x-forwarded-for': attackerIp,
          },
        });
        assert.strictEqual(res.statusCode, 401, `Attempt ${i} should return 401`);
        assert.strictEqual(res.json.error, 'Unauthorized');
      }

      // 5th failed attempt reaches the limit (returns 429)
      const fifthRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctors',
        headers: {
          apikey: wrongKey,
          'x-forwarded-for': attackerIp,
        },
      });
      assert.strictEqual(fifthRes.statusCode, 429);
      assert.strictEqual(fifthRes.json.error, 'Too Many Requests');
      assert.match(fifthRes.json.message, /Too many failed service key attempts/);

      // Subsequent attempt from the same attacker IP is blocked immediately with 429
      const blockedRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctors',
        headers: {
          apikey: wrongKey,
          'x-forwarded-for': attackerIp,
        },
      });
      assert.strictEqual(blockedRes.statusCode, 429);
      assert.strictEqual(blockedRes.json.error, 'Too Many Requests');

      // Different IP is NOT affected by the lockout
      const innocentIp = '198.51.100.222';
      const innocentRes = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctors',
        headers: {
          apikey: testServiceRoleKey,
          'x-forwarded-for': innocentIp,
        },
      });
      assert.strictEqual(innocentRes.statusCode, 200);
    });

    it('enforces anonymous rate limiting per IP and returns 429 when exceeded', async () => {
      const anonIp = '203.0.113.88';
      let limited = false;
      for (let i = 0; i < 15; i++) {
        const res = await makeRequest({
          method: 'GET',
          path: '/rest/v1/doctor_directory',
          headers: { 'x-forwarded-for': anonIp },
        });
        if (res.statusCode === 429) {
          limited = true;
          assert.strictEqual(res.json.error, 'Too Many Requests');
          assert.match(res.json.message, /Rate limit exceeded/);
          break;
        }
      }
      assert.strictEqual(limited, true, 'Expected anonymous requests to be rate-limited');
    });

    it('forces max limit for anonymous queries exceeding anonMaxRows', async () => {
      const anonIp = '203.0.113.89';

      // Case A: Query with limit=500 (exceeding 100) -> forced down to limit=100
      receivedPostgrestRequests.length = 0;
      const resA = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctor_directory?limit=500',
        headers: { 'x-forwarded-for': anonIp },
      });
      assert.strictEqual(resA.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.match(receivedPostgrestRequests[0].url, /limit=100/);

      // Case B: Query with limit=25 (< 100) -> preserved as limit=25
      receivedPostgrestRequests.length = 0;
      const resB = await makeRequest({
        method: 'GET',
        path: '/rest/v1/doctor_directory?limit=25',
        headers: { 'x-forwarded-for': anonIp },
      });
      assert.strictEqual(resB.statusCode, 200);
      assert.strictEqual(receivedPostgrestRequests.length, 1);
      assert.match(receivedPostgrestRequests[0].url, /limit=25/);
    });

    it('rejects anonymous access to medical_directory with 401 Unauthorized', async () => {
      const res = await makeRequest({
        method: 'GET',
        path: '/rest/v1/medical_directory',
      });
      assert.strictEqual(res.statusCode, 401);
      assert.strictEqual(res.json.error, 'Unauthorized');
      assert.match(res.json.message, /Authentication token required/);
    });
  });
});

