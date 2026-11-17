'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');
const { getDatabaseClient, resetDatabaseClientForTesting } = require('../../../backend/functions/src/db/client');
const { assertClientRoutingHintIgnored } = require('../../../scripts/lib/demo_routing');

describe('Demo vs real dual-upstream (local e2e)', () => {
  let rdsUpstream;
  let demoUpstream;
  let rdsPort;
  let demoPort;
  let rdsHits = [];
  let demoHits = [];
  let gateway;
  let gatewayPort;

  const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const testPrivateKey = keyPair.privateKey;
  const testPublicKey = keyPair.publicKey;
  const testKid = 'e2e-key';
  const testProjectId = 'medibond-45fad';
  const serviceKey = 'test-super-secret-service-role-key-32chars';

  function tokenForUid(sub) {
    const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
    const payload = {
      iss: `https://securetoken.google.com/${testProjectId}`,
      aud: testProjectId,
      sub,
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000) - 10,
    };
    const h = base64UrlEncode(JSON.stringify(header));
    const p = base64UrlEncode(JSON.stringify(payload));
    const sig = base64UrlEncode(crypto.sign('RSA-SHA256', Buffer.from(`${h}.${p}`), testPrivateKey));
    return `${h}.${p}.${sig}`;
  }

  before(async () => {
    process.env.APP_ENV = 'production';
    process.env.DEMO_REAL_ROUTING_ENABLED = '1';
    process.env.DEMO_FIREBASE_UID_ALLOWLIST = 'demo_patient_uid';

    rdsUpstream = http.createServer((req, res) => {
      rdsHits.push(req.url);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('[]');
    });
    demoUpstream = http.createServer((req, res) => {
      demoHits.push(req.url);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('[]');
    });
    await new Promise((r) => rdsUpstream.listen(0, '127.0.0.1', r));
    await new Promise((r) => demoUpstream.listen(0, '127.0.0.1', r));
    rdsPort = rdsUpstream.address().port;
    demoPort = demoUpstream.address().port;

    const mockJwksClient = new JwksClient();
    mockJwksClient.setMockKeys(new Map([[testKid, testPublicKey]]));

    gateway = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${rdsPort}`,
      postgrestJwtSecret: 'test-postgrest-jwt-secret-min32chars',
      serviceRoleKey: serviceKey,
      firebaseProjectId: testProjectId,
      jwksClient: mockJwksClient,
      firebaseRevocationCheck: false,
      requireFirebaseRevocationCheck: false,
      demoRealRoutingEnabled: true,
      demoPostgrestUrl: `http://127.0.0.1:${demoPort}`,
      demoPostgrestJwtSecret: 'demo-postgrest-jwt-secret-min32chars',
      rateLimitMaxRequests: 10000,
      anonRateLimitMaxRequests: 10000,
    });
    await new Promise((r) => gateway.server.listen(0, '127.0.0.1', r));
    gatewayPort = gateway.server.address().port;
  });

  after(async () => {
    await new Promise((r) => gateway.server.close(r));
    await new Promise((r) => rdsUpstream.close(r));
    await new Promise((r) => demoUpstream.close(r));
    resetDatabaseClientForTesting();
  });

  it('rejects client routing hint headers', () => {
    const r = assertClientRoutingHintIgnored({ 'x-data-plane': 'supabase', 'x-demo': '1' });
    assert.equal(r.ok, false);
  });

  it('demo Firebase UID -> demo upstream only', async () => {
    rdsHits = [];
    demoHits = [];
    const tok = tokenForUid('demo_patient_uid');
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/rest/v1/patients?limit=1`, {
      headers: { Authorization: `Bearer ${tok}` },
    });
    assert.equal(res.status, 200);
    assert.equal(demoHits.length, 1);
    assert.equal(rdsHits.length, 0);
  });

  it('real Firebase UID -> RDS upstream only', async () => {
    rdsHits = [];
    demoHits = [];
    const tok = tokenForUid('real_user_uid');
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/rest/v1/patients?limit=1`, {
      headers: { Authorization: `Bearer ${tok}` },
    });
    assert.equal(res.status, 200);
    assert.equal(rdsHits.length, 1);
    assert.equal(demoHits.length, 0);
  });

  it('service role -> RDS upstream (Functions path)', async () => {
    rdsHits = [];
    demoHits = [];
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/rest/v1/patients?limit=1`, {
      headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey },
    });
    assert.equal(res.status, 200);
    assert.equal(rdsHits.length, 1);
    assert.equal(demoHits.length, 0);
  });

  it('getDatabaseClient: demo uid -> DEMO_SUPABASE_URL; real -> PROD_GATEWAY_URL', () => {
    resetDatabaseClientForTesting();
    process.env.PROD_GATEWAY_URL = `http://127.0.0.1:${gatewayPort}`;
    process.env.PROD_GATEWAY_SERVICE_KEY = serviceKey;
    process.env.DEMO_SUPABASE_URL = `http://127.0.0.1:${demoPort}`;
    process.env.DEMO_SUPABASE_SERVICE_ROLE_KEY = serviceKey;
    const demoClient = getDatabaseClient({ firebaseUid: 'demo_patient_uid', forceNew: true });
    const realClient = getDatabaseClient({ firebaseUid: 'real_user_uid', forceNew: true });
    assert.match(demoClient.supabaseUrl, new RegExp(`:${demoPort}`));
    assert.match(realClient.supabaseUrl, new RegExp(`:${gatewayPort}`));
  });
});