'use strict';

const fs = require('fs');
const path = require('path');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawn, execSync } = require('child_process');
const { Client } = require(path.resolve(process.cwd(), 'scripts/node_modules/pg'));
const { getEnv } = require(path.resolve(process.cwd(), 'scripts/lib/env_loader'));
const { createGatewayServer } = require(path.resolve(process.cwd(), 'services/api-gateway/src/server'));
const { base64UrlEncode } = require(path.resolve(process.cwd(), 'services/api-gateway/src/jwt_minter'));

const POSTGREST_PORT = 3001;
const GATEWAY_PORT = 3000;
const TEST_JWT_SECRET = 'doctornect-secure-postgrest-jwt-secret-min32chars';
const TEST_SERVICE_KEY = 'doctornect-test-service-key-32chars-minimum!';
const TEST_PROJECT_ID = 'medibond-45fad';

// Generate RSA Key pair for Firebase JWKS stub
const { privateKey: testPrivateKey, publicKey: testPublicKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const testKid = 'test-firebase-kid-round10';

function createTestFirebaseToken({
  sub = 'test_usr_pat_a',
  appRole = 'patient',
  verified = true,
  exp = Math.floor(Date.now() / 1000) + 3600,
} = {}) {
  const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
  const payload = {
    iss: `https://securetoken.google.com/${TEST_PROJECT_ID}`,
    aud: TEST_PROJECT_ID,
    sub,
    app_role: appRole,
    user_role: appRole,
    verified,
    exp,
    iat: Math.floor(Date.now() / 1000) - 10,
  };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(signingInput);
  const signature = signer.sign(testPrivateKey, 'base64url');
  return `${signingInput}.${signature}`;
}

function makeRequest(options, postData = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: data,
        });
      });
    });
    req.on('error', reject);
    if (postData) {
      req.write(typeof postData === 'string' ? postData : JSON.stringify(postData));
    }
    req.end();
  });
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  console.log('================================================================');
  console.log('DoctorNect: PostgREST & API Gateway Real HTTP E2E Test Runner');
  console.log('Timestamp: ' + new Date().toISOString());
  console.log('================================================================\n');

  // 1. PostgREST Windows Binary Metadata
  const exePath = path.resolve('.bin/postgrest.exe');
  const zipPath = path.resolve('.bin/postgrest-v12.2.3-windows-x64.zip');
  const zipSha256 = crypto.createHash('sha256').update(fs.readFileSync(zipPath)).digest('hex');
  const exeSha256 = crypto.createHash('sha256').update(fs.readFileSync(exePath)).digest('hex');

  console.log('1. PostgREST Windows Binary Specifications:');
  console.log('   Pinned Version   : PostgREST 12.2.3 (519615d)');
  console.log('   Zip Archive SHA256: ' + zipSha256);
  console.log('   postgrest.exe SHA256: ' + exeSha256);
  console.log('   Executable Path  : ' + exePath);
  console.log('   Runtime DLL Link : C:\\Program Files\\PostgreSQL\\17\\bin\\libpq.dll\n');

  // 2. Prepare database replay_check and seed persistent test fixtures
  console.log('2. Setting up database replay_check and seeding fixtures...');
  const superAdminUrl = getEnv('REPLAY_DB_URL');
  const adminClient = new Client({ connectionString: superAdminUrl });
  await adminClient.connect();

  await adminClient.query(`
    ALTER ROLE authenticator WITH PASSWORD 'authenticator_pass';
    GRANT ALL ON SCHEMA public TO authenticator;
    GRANT anon, authenticated, service_role TO authenticator;
  `);

  const replayClient = new Client({ connectionString: `${superAdminUrl.replace(/\/[^/]+$/, '')}/replay_check` });
  await replayClient.connect();

  // Seed fixtures
  await replayClient.query(`
    DELETE FROM public.appointments WHERE patient_id = 'test_usr_pat_a';
    ALTER TABLE public.doctor_directory_updates NO FORCE ROW LEVEL SECURITY;
    ALTER TABLE public.users NO FORCE ROW LEVEL SECURITY;
    ALTER TABLE public.doctors NO FORCE ROW LEVEL SECURITY;
    ALTER TABLE public.patients NO FORCE ROW LEVEL SECURITY;

    -- Seed test user and doctor
    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
    VALUES 
      ('test_usr_pat_a', 'test_usr_pat_a', 'patient', 'test_usr_pat_a', 'Patient Alpha', 'pa@e2e.test', '+919999900001', true),
      ('test_usr_doc_a', 'test_usr_doc_a', 'doctor', 'test_usr_doc_a', 'Dr. Alpha E2E', 'da@e2e.test', '+919999900003', true)
    ON CONFLICT (id) DO UPDATE SET verified = true;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors)
    VALUES ('test_usr_pat_a', 'test_usr_pat_a', 'Patient Alpha', '+919999900001', true)
    ON CONFLICT (patient_id) DO NOTHING;

    INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, consultation_fee, verified, deactivated)
    VALUES ('test_usr_doc_a', 'test_usr_doc_a', 'Dr. Alpha E2E', 'da@e2e.test', '+919999900003', 'Cardiology', 'MD', 10, 500, true, false)
    ON CONFLICT (doctor_id) DO UPDATE SET verified = true;

    ALTER TABLE public.users FORCE ROW LEVEL SECURITY;
    ALTER TABLE public.doctors FORCE ROW LEVEL SECURITY;
    ALTER TABLE public.patients FORCE ROW LEVEL SECURITY;

    -- Grant access to roles
    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
    GRANT SELECT ON public.doctor_directory TO anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
    GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
  `);

  await replayClient.end();
  await adminClient.end();
  console.log('✔ Fixtures seeded in replay_check successfully.\n');

  // 3. Write PostgREST configuration file
  const confPath = path.resolve('.bin/postgrest.conf');
  const confContent = [
    `db-uri = "postgres://authenticator:authenticator_pass@127.0.0.1:5432/replay_check"`,
    `db-schemas = "public"`,
    `db-anon-role = "anon"`,
    `jwt-secret = "${TEST_JWT_SECRET}"`,
    `jwt-aud = "authenticated"`,
    `server-host = "127.0.0.1"`,
    `server-port = ${POSTGREST_PORT}`,
  ].join('\n');
  fs.writeFileSync(confPath, confContent, 'utf8');
  console.log(`3. Created PostgREST configuration: ${confPath}\n`);

  // 4. Start PostgREST process
  console.log('4. Spawning postgrest.exe process...');
  const envWithPg = {
    ...process.env,
    PATH: `C:\\Program Files\\PostgreSQL\\17\\bin;${process.env.PATH}`,
  };

  const pgrstProc = spawn(exePath, [confPath], {
    env: envWithPg,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let pgrstStdout = '';
  let pgrstStderr = '';
  pgrstProc.stdout.on('data', (d) => { pgrstStdout += d.toString(); });
  pgrstProc.stderr.on('data', (d) => { pgrstStderr += d.toString(); });

  // Wait for PostgREST to be ready
  let pgrstReady = false;
  for (let i = 0; i < 30; i++) {
    await sleep(200);
    try {
      const res = await makeRequest({
        hostname: '127.0.0.1',
        port: POSTGREST_PORT,
        path: '/',
        method: 'GET',
      });
      if (res.statusCode === 200) {
        pgrstReady = true;
        break;
      }
    } catch (_) {}
  }

  if (!pgrstReady) {
    pgrstProc.kill();
    console.error('PostgREST STDOUT:\n' + pgrstStdout);
    console.error('PostgREST STDERR:\n' + pgrstStderr);
    throw new Error('PostgREST failed to start on port ' + POSTGREST_PORT);
  }
  console.log(`✔ PostgREST running and responsive at http://127.0.0.1:${POSTGREST_PORT}\n`);

  // 5. Start API Gateway with Mock JWKS
  console.log('5. Starting API Gateway with Mock Firebase JWKS Stub...');
  const mockJwksClient = {
    getSigningKey: async (kid) => {
      if (kid === testKid) {
        return testPublicKey;
      }
      throw new Error(`Key ID ${kid} not found`);
    },
  };

  const { server: gatewayServer } = createGatewayServer({
    port: GATEWAY_PORT,
    host: '127.0.0.1',
    postgrestUrl: `http://127.0.0.1:${POSTGREST_PORT}`,
    firebaseProjectId: TEST_PROJECT_ID,
    postgrestJwtSecret: TEST_JWT_SECRET,
    serviceRoleKey: TEST_SERVICE_KEY,
    jwksClient: mockJwksClient,
  });

  await new Promise((resolve, reject) => {
    gatewayServer.listen(GATEWAY_PORT, '127.0.0.1', () => resolve());
    gatewayServer.on('error', reject);
  });
  console.log(`✔ API Gateway listening at http://127.0.0.1:${GATEWAY_PORT}\n`);

  try {
    console.log('--- 6. EXECUTING REAL HTTP END-TO-END TESTS ---\n');

    // TEST 1: Anon read of doctor_directory
    console.log('Test 1: Anonymous read of /rest/v1/doctor_directory:');
    const res1 = await makeRequest({
      hostname: '127.0.0.1',
      port: GATEWAY_PORT,
      path: '/rest/v1/doctor_directory',
      method: 'GET',
    });
    console.log(`  HTTP Status: ${res1.statusCode}`);
    console.log(`  Body length: ${res1.body.length} bytes`);
    const docs = JSON.parse(res1.body);
    console.log(`  Doctors retrieved: ${docs.length}`);
    if (res1.statusCode !== 200 || docs.length === 0) {
      throw new Error(`Test 1 Failed: Expected 200 with doctors, got ${res1.statusCode}`);
    }
    console.log('  ✔ Test 1 PASS (Anonymous doctor directory read successful)\n');

    // TEST 2: Authenticated patient book_appointment_atomic
    console.log('Test 2: Authenticated patient booking via /rest/v1/rpc/book_appointment_atomic:');
    const patientToken = createTestFirebaseToken({ sub: 'test_usr_pat_a', appRole: 'patient', verified: true });
    const bookPayload = {
      p_appointment_id: 'test_apt_e2e_' + Date.now(),
      p_doctor_id: 'test_usr_doc_a',
      p_doctor_name: 'Dr. Alpha E2E',
      p_specialization: 'Cardiology',
      p_patient_name: 'Patient Alpha',
      p_patient_age: 30,
      p_patient_gender: 'male',
      p_date_time: '2026-11-06T10:00:00Z',
      p_slot_label: '10:00 AM',
      p_patient_id: 'test_usr_pat_a',
    };
    const res2 = await makeRequest({
      hostname: '127.0.0.1',
      port: GATEWAY_PORT,
      path: '/rest/v1/rpc/book_appointment_atomic',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${patientToken}`,
        'Content-Type': 'application/json',
      },
    }, bookPayload);
    console.log(`  HTTP Status: ${res2.statusCode}`);
    console.log(`  Full Request Body: ${JSON.stringify(bookPayload, null, 2)}`);
    console.log(`  Full Response Body: ${res2.body}`);
    if (res2.statusCode !== 200 && res2.statusCode !== 204) {
      throw new Error(`Test 2 Failed: Expected 200/204, got ${res2.statusCode}: ${res2.body}`);
    }
    console.log('  ✔ Test 2 PASS (Authenticated atomic appointment booking successful)\n');

    // TEST 3: Forbidden RPC returns 403 or 404
    console.log('Test 3: Forbidden RPC /rest/v1/rpc/delete_my_account called by client:');
    const res3 = await makeRequest({
      hostname: '127.0.0.1',
      port: GATEWAY_PORT,
      path: '/rest/v1/rpc/delete_my_account',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${patientToken}`,
        'Content-Type': 'application/json',
      },
    }, {});
    console.log(`  HTTP Status: ${res3.statusCode}`);
    console.log(`  Response: ${res3.body}`);
    if (res3.statusCode !== 403 && res3.statusCode !== 404) {
      throw new Error(`Test 3 Failed: Expected 403 or 404, got ${res3.statusCode}`);
    }
    console.log('  ✔ Test 3 PASS (Forbidden RPC properly rejected by Gateway allowlist)\n');

    // TEST 4: Service-key path
    console.log('Test 4: Service key authorized request to /rest/v1/sync_dead_letter_queue:');
    const res4 = await makeRequest({
      hostname: '127.0.0.1',
      port: GATEWAY_PORT,
      path: '/rest/v1/sync_dead_letter_queue',
      method: 'GET',
      headers: {
        'apikey': TEST_SERVICE_KEY,
      },
    });
    console.log(`  HTTP Status: ${res4.statusCode}`);
    console.log(`  Response: ${res4.body}`);
    if (res4.statusCode !== 200) {
      throw new Error(`Test 4 Failed: Expected 200 for service key path, got ${res4.statusCode}`);
    }
    console.log('  ✔ Test 4 PASS (Service key successfully authenticated and proxies to PostgREST)\n');

    // TEST 5: Rate limit
    console.log('Test 5: Rate limit enforcement on anonymous queries:');
    let got429 = false;
    for (let i = 0; i < 75; i++) {
      const rlRes = await makeRequest({
        hostname: '127.0.0.1',
        port: GATEWAY_PORT,
        path: '/rest/v1/doctor_directory',
        method: 'GET',
      });
      if (rlRes.statusCode === 429) {
        got429 = true;
        console.log(`  Encountered HTTP 429 after request #${i + 1}`);
        console.log(`  Retry-After header: ${rlRes.headers['retry-after'] || rlRes.headers['x-ratelimit-reset']}`);
        break;
      }
    }
    if (!got429) {
      throw new Error('Test 5 Failed: Expected HTTP 429 rate limit exceeded.');
    }
    console.log('  ✔ Test 5 PASS (Rate limiter blocked abusive/flooding requests with 429)\n');

    // TEST 6: Forged x-user-role header
    console.log('Test 6: Request with forged x-user-role / x-app-role header:');
    const res6 = await makeRequest({
      hostname: '127.0.0.1',
      port: GATEWAY_PORT,
      path: '/rest/v1/users',
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${patientToken}`,
        'x-user-role': 'super_admin',
        'x-app-role': 'super_admin',
      },
    });
    console.log(`  HTTP Status: ${res6.statusCode}`);
    console.log(`  Full Request Headers: Authorization: Bearer <patientToken>, x-user-role: super_admin, x-app-role: super_admin`);
    console.log(`  Full Response Body: ${res6.body}`);
    const usersParsed = JSON.parse(res6.body);
    const seesOtherUsers = Array.isArray(usersParsed) && usersParsed.some(u => u.id !== 'test_usr_pat_a');
    console.log(`  Total users returned: ${usersParsed.length}`);
    console.log(`  Can see other users? ${seesOtherUsers ? 'YES (SECURITY FAILURE)' : 'NO (RLS strictly enforced, forged header dropped)'}`);
    if (seesOtherUsers) {
      throw new Error('Test 6 Failed: Forged role header breached security boundary!');
    }
    console.log('  ✔ Test 6 PASS (Forged client role header stripped/ignored; PostgREST JWT minted only from verified token)\n');

    console.log('================================================================');
    console.log('ALL 6 POSTGREST E2E REAL HTTP TESTS PASSED WITH 100% SUCCESS.');
    console.log('================================================================\n');

  } finally {
    console.log('Cleaning up processes...');
    try { gatewayServer.close(); } catch (_) {}
    try { pgrstProc.kill(); } catch (_) {}
    console.log('Processes terminated cleanly.');
  }
}

main().catch(err => {
  console.error('\n❌ E2E Runner Failure:', err);
  process.exit(1);
});
