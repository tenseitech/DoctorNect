'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const {
  syncFirestoreUserToSupabase,
  buildUserSupabasePayload,
  normalizeRole,
  toUserUuid: crossRoleToUserUuid,
} = require('../cross_role_sync');
const { toUserUuid, DOCTORNECT_NAMESPACE } = require('../user_id_bridge');

const realFetch = global.fetch;

function withFakeSupabase(run) {
  const prevUrl = process.env.SUPABASE_URL;
  const prevKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.SUPABASE_URL = 'https://example.invalid';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-key';
  return Promise.resolve()
    .then(run)
    .finally(() => {
      global.fetch = realFetch;
      if (prevUrl === undefined) delete process.env.SUPABASE_URL;
      else process.env.SUPABASE_URL = prevUrl;
      if (prevKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
      else process.env.SUPABASE_SERVICE_ROLE_KEY = prevKey;
    });
}

test('normalizeRole maps variants to schema-supported canonical roles', () => {
  assert.equal(normalizeRole('patient'), 'patient');
  assert.equal(normalizeRole('doctor'), 'doctor');
  assert.equal(normalizeRole('medical'), 'medicalStore');
  assert.equal(normalizeRole('medicalStore'), 'medicalStore');
  assert.equal(normalizeRole('pharmacy'), 'medicalStore');
  assert.equal(normalizeRole('lab'), 'lab');
  assert.equal(normalizeRole('ambulance'), 'ambulance');
  assert.equal(normalizeRole('super_admin'), 'superAdmin');
  assert.equal(normalizeRole('superadmin'), 'superAdmin');
  assert.equal(normalizeRole('admin'), 'admin');
});

test('buildUserSupabasePayload builds valid public.users row', () => {
  const payload = buildUserSupabasePayload('fb_uid_123', {
    role: 'medical',
    profileId: 'store_456',
    displayName: 'City Pharmacy',
    mobile: '+91 9876543210',
    email: 'test@pharmacy.com',
    profileCompleted: true,
    verified: true,
    status: 'approved',
    createdAt: '2026-01-01T10:00:00.000Z',
    updatedAt: '2026-01-01T10:00:00.000Z',
  });

  assert.equal(payload.skip, false);
  assert.equal(payload.row.firebase_uid, 'fb_uid_123');
  assert.equal(payload.row.role, 'medicalStore');
  assert.equal(payload.row.profile_id, 'store_456');
  assert.equal(payload.row.display_name, 'City Pharmacy');
  assert.equal(payload.row.email, 'test@pharmacy.com');
  assert.equal(payload.row.mobile, '9876543210');
  assert.equal(payload.row.profile_completed, true);
  assert.equal(payload.row.verified, true);
  assert.equal(payload.row.status, 'approved');
});

test('Loop Prevention: Drops user writes marked with syncedBy: supabase_bridge', async () => {
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return { ok: true };
  };

  const fakeEvent = {
    params: { uid: 'user_loop_test' },
    data: {
      after: {
        exists: true,
        data: () => ({
          role: 'patient',
          profileId: 'pat_1',
          syncedBy: 'supabase_bridge',
        }),
      },
    },
  };

  await syncFirestoreUserToSupabase(fakeEvent);
  assert.equal(fetchCalled, false, 'Fetch should not be called when syncedBy is supabase_bridge');
});

