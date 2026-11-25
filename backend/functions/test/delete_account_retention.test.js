'use strict';

/**
 * Account deletion retention policy (Task E):
 * - Deleting a LAB anonymises the lab and keeps patients' lab bookings, orders and report files.
 * - Deleting a PATIENT removes the patient's Postgres rows and S3 objects (plane-prefixed in
 *   production), and deletes the Firebase Auth user LAST, only when every cleanup step succeeded.
 */

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
if (!getApps().length) initializeApp({ projectId: 'demo-delete-retention' });
const { ListObjectVersionsCommand } = require('@aws-sdk/client-s3');

const del = require('../delete_my_account');
const { setSupabaseClientForTesting } = require('../caller_identity');

let events;
let authInstance;
let origDeleteUser;

function identity(uid, role, profileId) {
  setSupabaseClientForTesting({
    from: (table) => {
      if (table !== 'users') throw new Error('unexpected table ' + table);
      const chain = {
        select: () => chain,
        or: () => chain,
        eq: () => chain,
        limit: () => chain,
        maybeSingle: async () => ({
          data: { id: uid, firebase_uid: uid, role, profile_id: profileId, mobile: '9876543210' },
          error: null,
        }),
      };
      return chain;
    },
  });
}

function pgFetch({ failTable } = {}) {
  del.setSupabaseFetchForTesting(async (url, options) => {
    const path = url.split('/rest/v1/')[1];
    const table = path.split('?')[0];
    events.push({ kind: 'pg', method: options.method, table, path, body: options.body ? JSON.parse(options.body) : null });
    if (failTable && table === failTable && options.method !== 'GET') {
      return { ok: false, status: 500, text: async () => '{"message":"boom"}' };
    }
    if (options.method === 'GET' && table === 'lab_bookings') {
      return { ok: true, status: 200, text: async () => JSON.stringify([{ booking_id: 'b1' }]) };
    }
    return { ok: true, status: 200, text: async () => '[]' };
  });
}

function s3({ fail = false } = {}) {
  del.setS3ClientForTesting({
    send: async (cmd) => {
      if (cmd instanceof ListObjectVersionsCommand) {
        events.push({ kind: 's3', prefix: cmd.input.Prefix });
        if (fail) throw new Error('AccessDenied');
        return { IsTruncated: false, Versions: [], DeleteMarkers: [] };
      }
      return {};
    },
  });
}

beforeEach(() => {
  events = [];
  process.env.SUPABASE_URL = 'https://example.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role-test';
  const { getAuth } = require('firebase-admin/auth');
  authInstance = getAuth();
  origDeleteUser = authInstance.deleteUser;
  authInstance.deleteUser = async (uid) => {
    events.push({ kind: 'auth', uid });
    return {};
  };
});

afterEach(() => {
  authInstance.deleteUser = origDeleteUser;
  del.setSupabaseFetchForTesting(null);
  del.setS3ClientForTesting(null);
  setSupabaseClientForTesting(null);
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  delete process.env.APP_ENV;
  delete process.env.DEMO_REAL_ROUTING_ENABLED;
  delete process.env.DEMO_FIREBASE_UID_ALLOWLIST;
});

