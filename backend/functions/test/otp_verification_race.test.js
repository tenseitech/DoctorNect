'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const {
  consumeOtpChallengeAtomically,
  hashOtp,
} = require('../registration_otp');

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

function seedChallenge(db, challengeKey, { otpCode = '654321', attempts = 0 } = {}) {
  db.docs.set(`otp_challenges/${challengeKey}`, {
    otpHash: hashOtp(otpCode),
    attempts,
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)),
  });
}

function readAttempts(db, challengeKey) {
  return db.docs.get(`otp_challenges/${challengeKey}`)?.attempts ?? null;
}

test('10 concurrent invalid OTP attempts increment attempts atomically and lock out', async () => {
  const db = createConcurrentMockFirestore();
  const challengeKey = 'challenge-invalid-race';
  seedChallenge(db, challengeKey, { otpCode: '654321', attempts: 0 });

  const results = await Promise.allSettled(
    Array.from({ length: 10 }, () => consumeOtpChallengeAtomically(db, {
      challengeKey,
      otp: '000000',
      isDemoAccount: false,
    })),
  );

  const denied = results.filter(
    (result) => result.status === 'rejected' && result.reason?.code === 'permission-denied',
  );
  const exhausted = results.filter(
    (result) => result.status === 'rejected' && result.reason?.code === 'resource-exhausted',
  );
  const missing = results.filter(
    (result) => result.status === 'rejected' && result.reason?.code === 'failed-precondition',
  );

  assert.equal(denied.length, 5);
  assert.equal(exhausted.length + missing.length, 5);
  assert.equal(readAttempts(db, challengeKey), null);
});

test('10 concurrent valid OTP attempts consume the challenge exactly once', async () => {
  const db = createConcurrentMockFirestore();
  const challengeKey = 'challenge-valid-race';
  seedChallenge(db, challengeKey, { otpCode: '654321', attempts: 0 });

  const results = await Promise.allSettled(
    Array.from({ length: 10 }, () => consumeOtpChallengeAtomically(db, {
      challengeKey,
      otp: '654321',
      isDemoAccount: false,
    })),
  );

  const successes = results.filter((result) => result.status === 'fulfilled');
  const failures = results.filter((result) => result.status === 'rejected');

  assert.equal(successes.length, 1);
  assert.equal(failures.length, 9);
  assert.ok(failures.every((result) => result.reason?.code === 'failed-precondition'));
  assert.equal(readAttempts(db, challengeKey), null);
});
