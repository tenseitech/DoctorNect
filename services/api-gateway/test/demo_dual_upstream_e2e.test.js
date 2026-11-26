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

  function tokenForUid(sub, extraClaims = {}) {
    const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
    const payload = {
      iss: `https://securetoken.google.com/${testProjectId}`,
      aud: testProjectId,
      sub,
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000) - 10,
      ...extraClaims,
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

  async function post(uid, table, body, extraHeaders = {}) {
    rdsHits = [];
    demoHits = [];
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/rest/v1/${table}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenForUid(uid)}`, 'Content-Type': 'application/json', ...extraHeaders },
      body: JSON.stringify(body),
    });
    await res.text();
    return res.status;
  }

  it('real user registration write goes to RDS only', async () => {
    const status = await post('real_new_user_uid', 'users', { id: 'real_new_user_uid', role: 'doctor', mobile: '9876543210' });
    assert.ok(status < 400, `status ${status}`);
    assert.equal(rdsHits.length, 1);
    assert.equal(demoHits.length, 0);
  });

  it('a client routing hint is rejected outright: the write reaches no upstream', async () => {
    const status = await post('real_new_user_uid', 'users',
      { id: 'real_new_user_uid', role: 'doctor', mobile: '9876543210' },
      { 'x-data-plane': 'supabase', 'x-demo': '1' });
    assert.equal(status, 400);
    assert.equal(rdsHits.length, 0);
    assert.equal(demoHits.length, 0);
  });

  it('a real uid can never register a demo number on RDS (nothing reaches either upstream)', async () => {
    for (const mobile of ['9999900001', '+919999900003', '91 99999 00005']) {
      const status = await post('real_new_user_uid', 'users', { id: 'real_new_user_uid', role: 'doctor', mobile });
      assert.ok(status >= 400, `${mobile}: status ${status}`);
      assert.equal(rdsHits.length, 0, mobile);
      assert.equal(demoHits.length, 0, mobile);
    }
  });

  it('the five built-in demo uids write only to the demo upstream (staging), never RDS', async () => {
    for (const uid of ['rev_fb_doc_001', 'rev_fb_pat_001', 'rev_fb_store_001', 'rev_fb_lab_001', 'rev_fb_amb_001']) {
      const status = await post(uid, 'users', { id: uid, display_name: 'Demo' });
      assert.ok(status < 400, `${uid}: status ${status}`);
      assert.equal(rdsHits.length, 0, uid);
      assert.equal(demoHits.length, 1, uid);
    }
  });

  // ---- Demo-plane marker (demo ambulance on an anonymous session) ----
  const { buildDemoPlaneClaims, MARKER_TTL_SECONDS } = require('../src/shared/demo_plane_marker');
  const ANON = 'anon_ambulance_uid_1';
  const anonClaims = (extra = {}) => ({ firebase: { sign_in_provider: 'anonymous' }, ...extra });
  async function call(method, uid, claims, table, body) {
    rdsHits = [];
    demoHits = [];
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/rest/v1/${table}`, {
      method,
      headers: { Authorization: `Bearer ${tokenForUid(uid, claims)}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    await res.text();
    return res.status;
  }

  it('demo ambulance anonymous session with a valid marker -> demo upstream only (read + write)', async () => {
    const claims = anonClaims(buildDemoPlaneClaims(ANON));
    assert.equal(await call('GET', ANON, claims, 'ambulances?limit=1'), 200);
    assert.deepEqual([rdsHits.length, demoHits.length], [0, 1]);
    assert.ok((await call('PATCH', ANON, claims, 'ambulances?ambulance_id=eq.x', { is_available: true })) < 400);
    assert.deepEqual([rdsHits.length, demoHits.length], [0, 1]);
  });

  it('real ambulance anonymous session (no marker) -> RDS upstream as before', async () => {
    assert.equal(await call('GET', 'real_anon_uid', anonClaims(), 'ambulances?limit=1'), 200);
    assert.deepEqual([rdsHits.length, demoHits.length], [1, 0]);
  });

  it('expired, replayed or non-anonymous markers are rejected and reach no upstream (no RDS write)', async () => {
    const now = Math.floor(Date.now() / 1000);
    const cases = {
      expired: anonClaims(buildDemoPlaneClaims(ANON, now - MARKER_TTL_SECONDS - 120)),
      replayed: anonClaims(buildDemoPlaneClaims('another_anon_uid')),
      nonAnonymous: { firebase: { sign_in_provider: 'custom' }, ...buildDemoPlaneClaims(ANON) },
      edited: anonClaims({ ...buildDemoPlaneClaims(ANON), dn_plane: 'rds' }),
    };
    for (const [name, claims] of Object.entries(cases)) {
      assert.equal(await call('POST', ANON, claims, 'ambulances', { ambulance_id: 'x' }), 401, name);
      assert.deepEqual([rdsHits.length, demoHits.length], [0, 0], name);
    }
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