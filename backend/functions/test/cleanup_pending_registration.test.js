'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  cleanupPendingRegistration,
  ORPHAN_AUTH_MAX_AGE_MS,
} = require('../registration_otp');

let origLegacy;

test.beforeEach(() => {
  origLegacy = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
  try {
    const { _resetRemoteConfigCache } = require('../sync_flags');
    _resetRemoteConfigCache();
  } catch (_) {}
});

test.afterEach(() => {
  if (origLegacy === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacy;
});

function mockDb(profileByUid = new Map()) {
  return {
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              if (name !== 'users') return { exists: false, data: () => undefined };
              const data = profileByUid.get(id);
              return { exists: data != null, data: () => data };
            },
            async delete() {
              if (name === 'users') profileByUid.delete(id);
            },
          };
        },
      };
    },
  };
}

function mockAuthAdmin(usersByUid, deletedOut) {
  return {
    async getUser(uid) {
      const record = usersByUid.get(uid);
      if (!record) {
        const err = new Error('not found');
        err.code = 'auth/user-not-found';
        throw err;
      }
      return record;
    },
    async deleteUser(uid) {
      deletedOut.push(uid);
      usersByUid.delete(uid);
    },
  };
}

test('cleanupPendingRegistration deletes fresh unverified orphan', async () => {
  const uid = 'cleanup_fresh_uid';
  const nowMs = Date.now();
  const profileByUid = new Map([
    [
      uid,
      {
        role: 'patient',
        profileId: 'p_cleanup_1',
        createdAt: { toDate: () => new Date(nowMs - 60_000) },
      },
    ],
  ]);
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
  ]);
  const deleted = [];
  const result = await cleanupPendingRegistration(
    mockDb(profileByUid),
    { uid, token: {} },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.deepEqual(result, { ok: true, cleaned: true });
  assert.equal(profileByUid.has(uid), false);
  assert.deepEqual(deleted, [uid]);
});

test('cleanupPendingRegistration refuses account older than 10 minutes', async () => {
  const uid = 'cleanup_old_uid';
  const nowMs = Date.now();
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: {
          creationTime: new Date(nowMs - ORPHAN_AUTH_MAX_AGE_MS - 5000).toISOString(),
        },
      },
    ],
  ]);
  const deleted = [];
  const result = await cleanupPendingRegistration(
    mockDb(new Map()),
    { uid, token: {} },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.deepEqual(result, { ok: true, cleaned: false });
  assert.equal(deleted.length, 0);
});

test('cleanupPendingRegistration refuses verified profile flags', async () => {
  const uid = 'cleanup_verified_uid';
  const nowMs = Date.now();
  const profileByUid = new Map([
    [
      uid,
      {
        role: 'patient',
        profileId: 'p_verified',
        mobileVerified: true,
        createdAt: { toDate: () => new Date(nowMs - 60_000) },
      },
    ],
  ]);
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
  ]);
  const deleted = [];
  const result = await cleanupPendingRegistration(
    mockDb(profileByUid),
    { uid, token: {} },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.deepEqual(result, { ok: true, cleaned: false });
  assert.equal(deleted.length, 0);
});

test('cleanupPendingRegistration refuses verified auth token claims', async () => {
  const uid = 'cleanup_claim_uid';
  const nowMs = Date.now();
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
  ]);
  const deleted = [];
  const result = await cleanupPendingRegistration(
    mockDb(new Map()),
    { uid, token: { mobile_verified: true } },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.deepEqual(result, { ok: true, cleaned: false });
  assert.equal(deleted.length, 0);
});

test('cleanupPendingRegistration fail-closed when profile check throws', async () => {
  const uid = 'cleanup_check_fail_uid';
  const nowMs = Date.now();
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
  ]);
  const deleted = [];
  const loadProfile = async () => {
    throw new Error('supabase timeout');
  };

  const result = await cleanupPendingRegistration(
    mockDb(new Map()),
    { uid, token: {} },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted), loadProfile },
  );

  assert.deepEqual(result, { ok: true, cleaned: false });
  assert.equal(deleted.length, 0);
});

test('cleanupPendingRegistration only deletes caller auth uid', async () => {
  const callerUid = 'cleanup_caller_uid';
  const otherUid = 'cleanup_other_uid';
  const nowMs = Date.now();
  const users = new Map([
    [
      callerUid,
      {
        uid: callerUid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
    [
      otherUid,
      {
        uid: otherUid,
        metadata: { creationTime: new Date(nowMs - 60_000).toISOString() },
      },
    ],
  ]);
  const deleted = [];
  const result = await cleanupPendingRegistration(
    mockDb(new Map()),
    { uid: callerUid, token: {} },
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.deepEqual(result, { ok: true, cleaned: true });
  assert.deepEqual(deleted, [callerUid]);
  assert.ok(users.has(otherUid));
});
