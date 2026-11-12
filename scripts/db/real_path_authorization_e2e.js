'use strict';

/**
 * Real PostgREST + Auth Gateway HTTP tests against fresh local DB (no mocked PostgREST).
 * Requires .bin/postgrest.exe and PostgreSQL libpq on PATH (see docs/ops/postgrest_windows_binary.md).
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { Client } = require('pg');
process.env.FIREBASE_REVOCATION_CHECK = 'false';
process.env.APP_ENV = process.env.APP_ENV || 'test';
const { getEnv } = require('../lib/env_loader');
const { createGatewayServer } = require('../../services/api-gateway/src/server');
const { base64UrlEncode } = require('../../services/api-gateway/src/jwt_minter');
const { seedFixtures } = require('./gateway_rls_authorization_suite');

const POSTGREST_PORT = parseInt(process.env.PGRST_E2E_PORT || '3011', 10);
const GATEWAY_PORT = parseInt(process.env.GATEWAY_E2E_PORT || '3010', 10);
const TEST_JWT_SECRET = process.env.PGRST_JWT_SECRET || 'doctornect-secure-postgrest-jwt-secret-min32chars';
const TEST_SERVICE_KEY = process.env.SERVICE_ROLE_KEY || 'doctornect-test-service-key-32chars-minimum!';
const TEST_PROJECT_ID = 'medibond-45fad';
const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

const { privateKey: testPrivateKey, publicKey: testPublicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const testKid = 'real-path-e2e-kid';

function freshUrl() {
  const base = getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

function createTestFirebaseToken({ sub, appRole = 'patient', expOffset = 3600 }) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
  const payload = {
    iss: `https://securetoken.google.com/${TEST_PROJECT_ID}`,
    aud: TEST_PROJECT_ID,
    sub,
    app_role: appRole,
    user_role: appRole,
    verified: true,
    exp: now + expOffset,
    iat: now - 10,
  };
  const h = base64UrlEncode(JSON.stringify(header));
  const p = base64UrlEncode(JSON.stringify(payload));
  const input = `${h}.${p}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(input), testPrivateKey);
  return `${input}.${base64UrlEncode(sig)}`;
}

function httpReq(port, method, urlPath, headers, body) {
  return new Promise((resolve, reject) => {
    const h = { ...headers };
    const data = body ? JSON.stringify(body) : null;
    if (data) h['Content-Type'] = 'application/json';
    const req = http.request({ hostname: '127.0.0.1', port, path: urlPath, method, headers: h }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function main() {
  const matrix = [];
  const exePath = path.resolve('.bin/postgrest.exe');
  if (!fs.existsSync(exePath)) {
    console.error('Missing .bin/postgrest.exe — see docs/ops/postgrest_windows_binary.md');
    process.exit(1);
  }

  const admin = new Client({ connectionString: getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres' });
  await admin.connect();
  await admin.query(`ALTER ROLE authenticator WITH LOGIN PASSWORD 'authenticator_pass';`).catch(() => {});
  await admin.query(`GRANT ALL ON SCHEMA public TO authenticator;`);
  await admin.query(`GRANT anon, authenticated, service_role TO authenticator;`);
  await admin.end();

  const dbClient = new Client({ connectionString: freshUrl() });
  await dbClient.connect();
  await dbClient.query('BEGIN');
  const ids = await seedFixtures(dbClient);
  await dbClient.query('COMMIT');
  await dbClient.end();

  const confPath = path.resolve('.bin/postgrest-fresh-local.conf');
  fs.writeFileSync(
    confPath,
    [
      `db-uri = "postgres://authenticator:authenticator_pass@127.0.0.1:5432/${DB_NAME}"`,
      'db-schemas = "public"',
      'db-anon-role = "anon"',
      'jwt-secret = "$(PGRST_JWT_SECRET)"',
      'jwt-secret-is-base64 = false',
      'jwt-aud = "authenticated"',
      'server-host = "127.0.0.1"',
      `server-port = ${POSTGREST_PORT}`,
    ].join('\n'),
    'utf8',
  );

  const envWithPg = {
    ...process.env,
    PGRST_JWT_SECRET: TEST_JWT_SECRET,
    PATH: `C:\\Program Files\\PostgreSQL\\17\\bin;${process.env.PATH}`,
  };
  const pgrstLogs = [];
  const pgrst = spawn(exePath, [confPath], { env: envWithPg, stdio: ['ignore', 'pipe', 'pipe'] });
  pgrst.stderr.on('data', (c) => pgrstLogs.push(String(c)));

  let ready = false;
  for (let i = 0; i < 40; i++) {
    await sleep(250);
    try {
      const r = await httpReq(POSTGREST_PORT, 'GET', '/', {});
      if (r.status === 200) {
        ready = true;
        break;
      }
    } catch (_) {}
  }
  if (!ready) {
    pgrst.kill();
    throw new Error('PostgREST did not become ready');
  }

  const mockJwks = {
    async getSigningKey(kid) {
      if (kid === testKid) return testPublicKey;
      throw new Error('unknown kid');
    },
  };

  const { server: gateway } = createGatewayServer({
    postgrestUrl: `http://127.0.0.1:${POSTGREST_PORT}`,
    firebaseProjectId: TEST_PROJECT_ID,
    postgrestJwtSecret: TEST_JWT_SECRET,
    serviceRoleKey: TEST_SERVICE_KEY,
    anonKey: 'public-anon-key-e2e',
    jwksClient: mockJwks,
    firebaseRevocationCheck: false,
    requireFirebaseRevocationCheck: false,
  });

  await new Promise((resolve, reject) => {
    gateway.listen(GATEWAY_PORT, '127.0.0.1', resolve);
    gateway.on('error', reject);
  });

  try {
    const r1 = await httpReq(GATEWAY_PORT, 'GET', '/rest/v1/doctor_directory?limit=1', {});
    matrix.push({
      test: 'anon doctor_directory',
      verdict: r1.status === 200 ? 'PASS' : 'FAIL',
      http: r1.status,
      detail: r1.status === 200 ? '' : r1.body.slice(0, 240),
    });

    const patTok = createTestFirebaseToken({ sub: ids.pA, appRole: 'patient' });
    const r2 = await httpReq(GATEWAY_PORT, 'GET', `/rest/v1/patients?patient_id=eq.${ids.pA}&select=patient_id`, {
      Authorization: `Bearer ${patTok}`,
    });
    matrix.push({ test: 'patient own patients row', verdict: r2.status === 200 && r2.body.includes(ids.pA) ? 'PASS' : 'FAIL', http: r2.status });

    const r3 = await httpReq(GATEWAY_PORT, 'GET', `/rest/v1/patients?patient_id=eq.${ids.pB}&select=patient_id`, {
      Authorization: `Bearer ${patTok}`,
    });
    matrix.push({
      test: 'patient cross-user patients',
      verdict: r3.status === 200 && !r3.body.includes(ids.pB) ? 'PASS' : 'FAIL',
      http: r3.status,
    });

    const r4 = await httpReq(GATEWAY_PORT, 'GET', '/rest/v1/patients?limit=1', {});
    matrix.push({ test: 'no token rejected', verdict: r4.status === 401 ? 'PASS' : 'FAIL', http: r4.status });

    const expired = createTestFirebaseToken({ sub: ids.pA, expOffset: -60 });
    const r5 = await httpReq(GATEWAY_PORT, 'GET', '/rest/v1/patients?limit=1', { Authorization: `Bearer ${expired}` });
    matrix.push({ test: 'expired token rejected', verdict: r5.status === 401 ? 'PASS' : 'FAIL', http: r5.status });

    const r6 = await httpReq(GATEWAY_PORT, 'GET', '/rest/v1/sync_dead_letter_queue?limit=1', { apikey: TEST_SERVICE_KEY });
    matrix.push({ test: 'service key sync_dead_letter_queue', verdict: r6.status === 200 ? 'PASS' : 'FAIL', http: r6.status });

    const r7 = await httpReq(
      GATEWAY_PORT,
      'POST',
      '/rest/v1/rpc/book_appointment_atomic',
      { Authorization: `Bearer ${patTok}` },
      {
        p_appointment_id: `e2e_${Date.now()}`,
        p_doctor_id: ids.docA,
        p_doctor_name: 'Doc A',
        p_specialization: 'Gen',
        p_patient_name: 'Pat A',
        p_patient_age: 30,
        p_patient_gender: 'male',
        p_date_time: new Date().toISOString(),
        p_slot_label: '10:00',
        p_patient_id: ids.pA,
      },
    );
    matrix.push({ test: 'book_appointment_atomic via gateway', verdict: r7.status >= 200 && r7.status < 300 ? 'PASS' : 'FAIL', http: r7.status });

    console.table(matrix);
    const fails = matrix.filter((m) => m.verdict === 'FAIL').length;
    const out = path.resolve(__dirname, '../../docs/reports/real_path_authorization_e2e.json');
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, JSON.stringify({ at: new Date().toISOString(), matrix }, null, 2));
    console.log(`Wrote ${out}`);
    console.log(`SUMMARY: ${matrix.length - fails} PASS / ${fails} FAIL`);
    if (fails) process.exit(1);
  } finally {
    await new Promise((r) => gateway.close(r));
    pgrst.kill();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
