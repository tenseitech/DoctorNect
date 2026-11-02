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
