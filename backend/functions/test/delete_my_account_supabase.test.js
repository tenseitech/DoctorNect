'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
if (!getApps().length) initializeApp({ projectId: 'demo-delete-test' });

const {
  cleanupUserSupabaseRows,
  cleanupUserRedisKeys,
  deleteMyAccountHandler,
  setSupabaseFetchForTesting,
  getSupabaseServiceConfig,
} = require('../delete_my_account');
const { getDatabaseClient, resetDatabaseClientForTesting } = require('../src/db/client');
const { setSupabaseClientForTesting } = require('../caller_identity');

const UID = 'firebase_uid_patient_1';
const USER_UUID = '11111111-2222-3333-4444-555555555555';
const PATIENT_ID = 'pat_abc';
const PRESC_ID = 'rx_1';

beforeEach(() => {
  process.env.SUPABASE_URL = 'https://example.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-test';
});

afterEach(() => {
  setSupabaseFetchForTesting(null);
  setSupabaseClientForTesting(null);
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  delete process.env.FIRESTORE_FORBIDDEN;
  delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
});

test('cleanupUserSupabaseRows skips when secrets are absent', async () => {
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  let called = false;
  setSupabaseFetchForTesting(async () => {
    called = true;
    return { ok: true, text: async () => '[]' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, true);
  assert.equal(called, false);
  assert.deepEqual(result.failedSupabaseTables, []);
});

test('cleanupUserSupabaseRows deletes patient graph using real table/column names', async () => {
  const calls = [];
  setSupabaseFetchForTesting(async (url, options) => {
    calls.push({ url, method: options.method, body: options.body });
    const path = url.replace('https://example.supabase.co/rest/v1/', '');
    if (path.startsWith('users?firebase_uid=') && options.method === 'GET') {
      return {
        ok: true,
        text: async () => JSON.stringify([{ id: USER_UUID, profile_id: PATIENT_ID, role: 'patient' }]),
      };
    }
    if (path.startsWith('patients?owner_uid=') && options.method === 'GET') {
      return { ok: true, text: async () => JSON.stringify([{ patient_id: PATIENT_ID }]) };
    }
    if (path.startsWith('doctors?') || path.startsWith('medical_stores?') || path.startsWith('labs?') || path.startsWith('ambulances?')) {
      return { ok: true, text: async () => '[]' };
    }
    if (path.startsWith('prescriptions?patient_id=') && options.method === 'GET') {
      return { ok: true, text: async () => JSON.stringify([{ prescription_id: PRESC_ID }]) };
    }
    return { ok: true, status: 200, text: async () => '[]' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, false);
  assert.deepEqual(result.failedSupabaseTables, []);

  const paths = calls.map((c) => `${c.method} ${c.url}`);
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/prescription_medicines?prescription_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/prescription_investigations?prescription_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/prescription_referrals?prescription_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/prescriptions?prescription_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/health_records?patient_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/family_members?patient_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/reviews?patient_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/appointments?patient_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes('/patients?patient_id=eq.')));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes(`/user_devices?user_id=eq.${USER_UUID}`)));
  assert.ok(paths.some((p) => p.includes('PATCH') && p.includes(`/razorpay_orders?user_uid=eq.${UID}`)));
  assert.ok(paths.some((p) => p.includes('DELETE') && p.includes(`/users?firebase_uid=eq.${UID}`)));
  assert.equal(paths.some((p) => p.includes(process.env.SUPABASE_SERVICE_ROLE_KEY) && p.includes('https://')), false);

  // Assert views patient_safe and doctor_directory are NEVER deleted
  assert.equal(paths.some((p) => p.includes('/patient_safe')), false, 'Views must not be in delete order');
  assert.equal(paths.some((p) => p.includes('/doctor_directory')), false, 'Views must not be in delete order');

  // Assert auth/v1/admin/users is NEVER called
  assert.equal(paths.some((p) => p.includes('/auth/v1/admin/users')), false, 'Supabase Auth admin must not be called');
});

