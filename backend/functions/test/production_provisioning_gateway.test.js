'use strict';

const { describe, it, before, after, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const config = require('../../../services/api-gateway/src/config');
const { createGatewayServer } = require('../../../services/api-gateway/src/server');
const { getDatabaseClient, resetDatabaseClientForTesting } = require('../src/db/client');

describe('Production Provisioning Integration with Gateway', () => {
  let mockPostgrestServer;
  let mockPostgrestPort;
  let receivedPostgrestRequests = [];

  let gatewayServer;
  let gatewayPort;

  const testServiceRoleKey = 'test-prod-gateway-service-role-key-32chars';
  const originalEnv = { ...process.env };

  before(async () => {
    // 1. Mock PostgREST Backend
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

        res.writeHead(200, {
          'Content-Type': 'application/json',
          'Content-Range': '0-0/1',
        });
        res.end(JSON.stringify([{ id: 'mock-id-001', success: true }]));
      });
    });

    await new Promise((resolve) => mockPostgrestServer.listen(0, '127.0.0.1', resolve));
    mockPostgrestPort = mockPostgrestServer.address().port;

    // 2. Mock Gateway Server built from real config.js
    const gateway = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      serviceRoleKey: testServiceRoleKey,
      firebaseProjectId: 'medibond-45fad',
    });

    gatewayServer = gateway.server;
    await new Promise((resolve) => gatewayServer.listen(0, '127.0.0.1', resolve));
    gatewayPort = gatewayServer.address().port;
  });

  after(async () => {
    if (gatewayServer) await new Promise((resolve) => gatewayServer.close(resolve));
    if (mockPostgrestServer) await new Promise((resolve) => mockPostgrestServer.close(resolve));
    process.env = { ...originalEnv };
  });

  beforeEach(() => {
    resetDatabaseClientForTesting();
    receivedPostgrestRequests = [];
    process.env = { ...originalEnv };
    process.env.APP_ENV = 'production';
    process.env.PROD_GATEWAY_URL = `http://127.0.0.1:${gatewayPort}`;
    process.env.PROD_GATEWAY_SERVICE_KEY = testServiceRoleKey;
  });

  afterEach(() => {
    resetDatabaseClientForTesting();
  });

  it('proves getDatabaseClient under APP_ENV=production connects to PROD_GATEWAY with zero denied requests across all roles', async () => {
    const client = getDatabaseClient();
    assert.ok(client);
    assert.strictEqual(client.supabaseUrl, `http://127.0.0.1:${gatewayPort}`);

    const rolesToTest = [
      { role: 'patient', table: 'patients', idCol: 'patient_id', ownerCol: 'owner_uid', idVal: 'pat_prod_01' },
      { role: 'doctor', table: 'doctors', idCol: 'doctor_id', ownerCol: 'owner_uid', idVal: 'doc_prod_01' },
      { role: 'lab', table: 'labs', idCol: 'lab_id', ownerCol: 'owner_uid', idVal: 'lab_prod_01' },
      { role: 'medicalStore', table: 'medical_stores', idCol: 'store_id', ownerCol: 'owner_uid', idVal: 'store_prod_01' },
      { role: 'ambulance', table: 'ambulances', idCol: 'ambulance_id', ownerCol: 'auth_uid', idVal: 'amb_prod_01' },
    ];

    const deniedRequests = [];
    const successfulRequests = [];

    for (const item of rolesToTest) {
      const testUid = `uid_${item.role}_999`;
      const testMobile = `+9199999000${rolesToTest.indexOf(item) + 1}`;

      // 1. Mobile existence check via users table (lookup)
      const lookupRes = await client
        .from('users')
        .select('id, role, mobile, profile_id')
        .eq('mobile', testMobile);

      if (lookupRes.error) {
        deniedRequests.push({ op: 'lookup_users', role: item.role, error: lookupRes.error });
      } else {
        successfulRequests.push({ op: 'lookup_users', role: item.role });
      }

      // 2. Profile row insert into domain table (using literal table names for static analyzer)
      const profilePayload = {
        [item.idCol]: item.idVal,
        [item.ownerCol]: testUid,
        status: 'pending',
        verified: false,
      };

      let profileInsertRes;
      if (item.table === 'patients') {
        profileInsertRes = await client.from('patients').insert(profilePayload);
      } else if (item.table === 'doctors') {
        profileInsertRes = await client.from('doctors').insert(profilePayload);
      } else if (item.table === 'labs') {
        profileInsertRes = await client.from('labs').insert(profilePayload);
      } else if (item.table === 'medical_stores') {
        profileInsertRes = await client.from('medical_stores').insert(profilePayload);
      } else if (item.table === 'ambulances') {
        profileInsertRes = await client.from('ambulances').insert(profilePayload);
      }

      if (profileInsertRes.error) {
        deniedRequests.push({ op: 'insert_profile', table: item.table, role: item.role, error: profileInsertRes.error });
      } else {
        successfulRequests.push({ op: 'insert_profile', table: item.table, role: item.role });
      }

      // 3. User account insert into public.users
      const userPayload = {
        id: testUid,
        firebase_uid: testUid,
        role: item.role === 'medicalStore' ? 'medical_store' : item.role,
        mobile: testMobile,
        profile_id: item.idVal,
        verified: false,
      };
      const userInsertRes = await client
        .from('users')
        .insert(userPayload);

      if (userInsertRes.error) {
        deniedRequests.push({ op: 'insert_users', role: item.role, error: userInsertRes.error });
      } else {
        successfulRequests.push({ op: 'insert_users', role: item.role });
      }

      // 4. Verification approval update on domain table (using literal table names)
      const approvePayload = { verified: true, status: 'active', updated_at: new Date().toISOString() };
      let profileApproveRes;
      if (item.table === 'patients') {
        profileApproveRes = await client.from('patients').update(approvePayload).eq(item.idCol, item.idVal);
      } else if (item.table === 'doctors') {
        profileApproveRes = await client.from('doctors').update(approvePayload).eq(item.idCol, item.idVal);
      } else if (item.table === 'labs') {
        profileApproveRes = await client.from('labs').update(approvePayload).eq(item.idCol, item.idVal);
      } else if (item.table === 'medical_stores') {
        profileApproveRes = await client.from('medical_stores').update(approvePayload).eq(item.idCol, item.idVal);
      } else if (item.table === 'ambulances') {
        profileApproveRes = await client.from('ambulances').update(approvePayload).eq(item.idCol, item.idVal);
      }

      if (profileApproveRes.error) {
        deniedRequests.push({ op: 'approve_profile', table: item.table, role: item.role, error: profileApproveRes.error });
      } else {
        successfulRequests.push({ op: 'approve_profile', table: item.table, role: item.role });
      }

      // 5. Verification approval update on public.users
      const userApproveRes = await client
        .from('users')
        .update({ verified: true, updated_at: new Date().toISOString() })
        .eq('id', testUid);

      if (userApproveRes.error) {
        deniedRequests.push({ op: 'approve_users', role: item.role, error: userApproveRes.error });
      } else {
        successfulRequests.push({ op: 'approve_users', role: item.role });
      }

      // 6. Device token registration on user_devices
      const deviceRes = await client
        .from('user_devices')
        .insert({
          user_id: testUid,
          platform: 'android',
          fcm_token: `fcm_${item.role}_token`,
          updated_at: new Date().toISOString(),
        });

      if (deviceRes.error) {
        deniedRequests.push({ op: 'register_device', role: item.role, error: deviceRes.error });
      } else {
        successfulRequests.push({ op: 'register_device', role: item.role });
      }
    }

    // Assert that ZERO requests were denied or errored
    assert.strictEqual(
      deniedRequests.length,
      0,
      `Expected zero denied requests during production provisioning, but got: ${JSON.stringify(deniedRequests, null, 2)}`
    );

    // Assert that all operations succeeded through the gateway
    assert.strictEqual(successfulRequests.length, rolesToTest.length * 6);
    assert.strictEqual(receivedPostgrestRequests.length, rolesToTest.length * 6);

    // Verify all proxied requests carried valid service_role authorization
    for (const req of receivedPostgrestRequests) {
      assert.ok(req.headers.authorization, 'Expected Authorization header in PostgREST request');
      assert.ok(req.headers.authorization.startsWith('Bearer '), 'Expected Bearer JWT token');
    }
  });
});
