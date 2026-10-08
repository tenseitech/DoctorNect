'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  cleanupUserSupabaseRows,
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
