'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { consumeOtpVerificationSessionAtomically } = require('../registration_otp');

function createConcurrentMockFirestore() {
  const docs = new Map();
  let transactionChain = Promise.resolve();

  function docRef(collection, id) {
    const key = `${collection}/${id}`;
    return { id, collection, key };
  }

  function readDoc(key) {
    const data = docs.get(key);
    return data == null ? null : { ...data };
  }

  async function runTransaction(updateFn) {
    let releaseGate;
    const gate = new Promise((resolve) => {
      releaseGate = resolve;
    });
    const previous = transactionChain;
    transactionChain = transactionChain.then(() => gate);
    await previous;

    try {
      const pending = new Map();
      const tx = {
        async get(ref) {
          await Promise.resolve();
          const data = pending.has(ref.key)
            ? pending.get(ref.key)
            : readDoc(ref.key);
          return {
            exists: data != null,
            data: () => (data == null ? undefined : { ...data }),
          };
        },
        set(ref, data, { merge } = {}) {
          const base = pending.has(ref.key)
            ? pending.get(ref.key)
            : readDoc(ref.key) || {};
          pending.set(ref.key, merge ? { ...base, ...data } : { ...data });
        },
        delete(ref) {
          pending.set(ref.key, null);
        },
      };

      const result = await updateFn(tx);
      for (const [key, value] of pending.entries()) {
        if (value == null) docs.delete(key);
        else docs.set(key, value);
      }
      return result;
    } finally {
      releaseGate();
    }
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
    runTransaction,
  };
}

function seedSession(db, sessionId, overrides = {}) {
  db.docs.set(`otp_verification_sessions/${sessionId}`, {
    role: 'patient',
    mobileDigits: '9876543210',
    mobileVerified: true,
    consumed: false,
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 60 * 1000)),
    ...overrides,
  });
}

function readSession(db, sessionId) {
  return db.docs.get(`otp_verification_sessions/${sessionId}`) ?? null;
}

test('10 concurrent session completions consume the session exactly once', async () => {
  const db = createConcurrentMockFirestore();
  const sessionId = 'session-replay-race';

  seedSession(db, sessionId);

  const results = await Promise.allSettled(
    Array.from({ length: 10 }, () => consumeOtpVerificationSessionAtomically(db, sessionId, {
      assertSession: (session) => {
        if (session.mobileVerified !== true) {
          throw new Error('unexpected session state');
        }
      },
    })),
  );

  const successes = results.filter((result) => result.status === 'fulfilled');
  const failures = results.filter((result) => result.status === 'rejected');

  assert.equal(successes.length, 1);
  assert.equal(failures.length, 9);
  assert.ok(failures.every((result) => result.reason?.code === 'failed-precondition'));
  assert.equal(readSession(db, sessionId)?.consumed, true);
});

test('rejects replay after a session has already been consumed', async () => {
  const db = createConcurrentMockFirestore();
  const sessionId = 'session-replay-used';

  seedSession(db, sessionId, { consumed: true });

  await assert.rejects(
    () => consumeOtpVerificationSessionAtomically(db, sessionId),
    (err) => err.code === 'failed-precondition',
  );
});
