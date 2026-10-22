'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  cleanupUserSupabaseRows,
  cleanupUserRedisKeys,
  setSupabaseFetchForTesting,
} = require('../delete_my_account');

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
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
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

test('TASK 1e: deletes auth.users row via dedicated admin fetch on success', async () => {
  const { toUserUuid } = require('../user_id_bridge');
  const expectedUuid = toUserUuid(UID);
  const calls = [];

  setSupabaseFetchForTesting(async (url, options) => {
    calls.push({ url, method: options.method, headers: options.headers });
    if (url.includes('/auth/v1/admin/users/')) {
      return { ok: true, status: 200, text: async () => '{}' };
    }
    return { ok: true, status: 200, text: async () => '[]' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, false);
  assert.ok(!result.failedSupabaseTables.includes('auth.users'), 'auth.users should not be in failedSupabaseTables on success');

  const authCall = calls.find((c) => c.url.includes('/auth/v1/admin/users/'));
  assert.ok(authCall, 'Dedicated fetch to /auth/v1/admin/users/ must be made');
  assert.equal(authCall.method, 'DELETE');
  assert.equal(authCall.url, `https://example.supabase.co/auth/v1/admin/users/${expectedUuid}`);
  assert.equal(authCall.headers.Authorization, 'Bearer service-role-test');
});

test('TASK 1e: treats 404 on auth.users deletion as success (user without auth row)', async () => {
  let authCalled = false;

  setSupabaseFetchForTesting(async (url, options) => {
    if (url.includes('/auth/v1/admin/users/')) {
      authCalled = true;
      return { ok: false, status: 404, text: async () => '{"message":"User not found"}' };
    }
    return { ok: true, status: 200, text: async () => '[]' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, false);
  assert.equal(authCalled, true);
  assert.ok(!result.failedSupabaseTables.includes('auth.users'), '404 must be treated as success, not failure');
});

test('TASK 1e: surfaces 500 on auth.users deletion in failedSupabaseTables', async () => {
  setSupabaseFetchForTesting(async (url, options) => {
    if (url.includes('/auth/v1/admin/users/')) {
      return { ok: false, status: 500, text: async () => '{"message":"Internal Server Error"}' };
    }
    return { ok: true, status: 200, text: async () => '[]' };
  });

  const result = await cleanupUserSupabaseRows({ uid: UID, role: 'patient', profileId: PATIENT_ID });
  assert.equal(result.skipped, false);
  assert.ok(result.failedSupabaseTables.includes('auth.users'), '500 on auth.users must be surfaced in failedSupabaseTables');
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
