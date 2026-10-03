'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const {
  recordFailedLogin,
  recordLoginFailure,
  clearFailedLogins,
  resetLoginAttempts,
} = require('../registration_otp');

function createMockFirestore() {
  const docs = new Map();

  function docRef(collection, id) {
    const key = `${collection}/${id}`;
    return {
      id,
      collection,
      key,
      async get() {
        const data = docs.get(key);
        return {
          exists: data != null,
          data: () => (data == null ? undefined : { ...data }),
        };
      },
      set(data, { merge } = {}) {
        if (merge && docs.has(key)) {
          docs.set(key, { ...docs.get(key), ...data });
        } else {
          docs.set(key, { ...data });
        }
      },
      delete() {
        docs.delete(key);
      },
    };
  }

  return {
    docs,
    collection(name) {
      return {
        doc(id) {
          return docRef(name, id);
        },
      };
    },
    async runTransaction(updateFn) {
      const pending = new Map();
      const tx = {
        async get(ref) {
          const existing = pending.get(ref.key) ?? docs.get(ref.key);
          return {
            exists: existing != null,
            data: () => (existing == null ? undefined : { ...existing }),
          };
        },
        set(ref, data, { merge } = {}) {
          const base = pending.get(ref.key) ?? docs.get(ref.key) ?? {};
          pending.set(ref.key, merge ? { ...base, ...data } : { ...data });
        },
        delete(ref) {
          pending.set(ref.key, null);
        },
      };
      await updateFn(tx);
      for (const [key, value] of pending.entries()) {
        if (value == null) docs.delete(key);
        else docs.set(key, value);
      }
    },
  };
}

function readLoginCount(db, bucket) {
  return db.docs.get(`otp_rate_limits/${bucket}`)?.count ?? 0;
}

test('recordFailedLogin and recordLoginFailure complete without recursion', async () => {
  const db = createMockFirestore();
  const payload = { identifier: 'user@example.com' };
  const options = { clientIp: '203.0.113.10' };

  await assert.doesNotReject(() => recordFailedLogin(db, payload, options));
  await assert.doesNotReject(() => recordLoginFailure(db, payload, options));
});

test('repeated failures increment persisted identifier and IP counters', async () => {
  const db = createMockFirestore();
  const payload = { identifier: 'user@example.com' };
  const options = { clientIp: '203.0.113.10' };

  await recordFailedLogin(db, payload, options);
  await recordFailedLogin(db, payload, options);
  await recordLoginFailure(db, payload, options);

  const idBucket = [...db.docs.keys()].find((key) => key.startsWith('otp_rate_limits/login_id_'));
  const ipBucket = [...db.docs.keys()].find((key) => key.startsWith('otp_rate_limits/login_ip_'));

  assert.ok(idBucket);
  assert.ok(ipBucket);
  assert.equal(readLoginCount(db, idBucket.split('/')[1]), 3);
  assert.equal(readLoginCount(db, ipBucket.split('/')[1]), 3);
  assert.ok(db.docs.get(idBucket).windowStart instanceof Timestamp);
});

test('clearFailedLogins and resetLoginAttempts reset identifier counter', async () => {
  const db = createMockFirestore();
  const payload = { identifier: 'user@example.com' };

  await recordFailedLogin(db, payload, { clientIp: '203.0.113.10' });
  const idBucket = [...db.docs.keys()].find((key) => key.startsWith('otp_rate_limits/login_id_'));
  assert.equal(readLoginCount(db, idBucket.split('/')[1]), 1);

  await clearFailedLogins(db, payload);
  assert.equal(db.docs.has(idBucket), false);

  await recordFailedLogin(db, payload, { clientIp: '203.0.113.10' });
  assert.equal(readLoginCount(db, idBucket.split('/')[1]), 1);

  await resetLoginAttempts(db, payload);
  assert.equal(db.docs.has(idBucket), false);
});