test('cleanupUserSupabaseRows records table failures without throwing', async () => {
  setSupabaseFetchForTesting(async (url) => {
    if (url.includes('/users?firebase_uid=')) {
      return {
        ok: true,
        text: async () => JSON.stringify([{ id: USER_UUID, profile_id: PATIENT_ID, role: 'patient' }]),
      };
    }
    return { ok: false, status: 500, text: async () => '{"error":"boom"}' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, false);
  assert.ok(result.failedSupabaseTables.length > 0);
});

test('deleteMyAccountHandler runs with FIRESTORE_FORBIDDEN=1 without touching Firestore', async () => {
  process.env.FIRESTORE_FORBIDDEN = '1';
  delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;

  let firebaseAuthDeleted = false;
  // Mock Firebase Admin getAuth
  const { getAuth } = require('firebase-admin/auth');
  const authInstance = getAuth();
  const origDeleteUser = authInstance.deleteUser;
  authInstance.deleteUser = async (uid) => {
    assert.equal(uid, UID);
    firebaseAuthDeleted = true;
    return {};
  };

  // Mock Supabase service role client for caller_identity
  const mockSupabase = {
    from: (table) => {
      if (table === 'users') {
        return {
          select: () => ({
            or: () => ({
              maybeSingle: async () => ({
                data: {
                  id: UID,
                  firebase_uid: UID,
                  role: 'patient',
                  profile_id: PATIENT_ID,
                  email: 'patient@example.com',
                  mobile: '9876543210',
                },
                error: null,
              }),
            }),
          }),
        };
      }
      throw new Error('Unexpected table ' + table);
    },
  };
  setSupabaseClientForTesting(mockSupabase);

  // Mock Supabase fetch for row cleanup
  setSupabaseFetchForTesting(async () => {
    return { ok: true, status: 200, text: async () => '[]' };
  });

  try {
    const result = await deleteMyAccountHandler(UID);
    assert.equal(result.ok, true);
    assert.equal(result.supabase, true);
    assert.equal(firebaseAuthDeleted, true, 'Firebase Auth user must be deleted last');
  } finally {
    authInstance.deleteUser = origDeleteUser;
  }
});

test('cleanupUserRedisKeys removes keys when OTP_REDIS_MIRROR is on', async () => {
  process.env.OTP_REDIS_MIRROR = 'on';
  const deletedKeys = [];
  const { setRedisClientForTesting } = require('../redis');
  setRedisClientForTesting({
    del: async (k) => {
      deletedKeys.push(k);
      return 1;
    },
  });

  try {
    await cleanupUserRedisKeys({ mobileDigits: '9876543210', role: 'patient' });
    assert.ok(deletedKeys.length > 0);
    assert.ok(deletedKeys.some((k) => k.includes('9876543210')));
  } finally {
    delete process.env.OTP_REDIS_MIRROR;
    setRedisClientForTesting(null);
  }
});

test('with APP_ENV=production, delete_my_account and getDatabaseClient route to PROD_GATEWAY and strictly ignore STAGING_SUPABASE', async () => {
  process.env.APP_ENV = 'production';
  process.env.PROD_GATEWAY_URL = 'https://api.doctornect.com';
  process.env.PROD_GATEWAY_SERVICE_KEY = 'prod-gateway-service-secret-key';
  process.env.STAGING_SUPABASE_URL = 'https://staging.supabase.co';
  process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY = 'staging-supabase-key';
  process.env.SUPABASE_URL = 'https://legacy-staging.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'legacy-staging-key';

  resetDatabaseClientForTesting();

  // 1. Verify getSupabaseServiceConfig() uses PROD_GATEWAY
  const config = getSupabaseServiceConfig();
  assert.equal(config.isProduction, true);
  assert.equal(config.url, 'https://api.doctornect.com');
  assert.equal(config.key, 'prod-gateway-service-secret-key');

  // 2. Verify cleanupUserSupabaseRows strictly makes requests to PROD_GATEWAY_URL
  const calls = [];
  setSupabaseFetchForTesting(async (url, options) => {
    calls.push({ url, headers: options.headers });
    return { ok: true, status: 200, text: async () => '[]' };
  });

  await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.ok(calls.length > 0);
  for (const c of calls) {
    assert.ok(c.url.startsWith('https://api.doctornect.com/rest/v1/'), `Expected URL to target production gateway, got: ${c.url}`);
    assert.ok(!c.url.includes('staging.supabase.co'), `Staging URL must NEVER be contacted in production! URL: ${c.url}`);
    assert.equal(c.headers.apikey, 'prod-gateway-service-secret-key');
  }

  // 3. Verify getDatabaseClient() targets PROD_GATEWAY_URL
  const client = getDatabaseClient();
  assert.equal(client.supabaseUrl, 'https://api.doctornect.com');

  // 4. In production, if PROD_GATEWAY_URL is missing, getDatabaseClient strictly throws and refuses to fall back to staging
  delete process.env.PROD_GATEWAY_URL;
  resetDatabaseClientForTesting();
  assert.throws(
    () => getDatabaseClient({ forceNew: true }),
    /Missing required credentials for APP_ENV="production": PROD_GATEWAY_URL/
  );

  // Clean up
  delete process.env.APP_ENV;
  delete process.env.PROD_GATEWAY_URL;
  delete process.env.PROD_GATEWAY_SERVICE_KEY;
  delete process.env.STAGING_SUPABASE_URL;
  delete process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY;
  resetDatabaseClientForTesting();
});

test('Integration: cleanupUserSupabaseRows runs against mock gateway built from config.js with zero denied requests', async () => {
  const gatewayConfig = require('../../../services/api-gateway/src/config');
  const serviceRoleAllowedTables = new Set(gatewayConfig.serviceRoleAllowedTables);
  assert.ok(serviceRoleAllowedTables.size > 0);

  const deniedCalls = [];
  const allowedCalls = [];

  setSupabaseFetchForTesting(async (url, options) => {
    // URL format: https://example.supabase.co/rest/v1/<tableAndQuery>
    const fullPath = url.replace('https://example.supabase.co/rest/v1/', '');
    const tableName = fullPath.split('?')[0];

    if (!serviceRoleAllowedTables.has(tableName)) {
      deniedCalls.push({ table: tableName, url, method: options.method });
      return {
        ok: false,
        status: 404,
        text: async () => JSON.stringify({ error: 'Not Found', message: `Table ${tableName} not in serviceRoleAllowedTables` }),
      };
    }

    allowedCalls.push({ table: tableName, url, method: options.method });

    // Mock minimal responses for GET queries so traversal discovers dependent entities
    if (tableName === 'users' && options.method === 'GET') {
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify([{ id: 'uuid-1234', profile_id: 'prof-1234', role: 'patient' }]),
      };
    }
    if (options.method === 'GET') {
      return { ok: true, status: 200, text: async () => JSON.stringify([{ [`${tableName.slice(0, -1)}_id`]: 'id-1' }]) };
    }

    return { ok: true, status: 200, text: async () => '[]' };
  });

  // Test cleanup for all account roles
  const testRoles = [
    { role: 'patient', profileId: 'pat_test_1' },
    { role: 'doctor', profileId: 'doc_test_1' },
    { role: 'medicalStore', profileId: 'store_test_1' },
    { role: 'lab', profileId: 'lab_test_1' },
    { role: 'ambulance', profileId: 'amb_test_1' },
  ];

  for (const { role, profileId } of testRoles) {
    const res = await cleanupUserSupabaseRows({
      uid: `uid_${role}`,
      role,
      profileId,
    });

    assert.equal(res.skipped, false);
    assert.deepEqual(res.failedSupabaseTables, [], `Expected 0 failed tables for role ${role}`);
  }

  // Assert ZERO denied requests across all roles and all traversed tables
  assert.equal(deniedCalls.length, 0, `Expected zero denied calls, but got: ${JSON.stringify(deniedCalls)}`);
  assert.ok(allowedCalls.length > 20, `Expected extensive table traversal, got ${allowedCalls.length} calls`);

  // Verify that if an unallowlisted table is accessed, it fails loudly and throws
  setSupabaseFetchForTesting(async (url) => {
    return {
      ok: false,
      status: 404,
      text: async () => JSON.stringify({ error: 'Not Found' }),
    };
  });

  await assert.rejects(
    () => cleanupUserSupabaseRows({ uid: 'uid_test', role: 'patient', profileId: 'pat_1' }),
    (err) => err.status === 404
  );
});

