'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  assertLoginAllowed,
  recordFailedLogin,
  clearFailedLogins,
} = require('../registration_otp');

/**
 * Reusable mock Firestore instance mirroring login_failure_tracking.test.js
 */
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

/**
 * Simulates the ambulance driver PIN verification login flow in index.js:runVerifyAmbulanceDriverLogin:
 * 1. Checks assertLoginAllowed for identifier `ambulance:${username}`
 * 2. If credentials fail, records failed login via recordFailedLogin
 * 3. If credentials succeed, clears failed logins via clearFailedLogins
 */
async function simulateAmbulanceDriverLogin(db, { username, pinMatches, clientIp = '203.0.113.50' }) {
  const identifier = `ambulance:${username}`;

  // Step 1: Pre-login lockout check (index.js:1361-1372)
  await assertLoginAllowed(db, { identifier }, { clientIp });

  // Step 2: Validate PIN credentials
  if (!pinMatches) {
    await recordFailedLogin(db, { identifier }, { clientIp });
    return { ok: false, reason: 'invalid_credentials' };
  }

  // Step 3: Clear failed attempts on success (index.js:1395)
  await clearFailedLogins(db, { identifier });
  return { ok: true };
}

test('ambulance driver login: 5 failed PIN logins lock out on 6th attempt, different username is unaffected', async () => {
  const db = createMockFirestore();
  const lockedUser = 'driver_alpha';
  const otherUser = 'driver_beta';

  // Perform 5 consecutive failed PIN login attempts for driver_alpha
  for (let i = 1; i <= 5; i++) {
    const res = await simulateAmbulanceDriverLogin(db, {
      username: lockedUser,
      pinMatches: false,
      clientIp: `203.0.113.${10 + i}`,
    });
    assert.equal(res.ok, false, `Attempt ${i} should return ok: false`);
  }

  // Attempt 6 for driver_alpha must be rejected with HttpsError('resource-exhausted')
  await assert.rejects(
    async () => {
      await simulateAmbulanceDriverLogin(db, {
        username: lockedUser,
        pinMatches: true, // Even with correct PIN, caller must be locked out
        clientIp: '203.0.113.99',
      });
    },
    (err) => {
      assert.ok(err instanceof HttpsError, 'Error should be an instance of HttpsError');
      assert.equal(err.code, 'resource-exhausted', 'Error code must be resource-exhausted');
      assert.match(err.message, /Too many login attempts/i);
      return true;
    },
    '6th attempt for lockedUser must throw resource-exhausted'
  );

  // A different username (driver_beta) must remain unaffected and succeed
  const otherRes = await simulateAmbulanceDriverLogin(db, {
    username: otherUser,
    pinMatches: true,
    clientIp: '203.0.113.100',
  });
  assert.equal(otherRes.ok, true, 'Different username must not be affected by driver_alpha lockout');
});