test('lab deletion anonymises the lab and keeps patient lab bookings, orders and report files', async () => {
  identity('lab_uid', 'lab', 'lab_1');
  pgFetch();
  s3();

  const res = await del.deleteMyAccountHandler('lab_uid');
  assert.equal(res.ok, true);

  const destructive = events.filter((e) => e.kind === 'pg' && e.method === 'DELETE');
  for (const t of ['lab_bookings', 'lab_orders', 'health_records', 'patients', 'prescriptions']) {
    assert.ok(!destructive.some((e) => e.table === t), `lab deletion must not DELETE from ${t}`);
  }
  const labPatch = events.find((e) => e.kind === 'pg' && e.method === 'PATCH' && e.table === 'labs');
  assert.ok(labPatch, 'labs row is anonymised');
  assert.match(labPatch.path, /lab_id=eq\.lab_1/);
  assert.equal(labPatch.body.lab_name, 'Deleted lab');
  assert.equal(labPatch.body.owner_uid, null);
  assert.equal(labPatch.body.phone, 'deleted');

  const prefixes = events.filter((e) => e.kind === 's3').map((e) => e.prefix);
  assert.ok(prefixes.includes('labs/lab_1/'));
  assert.ok(!prefixes.some((p) => /lab_reports\/|health_records\/|patients\//.test(p)), 'no patient-owned S3 prefix is touched');
  assert.equal(typeof del.collectRoleSpecificS3ReportKeys, 'undefined', 'lab report key collection is gone');

  assert.equal(events[events.length - 1].kind, 'auth', 'Auth deleted last');
});

test('patient deletion removes patient rows and files, then deletes Auth last', async () => {
  identity('pat_uid', 'patient', 'pat_1');
  pgFetch();
  s3();

  await del.deleteMyAccountHandler('pat_uid');

  const deletes = events.filter((e) => e.kind === 'pg' && e.method === 'DELETE');
  for (const t of ['lab_bookings', 'lab_orders', 'health_records', 'appointments', 'patients']) {
    assert.ok(deletes.some((e) => e.table === t && /patient_id=eq\.pat_1/.test(e.path)), `deletes ${t} for patient`);
  }
  const prefixes = events.filter((e) => e.kind === 's3').map((e) => e.prefix);
  for (const p of ['patients/pat_1/', 'health_records/pat_1/', 'lab_reports/pat_1/']) {
    assert.ok(prefixes.includes(p), `deletes ${p}`);
  }
  const authIdx = events.findIndex((e) => e.kind === 'auth');
  assert.equal(authIdx, events.length - 1, 'Auth deletion is the final step');
});

test('S3 cleanup failure keeps the Firebase Auth user so deletion can be retried', async () => {
  identity('pat_uid', 'patient', 'pat_1');
  pgFetch();
  s3({ fail: true });

  await assert.rejects(del.deleteMyAccountHandler('pat_uid'), (e) => e.code === 'unavailable');
  assert.ok(!events.some((e) => e.kind === 'auth'), 'Auth must not be deleted');
});

test('Postgres cleanup failure keeps the Firebase Auth user', async () => {
  identity('pat_uid', 'patient', 'pat_1');
  pgFetch({ failTable: 'health_records' });
  s3();

  await assert.rejects(del.deleteMyAccountHandler('pat_uid'), (e) => e.code === 'unavailable');
  assert.ok(!events.some((e) => e.kind === 'auth'), 'Auth must not be deleted');
});

test('production S3 prefixes follow the data plane: demo/ for demo accounts, prod/ + legacy for real users', async () => {
  process.env.APP_ENV = 'production';
  process.env.DEMO_REAL_ROUTING_ENABLED = '1';
  process.env.DEMO_FIREBASE_UID_ALLOWLIST = 'rev_fb_pat_001';

  assert.deepEqual(del.planeKeyPrefixes('rev_fb_pat_001'), ['demo/']);
  assert.deepEqual(del.planeKeyPrefixes('real_uid'), ['prod/', '']);

  const demo = await del.resolveUserS3Prefixes(null, { uid: 'rev_fb_pat_001', role: 'patient', profileId: 'p1' });
  assert.ok(demo.includes('demo/health_records/p1/'));
  assert.ok(demo.every((p) => p.startsWith('demo/')), 'demo deletion never touches prod objects');

  const real = await del.resolveUserS3Prefixes(null, { uid: 'real_uid', role: 'patient', profileId: 'p1' });
  assert.ok(real.includes('prod/health_records/p1/'));
  assert.ok(real.includes('health_records/p1/'), 'legacy unprefixed prod objects are removed too');
  assert.ok(!real.some((p) => p.startsWith('demo/')));

  process.env.APP_ENV = 'staging';
  assert.deepEqual(del.planeKeyPrefixes('real_uid'), ['']);
});