test('User Bridge: Create inserts new public.users row with UUID and firebase_uid', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });

      if (u.includes('select=updated_at')) {
        return { ok: true, json: async () => [] };
      }
      if (u.includes('select=id')) {
        return { ok: true, json: async () => [] }; // User doesn't exist yet
      }
      if (u.includes('/rest/v1/users') && method === 'POST') {
        return { ok: true, text: async () => JSON.stringify(body) };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };

    const fakeEvent = {
      params: { uid: 'uid_create_123' },
      data: {
        after: {
          exists: true,
          id: 'uid_create_123',
          data: () => ({
            role: 'patient',
            profileId: 'pat_create_123',
            name: 'Priya Sharma',
            mobile: '9876543210',
            createdAt: '2026-02-01T00:00:00.000Z',
            updatedAt: '2026-02-01T00:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreUserToSupabase(fakeEvent);
  });

  const postCall = calls.find((c) => c.method === 'POST' && c.url.includes('/rest/v1/users'));
  assert.ok(postCall, 'Must perform POST /rest/v1/users');
  assert.equal(postCall.body.firebase_uid, 'uid_create_123');
  assert.equal(postCall.body.role, 'patient');
  assert.equal(postCall.body.profile_id, 'pat_create_123');
  assert.equal(postCall.body.display_name, 'Priya Sharma');
  assert.equal(postCall.body.mobile, '9876543210');
  assert.ok(postCall.body.id, 'Must generate id UUID on insert');
  assert.equal(postCall.body.id, toUserUuid('uid_create_123'), 'Must use deterministic toUserUuid');
  assert.match(
    postCall.body.id,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    'id must be a valid UUID',
  );
});

test('User Bridge: Update PATCHes existing public.users row keyed on firebase_uid', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });

      if (u.includes('select=updated_at')) {
        return { ok: true, json: async () => [{ updated_at: '2026-01-01T00:00:00.000Z' }] };
      }
      if (u.includes('select=id')) {
        return { ok: true, json: async () => [{ id: 'existing-uuid-999' }] }; // Exists
      }
      if (u.includes('/rest/v1/users') && method === 'PATCH') {
        return { ok: true, text: async () => JSON.stringify(body) };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };

    const fakeEvent = {
      params: { uid: 'uid_update_123' },
      data: {
        after: {
          exists: true,
          id: 'uid_update_123',
          data: () => ({
            role: 'doctor',
            profileId: 'doc_update_123',
            name: 'Dr. Ananya Roy',
            mobile: '9876543211',
            updatedAt: '2026-03-01T00:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreUserToSupabase(fakeEvent);
  });

  const patchCall = calls.find((c) => c.method === 'PATCH' && c.url.includes('/rest/v1/users'));
  assert.ok(patchCall, 'Must perform PATCH /rest/v1/users');
  assert.ok(patchCall.url.includes('firebase_uid=eq.uid_update_123'));
  assert.equal(patchCall.body.role, 'doctor');
  assert.equal(patchCall.body.profile_id, 'doc_update_123');
  assert.equal(patchCall.body.display_name, 'Dr. Ananya Roy');
  assert.equal(patchCall.body.mobile, '9876543211');
});

test('User Bridge: Role change updates normalized role in Supabase', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });

      if (u.includes('select=updated_at')) {
        return { ok: true, json: async () => [{ updated_at: '2026-01-01T00:00:00.000Z' }] };
      }
      if (u.includes('select=id')) {
        return { ok: true, json: async () => [{ id: 'role-change-uuid' }] };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };

    const fakeEvent = {
      params: { uid: 'uid_role_change' },
      data: {
        before: {
          exists: true,
          data: () => ({ role: 'patient', profileId: 'pat_1' }),
        },
        after: {
          exists: true,
          id: 'uid_role_change',
          data: () => ({
            role: 'pharmacy', // Legacy alias for medicalStore
            profileId: 'store_1',
            name: 'Metro Pharmacy',
            updatedAt: '2026-04-01T00:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreUserToSupabase(fakeEvent);
  });

  const patchCall = calls.find((c) => c.method === 'PATCH' && c.url.includes('/rest/v1/users'));
  assert.ok(patchCall, 'Must perform PATCH /rest/v1/users for role change');
  assert.equal(patchCall.body.role, 'medicalStore', 'Role "pharmacy" must normalize to "medicalStore"');
  assert.equal(patchCall.body.profile_id, 'store_1');
});

test('User Bridge: Deletion triggers deleteMyAccount Supabase cleanup policy', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      calls.push({ url: u, method });

      if (u.includes('users?firebase_uid=eq.uid_delete_123') && method === 'GET') {
        return {
          ok: true,
          text: async () => JSON.stringify([{ id: 'uuid-del', profile_id: 'pat_del', role: 'patient' }]),
        };
      }
      return { ok: true, text: async () => JSON.stringify([]) };
    };

    const fakeEvent = {
      params: { uid: 'uid_delete_123' },
      data: {
        before: {
          exists: true,
          id: 'uid_delete_123',
          data: () => ({ role: 'patient', profileId: 'pat_del' }),
        },
        after: {
          exists: false,
        },
      },
    };

    await syncFirestoreUserToSupabase(fakeEvent);
  });

  const deleteCalls = calls.filter((c) => c.method === 'DELETE');
  assert.ok(deleteCalls.length > 0, 'Must trigger DELETE operations for child tables and users row');
  assert.ok(
    deleteCalls.some((c) => c.url.includes('users?firebase_uid=eq.uid_delete_123')),
    'Must issue DELETE on users?firebase_uid',
  );
});

