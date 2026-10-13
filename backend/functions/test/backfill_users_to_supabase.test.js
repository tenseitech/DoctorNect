'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { runBackfill, parseCliArgs } = require('../../scripts/backfill_users_to_supabase');
const { toUserUuid } = require('../user_id_bridge');

// In-Memory Mock Firestore Collection
function createMockFirestore(docs = []) {
  // Sort documents by id to simulate orderBy documentId
  const sorted = [...docs].sort((a, b) => a.id.localeCompare(b.id));

  return {
    collection(colName) {
      assert.equal(colName, 'users');
      return {
        orderBy() {
          return this;
        },
        startAfter(startUid) {
          const idx = sorted.findIndex((d) => d.id === startUid);
          const remaining = idx >= 0 ? sorted.slice(idx + 1) : sorted;
          return {
            limit(n) {
              return {
                async get() {
                  return {
                    empty: remaining.length === 0,
                    docs: remaining.slice(0, n),
                  };
                },
              };
            },
          };
        },
        limit(n) {
          return {
            async get() {
              return {
                empty: sorted.length === 0,
                docs: sorted.slice(0, n),
              };
            },
          };
        },
      };
    },
  };
}

// In-Memory Mock Supabase Store
function createMockSupabase() {
  const store = new Map(); // id -> row
  const calls = [];

  const fakeFetch = async (urlStr, opts = {}) => {
    const url = String(urlStr);
    const method = opts.method || 'GET';
    const body = opts.body ? JSON.parse(opts.body) : null;
    calls.push({ url, method, body });

    // GET by firebase_uid
    if (url.includes('/rest/v1/users?firebase_uid=eq.') && method === 'GET') {
      const match = url.match(/firebase_uid=eq\.([^&]+)/);
      const uid = match ? decodeURIComponent(match[1]) : '';
      const found = Array.from(store.values()).filter((r) => r.firebase_uid === uid);
      return { ok: true, json: async () => found, text: async () => JSON.stringify(found) };
    }

    // GET by id
    if (url.includes('/rest/v1/users?id=eq.') && method === 'GET') {
      const match = url.match(/id=eq\.([^&]+)/);
      const id = match ? decodeURIComponent(match[1]) : '';
      const found = Array.from(store.values()).filter((r) => r.id === id);
      return { ok: true, json: async () => found, text: async () => JSON.stringify(found) };
    }

    // POST insert
    if (url.includes('/rest/v1/users') && method === 'POST') {
      if (store.has(body.id)) {
        return {
          ok: false,
          status: 409,
          text: async () => 'duplicate key value violates unique constraint "users_pkey"',
        };
      }
      store.set(body.id, body);
      return { ok: true, status: 201, text: async () => JSON.stringify(body) };
    }

    // PATCH by firebase_uid
    if (url.includes('/rest/v1/users?firebase_uid=eq.') && method === 'PATCH') {
      const match = url.match(/firebase_uid=eq\.([^&]+)/);
      const uid = match ? decodeURIComponent(match[1]) : '';
      const found = Array.from(store.values()).find((r) => r.firebase_uid === uid);
      if (found) {
        Object.assign(found, body);
      }
      return { ok: true, status: 200, text: async () => JSON.stringify(body) };
    }

    // PATCH by id
    if (url.includes('/rest/v1/users?id=eq.') && method === 'PATCH') {
      const match = url.match(/id=eq\.([^&]+)/);
      const id = match ? decodeURIComponent(match[1]) : '';
      const found = store.get(id);
      if (found) {
        Object.assign(found, body);
      }
      return { ok: true, status: 200, text: async () => JSON.stringify(body) };
    }

    return { ok: true, json: async () => [], text: async () => '[]' };
  };

  return { store, calls, fakeFetch };
}

test('Backfill CLI args parser parses flags properly', () => {
  const parsed = parseCliArgs([
    '--apply',
    '--project', 'test-medibond',
    '--start-after', 'uid_50',
    '--limit', '200',
    '--batch-size', '25',
  ]);

  assert.equal(parsed.apply, true);
  assert.equal(parsed.project, 'test-medibond');
  assert.equal(parsed.startAfter, 'uid_50');
  assert.equal(parsed.limit, 200);
  assert.equal(parsed.batchSize, 25);
});

