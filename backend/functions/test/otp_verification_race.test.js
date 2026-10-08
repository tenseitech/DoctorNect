'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { initializeApp, getApps } = require('firebase-admin/app');
if (!getApps().length) initializeApp({ projectId: 'test-project' });

process.env.MSG91_AUTHKEY = 'mock_secret_key_123';
process.env.OTP_TEST_MODE = 'true';

const { setRedisClientForTesting } = require('../redis');
setRedisClientForTesting({
  set: async () => 'OK',
  get: async () => null,
  del: async () => 1,
});

const {
  consumeOtpChallengeAtomically,
  hashOtp,
  legacyHashOtp,
  ALLOW_LEGACY_UNSALTED_OTP_HASH,
  setDemoConfigDocForTesting,
} = require('../registration_otp');

setDemoConfigDocForTesting(null);

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

function seedChallenge(db, challengeKey, {
  otpCode = '654321',
  attempts = 0,
  role = 'patient',
  mobileDigits = '9876543210',
  useLegacyHash = false,
} = {}) {
  db.docs.set(`otp_challenges/${challengeKey}`, {
    role,
    mobileDigits,
    otpHash: useLegacyHash ? legacyHashOtp(otpCode) : hashOtp(otpCode, role, mobileDigits),
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
      mobileDigits: '9876543210',
      role: 'patient',
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
      mobileDigits: '9876543210',
      role: 'patient',
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

test('in-flight legacy unsalted SHA-256 challenge is accepted when ALLOW_LEGACY_UNSALTED_OTP_HASH is true', async () => {
  assert.equal(ALLOW_LEGACY_UNSALTED_OTP_HASH, true, 'Legacy hash fallback must be enabled');
  const db = createConcurrentMockFirestore();
  const challengeKey = 'challenge-legacy-inflight';
  seedChallenge(db, challengeKey, { otpCode: '849201', attempts: 0, useLegacyHash: true });

  const result = await consumeOtpChallengeAtomically(db, {
    challengeKey,
    otp: '849201',
    mobileDigits: '9876543210',
    role: 'patient',
    isDemoAccount: false,
  });

  assert.equal(result.consumed, true, 'Legacy unsalted OTP challenge must be consumed successfully');
  assert.equal(db.docs.has(`otp_challenges/${challengeKey}`), false, 'Legacy challenge doc must be deleted');
});

test('HMAC-SHA256 OTP verification rejects mismatched mobile number or role', async () => {
  const db = createConcurrentMockFirestore();
  const challengeKey = 'challenge-mismatch';
  seedChallenge(db, challengeKey, {
    otpCode: '789012',
    attempts: 0,
    role: 'patient',
    mobileDigits: '9876543210',
  });

  // Verify with matching role and mobile succeeds
  const matchResult = await consumeOtpChallengeAtomically(db, {
    challengeKey,
    otp: '789012',
    mobileDigits: '9876543210',
    role: 'patient',
    isDemoAccount: false,
  });
  assert.equal(matchResult.consumed, true, 'Matching role and mobile must succeed');

  // Seed another challenge to test mismatch
  const mismatchKey = 'challenge-mismatch-2';
  seedChallenge(db, mismatchKey, {
    otpCode: '789012',
    attempts: 0,
    role: 'patient',
    mobileDigits: '9876543210',
  });

  // Verify with different role
  await assert.rejects(
    consumeOtpChallengeAtomically(db, {
      challengeKey: mismatchKey,
      otp: '789012',
      mobileDigits: '9876543210',
      role: 'doctor',
      isDemoAccount: false,
    }),
    { code: 'permission-denied' },
  );

  // Verify with different mobile number
  await assert.rejects(
    consumeOtpChallengeAtomically(db, {
      challengeKey: mismatchKey,
      otp: '789012',
      mobileDigits: '9111111111',
      role: 'patient',
      isDemoAccount: false,
    }),
    { code: 'permission-denied' },
  );
});