test('User Bridge: Repeated invocation is idempotent (skips stale or identical updatedAt)', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      calls.push({ url: u, method });

      if (u.includes('select=updated_at')) {
        // Remote is already at 2026-05-01T00:00:00.000Z
        return { ok: true, json: async () => [{ updated_at: '2026-05-01T00:00:00.000Z' }] };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };

    const fakeEvent = {
      params: { uid: 'uid_idempotent' },
      data: {
        after: {
          exists: true,
          id: 'uid_idempotent',
          data: () => ({
            role: 'patient',
            profileId: 'pat_idempotent',
            updatedAt: '2026-05-01T00:00:00.000Z', // Same timestamp
          }),
        },
      },
    };

    // First call with matching remote timestamp
    await syncFirestoreUserToSupabase(fakeEvent);
    // Second call with older remote timestamp
    await syncFirestoreUserToSupabase({
      params: { uid: 'uid_idempotent' },
      data: {
        after: {
          exists: true,
          id: 'uid_idempotent',
          data: () => ({
            role: 'patient',
            profileId: 'pat_idempotent',
            updatedAt: '2026-04-01T00:00:00.000Z', // Stale
          }),
        },
      },
    });
  });

  const writeCalls = calls.filter((c) => c.method === 'POST' || c.method === 'PATCH');
  assert.equal(writeCalls.length, 0, 'No write should happen for stale or already applied snapshot');
});

test('User ID Bridge: toUserUuid produces deterministic RFC 4122 v5 UUID and parity with migration script', () => {
  const uid1 = 'sample_firebase_uid_12345';
  const uuid1 = toUserUuid(uid1);
  const uuid2 = toUserUuid(uid1);

  // Determinism
  assert.equal(uuid1, uuid2, 'Repeated calls with same uid must produce identical UUID');
  assert.match(
    uuid1,
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    'Must be valid RFC 4122 UUID v5 (version 5, variant 1)'
  );

  // Parity with cross_role_sync exported helper
  assert.equal(crossRoleToUserUuid(uid1), uuid1, 'cross_role_sync toUserUuid must produce identical UUID');

  // Verify migration script imports and uses the shared helper
  const migrateScriptPath = path.resolve(__dirname, '../../scripts/migrate_firestore_to_supabase.js');
  const scriptContent = fs.readFileSync(migrateScriptPath, 'utf8');
  assert.ok(
    scriptContent.includes("require('../functions/user_id_bridge')"),
    'migrate_firestore_to_supabase.js must require user_id_bridge'
  );

  // Edge cases
  assert.equal(toUserUuid(''), null);
  assert.equal(toUserUuid(null), null);
  assert.equal(toUserUuid(undefined), null);
});