test('Backfill: Dry-run by default executes zero writes', async () => {
  const testDocs = [
    {
      id: 'uid_pat_1',
      data: () => ({
        role: 'patient',
        profileId: 'pat_1',
        name: 'Patient One',
        mobile: '9876543210',
        email: 'p1@example.com',
      }),
    },
    {
      id: 'uid_doc_2',
      data: () => ({
        role: 'doctor',
        profileId: 'doc_2',
        name: 'Doctor Two',
        mobile: '9876543211',
      }),
    },
  ];

  const mockDb = createMockFirestore(testDocs);
  const mockSupa = createMockSupabase();
  const logs = [];

  const counts = await runBackfill({
    apply: false,
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    logger: (msg) => logs.push(msg),
  });

  assert.equal(counts.scanned, 2);
  assert.equal(counts.created, 2);
  assert.equal(counts.updated, 0);
  assert.equal(counts.skipped, 0);
  assert.equal(counts.failed, 0);

  // Assert NO writes occurred to Supabase
  const writeCalls = mockSupa.calls.filter((c) => c.method === 'POST' || c.method === 'PATCH');
  assert.equal(writeCalls.length, 0, 'Dry-run must issue zero POST or PATCH write requests');
  assert.equal(mockSupa.store.size, 0, 'Dry-run must not modify store');
});

test('Backfill: Refuses --apply without explicit --project argument', async () => {
  const mockDb = createMockFirestore([]);
  await assert.rejects(
    async () => {
      await runBackfill({
        apply: true,
        project: null,
        firestoreDb: mockDb,
        adminApp: { options: { projectId: 'my-project' } },
      });
    },
    /Refusing to run --apply: An explicit --project <id> argument is strictly required/
  );
});

test('Backfill: Refuses --apply on --project mismatch with Admin SDK projectId', async () => {
  const mockDb = createMockFirestore([]);
  await assert.rejects(
    async () => {
      await runBackfill({
        apply: true,
        project: 'staging-wrong-project',
        firestoreDb: mockDb,
        adminApp: { options: { projectId: 'medibond-production' } },
      });
    },
    /Refusing to run --apply: --project argument.*does not match initialized Admin SDK/
  );
});

test('Backfill: Apply mode writes users to Supabase and handles pagination and skips', async () => {
  const testDocs = [
    {
      id: 'uid_pat_1',
      data: () => ({
        role: 'patient',
        profileId: 'pat_1',
        name: 'Patient One',
        mobile: '9876543210',
      }),
    },
    {
      id: 'uid_skip_2',
      data: () => ({
        role: 'invalid_hacker_role', // Invalid role -> will be skipped
        profileId: 'unknown_2',
      }),
    },
    {
      id: 'uid_doc_3',
      data: () => ({
        role: 'doctor',
        profileId: 'doc_3',
        name: 'Dr. Three',
        mobile: '9876543212',
      }),
    },
  ];

  const mockDb = createMockFirestore(testDocs);
  const mockSupa = createMockSupabase();
  const logs = [];

  const counts = await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    batchSize: 2, // Test pagination across multiple pages
    logger: (msg) => logs.push(msg),
  });

  assert.equal(counts.scanned, 3);
  assert.equal(counts.created, 2);
  assert.equal(counts.updated, 0);
  assert.equal(counts.skipped, 1, 'Invalid role must be counted as skipped');
  assert.equal(counts.failed, 0);

  assert.equal(mockSupa.store.size, 2);
  const user1 = mockSupa.store.get(toUserUuid('uid_pat_1'));
  assert.ok(user1);
  assert.equal(user1.firebase_uid, 'uid_pat_1');
  assert.equal(user1.role, 'patient');

  const user3 = mockSupa.store.get(toUserUuid('uid_doc_3'));
  assert.ok(user3);
  assert.equal(user3.firebase_uid, 'uid_doc_3');
  assert.equal(user3.role, 'doctor');
});

test('Backfill: Resume via --start-after skips earlier documents', async () => {
  const testDocs = [
    { id: 'uid_a', data: () => ({ role: 'patient', profileId: 'p_a', name: 'User A' }) },
    { id: 'uid_b', data: () => ({ role: 'patient', profileId: 'p_b', name: 'User B' }) },
    { id: 'uid_c', data: () => ({ role: 'patient', profileId: 'p_c', name: 'User C' }) },
  ];

  const mockDb = createMockFirestore(testDocs);
  const mockSupa = createMockSupabase();

  const counts = await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    startAfter: 'uid_a', // Resume after uid_a -> only uid_b and uid_c
    logger: () => {},
  });

  assert.equal(counts.scanned, 2);
  assert.equal(counts.created, 2);
  assert.equal(mockSupa.store.size, 2);
  assert.equal(mockSupa.store.has(toUserUuid('uid_a')), false);
  assert.equal(mockSupa.store.has(toUserUuid('uid_b')), true);
  assert.equal(mockSupa.store.has(toUserUuid('uid_c')), true);
});

