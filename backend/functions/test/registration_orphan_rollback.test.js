'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  maybeDeleteOrphanRegistrationAuthUser,
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

test('maybeDeleteOrphanRegistrationAuthUser deletes fresh orphan with no profile', async () => {
  const uid = 'fresh_orphan_uid';
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
  const auth = { uid };
  const db = mockDb(new Map());

  const result = await maybeDeleteOrphanRegistrationAuthUser(auth, db, {
    nowMs,
    authAdmin: mockAuthAdmin(users, deleted),
  });

  assert.equal(result.deleted, true);
  assert.deepEqual(deleted, [uid]);
});

test('maybeDeleteOrphanRegistrationAuthUser does not delete account older than 10 minutes', async () => {
  const uid = 'old_orphan_uid';
  const nowMs = Date.now();
  const users = new Map([
    [
      uid,
      {
        uid,
        metadata: {
          creationTime: new Date(nowMs - ORPHAN_AUTH_MAX_AGE_MS - 1000).toISOString(),
        },
      },
    ],
  ]);
  const deleted = [];
  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    mockDb(new Map()),
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, false);
  assert.equal(result.reason, 'too_old');
  assert.equal(deleted.length, 0);
});

test('maybeDeleteOrphanRegistrationAuthUser does not delete when profile row exists', async () => {
  const uid = 'profile_exists_uid';
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
  const db = mockDb(new Map([[uid, { role: 'patient', profileId: 'p1' }]]));

  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    db,
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, false);
  assert.equal(result.reason, 'profile_exists');
  assert.equal(deleted.length, 0);
});

test('maybeDeleteOrphanRegistrationAuthUser does not delete when verified flag is set', async () => {
  const uid = 'verified_uid';
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
  const db = mockDb(new Map([[uid, { role: 'patient', mobileVerified: true }]]));

  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    db,
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, false);
  assert.equal(result.reason, 'verified_flag_set');
  assert.equal(deleted.length, 0);
});

test('maybeDeleteOrphanRegistrationAuthUser does not delete when profile check throws', async () => {
  const uid = 'profile_check_fail_uid';
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

  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    mockDb(new Map()),
    { nowMs, authAdmin: mockAuthAdmin(users, deleted), loadProfile },
  );

  assert.equal(result.deleted, false);
  assert.equal(result.reason, 'profile_check_failed');
  assert.equal(deleted.length, 0);
});

test('maybeDeleteOrphanRegistrationAuthUser deletes fresh unverified profile then auth', async () => {
  const uid = 'fresh_profile_orphan_uid';
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
  const profileByUid = new Map([
    [
      uid,
      {
        role: 'patient',
        profileId: 'patient_orphan_1',
        createdAt: { toDate: () => new Date(nowMs - 60_000) },
      },
    ],
  ]);
  const db = mockDb(profileByUid);

  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    db,
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, true);
  assert.deepEqual(deleted, [uid]);
  assert.equal(profileByUid.has(uid), false);
});

test('retry registration: fresh orphan profile removal clears duplicate guard', async () => {
  const uid = 'retry_dup_uid';
  const nowMs = Date.now();
  const mobile = '9000000001';
  const profileByUid = new Map([
    [
      uid,
      {
        role: 'patient',
        profileId: 'patient_retry_1',
        mobile,
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
  const db = mockDb(profileByUid);

  assert.ok(profileByUid.has(uid));
  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid },
    db,
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, true);
  assert.equal(profileByUid.has(uid), false);
  assert.deepEqual(deleted, [uid]);
});

test('maybeDeleteOrphanRegistrationAuthUser only targets authenticated caller uid', async () => {
  const callerUid = 'caller_uid';
  const otherUid = 'other_uid';
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
  const result = await maybeDeleteOrphanRegistrationAuthUser(
    { uid: callerUid },
    mockDb(new Map()),
    { nowMs, authAdmin: mockAuthAdmin(users, deleted) },
  );

  assert.equal(result.deleted, true);
  assert.deepEqual(deleted, [callerUid]);
  assert.ok(users.has(otherUid));
});