test('User Bridge: Two sequential invocations for the same firebase_uid never create two rows', async () => {
  const targetUid = 'uid_double_invocation_test';
  const expectedUuid = toUserUuid(targetUid);

  // Mock database storage
  const mockDatabase = new Map();
  const recordedCalls = [];

  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      recordedCalls.push({ url: u, method, body });

      if (u.includes('select=updated_at')) {
        const existing = mockDatabase.get(targetUid);
        if (existing) {
          return { ok: true, json: async () => [{ updated_at: existing.updated_at }] };
        }
        return { ok: true, json: async () => [] };
      }

      if (u.includes('select=id')) {
        const existing = mockDatabase.get(targetUid);
        if (existing) {
          return { ok: true, json: async () => [{ id: existing.id }] };
        }
        return { ok: true, json: async () => [] };
      }

      if (u.includes('/rest/v1/users') && method === 'POST') {
        assert.ok(u.includes('on_conflict=firebase_uid'), 'POST must specify on_conflict=firebase_uid');
        assert.equal(opts.headers.Prefer, 'resolution=merge-duplicates,return=minimal');
        mockDatabase.set(targetUid, body);
        return { ok: true, text: async () => JSON.stringify(body) };
      }

      if (u.includes('/rest/v1/users') && method === 'PATCH') {
        assert.ok(u.includes(`firebase_uid=eq.${targetUid}`), 'PATCH must target firebase_uid');
        const existing = mockDatabase.get(targetUid) || {};
        const updated = { ...existing, ...body };
        mockDatabase.set(targetUid, updated);
        return { ok: true, text: async () => JSON.stringify(updated) };
      }

      return { ok: true, json: async () => [], text: async () => '' };
    };

    // First invocation: User does not exist in Supabase yet (initial creation)
    const eventCreate = {
      params: { uid: targetUid },
      data: {
        after: {
          exists: true,
          id: targetUid,
          data: () => ({
            role: 'patient',
            profileId: 'pat_initial',
            name: 'First Sync',
            mobile: '9876543210',
            createdAt: '2026-06-01T10:00:00.000Z',
            updatedAt: '2026-06-01T10:00:00.000Z',
          }),
        },
      },
    };
    await syncFirestoreUserToSupabase(eventCreate);

    // Second invocation: User is updated in Firestore (profile update with newer updatedAt)
    const eventUpdate = {
      params: { uid: targetUid },
      data: {
        after: {
          exists: true,
          id: targetUid,
          data: () => ({
            role: 'patient',
            profileId: 'pat_initial',
            name: 'Updated Sync Name',
            mobile: '9876543210',
            createdAt: '2026-06-01T10:00:00.000Z',
            updatedAt: '2026-06-01T11:00:00.000Z',
          }),
        },
      },
    };
    await syncFirestoreUserToSupabase(eventUpdate);
  });

  const postCalls = recordedCalls.filter((c) => c.method === 'POST');
  const patchCalls = recordedCalls.filter((c) => c.method === 'PATCH');

  // Verify: Exactly 1 POST and 1 PATCH, NEVER 2 POSTs (never creates 2 rows)
  assert.equal(postCalls.length, 1, 'First invocation must perform exactly one POST');
  assert.equal(patchCalls.length, 1, 'Second invocation must perform PATCH, not a second POST');
  assert.equal(postCalls[0].body.id, expectedUuid, 'Insert row must use deterministic toUserUuid');
  assert.equal(mockDatabase.size, 1, 'Database must contain exactly 1 row for this user');
  assert.equal(mockDatabase.get(targetUid).id, expectedUuid, 'Stored user ID must remain the deterministic UUID');
  assert.equal(mockDatabase.get(targetUid).display_name, 'Updated Sync Name', 'Second invocation must update data');
});

test('TASK 2b: syncFirestoreUserToSupabase handles email conflict on insert by retrying with synthetic email', async () => {
  const targetUid = 'uid_email_conflict_user';
  const expectedUuid = toUserUuid(targetUid);

  const mockDatabase = new Map();
  const recordedCalls = [];
  let postAttempts = 0;

  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      recordedCalls.push({ url: u, method, body });

      if (u.includes('select=updated_at') || u.includes('select=id')) {
        return { ok: true, json: async () => [] };
      }

      if (u.includes('/rest/v1/users') && method === 'POST') {
        postAttempts++;
        // First attempt with real email fails with 409 users_email_key
        if (postAttempts === 1) {
          return {
            ok: false,
            status: 409,
            text: async () => 'duplicate key value violates unique constraint "users_email_key"',
          };
        }
        // Second attempt with synthetic email succeeds
        mockDatabase.set(targetUid, body);
        return { ok: true, text: async () => JSON.stringify(body) };
      }

      return { ok: true, json: async () => [], text: async () => '' };
    };

    const event = {
      params: { uid: targetUid },
      data: {
        after: {
          exists: true,
          id: targetUid,
          data: () => ({
            role: 'patient',
            profileId: 'pat_conflict',
            name: 'Conflict Patient',
            email: 'duplicate_patient@realcorp.com',
            mobile: '9876543299',
            createdAt: '2026-06-01T10:00:00.000Z',
            updatedAt: '2026-06-01T10:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreUserToSupabase(event);
  });

  assert.equal(postAttempts, 2, 'Should retry POST after 409 email conflict');
  const insertedRow = mockDatabase.get(targetUid);
  assert.ok(insertedRow);
  assert.equal(insertedRow.id, expectedUuid);
  assert.equal(insertedRow.email, 'uid_email_conflict_user@signup.doctornect.app', 'Should use synthetic fallback email');
});