test('Backfill: Conflict handling updates existing row when deterministic ID already exists with missing/different firebase_uid', async () => {
  const targetUid = 'uid_conflict_migration_user';
  const deterministicId = toUserUuid(targetUid);

  const mockDb = createMockFirestore([
    {
      id: targetUid,
      data: () => ({
        role: 'patient',
        profileId: 'pat_relinked',
        name: 'Relinked Name',
        mobile: '9876543299',
      }),
    },
  ]);

  const mockSupa = createMockSupabase();

  // Simulate row pre-existing from earlier migration script with the same deterministic id
  // but missing or legacy firebase_uid
  mockSupa.store.set(deterministicId, {
    id: deterministicId,
    firebase_uid: null, // Legacy / missing
    role: 'patient',
    display_name: 'Old Name',
    email: 'old@example.com',
  });

  const counts = await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    logger: () => {},
  });

  assert.equal(counts.scanned, 1);
  assert.equal(counts.created, 0);
  assert.equal(counts.updated, 1, 'Pre-existing id must be updated without failing');
  assert.equal(counts.failed, 0);

  // Stored row is now updated and linked to the targetUid
  const updatedRow = mockSupa.store.get(deterministicId);
  assert.equal(updatedRow.firebase_uid, targetUid);
  assert.equal(updatedRow.display_name, 'Relinked Name');
  assert.equal(mockSupa.store.size, 1);
});

test('Backfill: Idempotency guarantee across repeat runs', async () => {
  const testDocs = [
    {
      id: 'uid_idempotent_1',
      data: () => ({
        role: 'patient',
        profileId: 'pat_idem_1',
        name: 'Initial Name',
        mobile: '9876543210',
      }),
    },
  ];

  const mockDb = createMockFirestore(testDocs);
  const mockSupa = createMockSupabase();

  // Pass 1: Initial creation
  const counts1 = await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    logger: () => {},
  });

  assert.equal(counts1.created, 1);
  assert.equal(counts1.updated, 0);

  // Pass 2: Repeat execution
  const counts2 = await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    logger: () => {},
  });

  assert.equal(counts2.created, 0);
  assert.equal(counts2.updated, 1, 'Second run must update rather than create');
  assert.equal(counts2.failed, 0);
  assert.equal(mockSupa.store.size, 1, 'Must not duplicate rows');
});

test('Backfill: Privacy guarantee - Zero PII, emails, phones, names or uids in logs', async () => {
  const testDocs = [
    {
      id: 'sensitive_uid_98765',
      data: () => ({
        role: 'patient',
        profileId: 'pat_sensitive',
        name: 'Secret Patient Name',
        mobile: '9876500000',
        email: 'secret_patient@confidential.com',
      }),
    },
  ];

  const mockDb = createMockFirestore(testDocs);
  const mockSupa = createMockSupabase();
  const logs = [];

  await runBackfill({
    apply: true,
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    supabaseConfig: { url: 'https://test.supabase.co', key: 'secret' },
    fetch: mockSupa.fakeFetch,
    logger: (msg) => logs.push(String(msg)),
  });

  const fullLog = logs.join('\n');

  // Verify counts are logged
  assert.ok(fullLog.includes('Scanned: 1'));
  assert.ok(fullLog.includes('Created: 1'));

  // Verify NO PII or sensitive keys appear in logs
  assert.doesNotMatch(fullLog, /sensitive_uid_98765/);
  assert.doesNotMatch(fullLog, /Secret Patient Name/);
  assert.doesNotMatch(fullLog, /9876500000/);
  assert.doesNotMatch(fullLog, /secret_patient@confidential\.com/);
  assert.doesNotMatch(fullLog, /pat_sensitive/);
});

test('Backfill: Counts email collisions in dry-run without printing emails', async () => {
  const testDocs = [
    {
      id: 'uid_dup_1',
      data: () => ({
        role: 'patient',
        email: 'duplicate@example.com',
        mobile: '9876500001',
      }),
    },
    {
      id: 'uid_dup_2',
      data: () => ({
        role: 'patient',
        email: 'duplicate@example.com',
        mobile: '9876500002',
      }),
    },
    {
      id: 'uid_unique',
      data: () => ({
        role: 'doctor',
        email: 'doctor@example.com',
        mobile: '9876500003',
      }),
    },
  ];

  const mockDb = createMockFirestore(testDocs);
  const logs = [];

  const counts = await runBackfill({
    apply: false, // Dry-run mode
    project: 'demo-medibond-test',
    adminApp: { options: { projectId: 'demo-medibond-test' } },
    firestoreDb: mockDb,
    logger: (msg) => logs.push(String(msg)),
  });

  assert.equal(counts.scanned, 3);
  assert.equal(counts.emailCollisions, 1);

  const fullLog = logs.join('\n');
  assert.ok(fullLog.includes('Email Collisions: 1'));
  assert.doesNotMatch(fullLog, /duplicate@example\.com/);
  assert.doesNotMatch(fullLog, /doctor@example\.com/);
});

