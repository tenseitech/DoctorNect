'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');
const { LIMITS, hashKey, enforceAbuseLimit, getRateLimitBackend } = require('../abuse_rate_limit');
const { setRedisClientForTesting } = require('../redis');

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

function createMockRedis() {
  const store = new Map(); // key -> { val, expireAt }
  const recordedKeys = [];

  function cleanExpired(key) {
    const entry = store.get(key);
    if (!entry) return null;
    if (entry.expireAt && Date.now() > entry.expireAt) {
      store.delete(key);
      return null;
    }
    return entry;
  }

  return {
    store,
    recordedKeys,
    async eval(script, numKeys, key, ...args) {
      recordedKeys.push(key);
      const windowMs = Number(args[0]) || 60000;
      let entry = cleanExpired(key);
      if (!entry) {
        entry = { val: 1, expireAt: Date.now() + windowMs };
        store.set(key, entry);
        return 1;
      }
      entry.val += 1;
      return entry.val;
    },
    async incr(key) {
      recordedKeys.push(key);
      let entry = cleanExpired(key);
      if (!entry) {
        entry = { val: 1, expireAt: null };
        store.set(key, entry);
        return 1;
      }
      entry.val += 1;
      return entry.val;
    },
    async pexpire(key, ms) {
      const entry = cleanExpired(key);
      if (entry) {
        entry.expireAt = Date.now() + Number(ms);
      }
      return 1;
    },
  };
}

test('flag default: RATE_LIMIT_BACKEND defaults to firestore', () => {
  const orig = process.env.RATE_LIMIT_BACKEND;
  delete process.env.RATE_LIMIT_BACKEND;
  try {
    assert.equal(getRateLimitBackend(), 'firestore');
  } finally {
    if (orig !== undefined) process.env.RATE_LIMIT_BACKEND = orig;
  }
});

test('Redis rate limiting: limit reached throws same resource-exhausted error and message', async () => {
  const orig = process.env.RATE_LIMIT_BACKEND;
  process.env.RATE_LIMIT_BACKEND = 'redis';
  const mockRedis = createMockRedis();
  setRedisClientForTesting(mockRedis);
  const db = createMockFirestore();

  try {
    const rawPhone = '9876543210';
    const req = {
      rawRequest: { ip: '10.0.0.1' },
      auth: null,
    };

    // otp_send limit for id is 6 (LIMITS.otp_send.id.max = 6)
    for (let i = 1; i <= 6; i++) {
      await enforceAbuseLimit(db, req, 'otp_send', {
        identifier: rawPhone,
        message: 'Too many OTP requests. Please wait 15 minutes.',
      });
    }

    // 7th attempt must throw resource-exhausted with the exact message
    await assert.rejects(
      async () => {
        await enforceAbuseLimit(db, req, 'otp_send', {
          identifier: rawPhone,
          message: 'Too many OTP requests. Please wait 15 minutes.',
        });
      },
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'resource-exhausted');
        assert.equal(err.message, 'Too many OTP requests. Please wait 15 minutes.');
        return true;
      },
    );
  } finally {
    setRedisClientForTesting(null);
    if (orig !== undefined) process.env.RATE_LIMIT_BACKEND = orig;
    else delete process.env.RATE_LIMIT_BACKEND;
  }
});

test('Redis rate limiting: key contains no raw identifier or raw IP', async () => {
  const orig = process.env.RATE_LIMIT_BACKEND;
  process.env.RATE_LIMIT_BACKEND = 'redis';
  const mockRedis = createMockRedis();
  setRedisClientForTesting(mockRedis);
  const db = createMockFirestore();

  try {
    const rawPhone = '919876543210';
    const rawIp = '192.168.1.100';
    const req = {
      rawRequest: { ip: rawIp },
      auth: null,
    };

    await enforceAbuseLimit(db, req, 'otp_send', {
      identifier: rawPhone,
    });

    assert.ok(mockRedis.recordedKeys.length >= 2, 'Expected IP and ID keys in Redis');
    for (const key of mockRedis.recordedKeys) {
      assert.ok(key.startsWith('ratelimit:otp_send:'), `Key ${key} must start with ratelimit:otp_send:`);
      assert.equal(key.includes(rawPhone), false, `Key ${key} must NOT contain raw phone number`);
      assert.equal(key.includes(rawIp), false, `Key ${key} must NOT contain raw IP address`);
      // Verify key ends with sha256 hex string (64 characters)
      const parts = key.split(':');
      const hashPart = parts[parts.length - 1];
      assert.equal(hashPart.length, 64, `Hash part ${hashPart} must be 64-char sha256`);
    }
  } finally {
    setRedisClientForTesting(null);
    if (orig !== undefined) process.env.RATE_LIMIT_BACKEND = orig;
    else delete process.env.RATE_LIMIT_BACKEND;
  }
});

test('Redis rate limiting: window expiry resets the counter', async () => {
  const orig = process.env.RATE_LIMIT_BACKEND;
  process.env.RATE_LIMIT_BACKEND = 'redis';
  const mockRedis = createMockRedis();
  setRedisClientForTesting(mockRedis);
  const db = createMockFirestore();

  try {
    const rawPhone = '8888877777';
    const req = {
      rawRequest: { ip: '10.0.0.2' },
      auth: null,
    };

    for (let i = 1; i <= 6; i++) {
      await enforceAbuseLimit(db, req, 'otp_send', {
        identifier: rawPhone,
      });
    }

    // Next fails
    await assert.rejects(async () => {
      await enforceAbuseLimit(db, req, 'otp_send', { identifier: rawPhone });
    });

    // Simulate window expiry: advance timestamps in mock store
    for (const entry of mockRedis.store.values()) {
      entry.expireAt = Date.now() - 1000;
    }

    // Now request must succeed again!
    const res = await enforceAbuseLimit(db, req, 'otp_send', { identifier: rawPhone });
    assert.deepEqual(res, { ok: true });
  } finally {
    setRedisClientForTesting(null);
    if (orig !== undefined) process.env.RATE_LIMIT_BACKEND = orig;
    else delete process.env.RATE_LIMIT_BACKEND;
  }
});

test('Redis rate limiting: Redis down/error falls back to Firestore transaction', async () => {
  const orig = process.env.RATE_LIMIT_BACKEND;
  process.env.RATE_LIMIT_BACKEND = 'redis';

  // Broken Redis client that simulates connection failure / timeout
  const brokenRedis = {
    async eval() {
      throw new Error('ECONNREFUSED 127.0.0.1:6379');
    },
    async incr() {
      throw new Error('ECONNREFUSED 127.0.0.1:6379');
    },
  };
  setRedisClientForTesting(brokenRedis);
  const db = createMockFirestore();

  try {
    const rawPhone = '9999900000';
    const req = {
      rawRequest: { ip: '10.0.0.3' },
      auth: null,
    };

    // Should NOT throw a Redis error to the caller; should fallback to Firestore
    const res = await enforceAbuseLimit(db, req, 'otp_send', {
      identifier: rawPhone,
    });
    assert.deepEqual(res, { ok: true });

    // Verify Firestore doc was created in abuse_rate_limits collection
    const idHash = hashKey(rawPhone);
    const firestoreKey = `abuse_rate_limits/otp_send_id_${idHash}`;
    assert.ok(db.docs.has(firestoreKey), 'Expected Firestore document to be created as fallback');
    const docData = db.docs.get(firestoreKey);
    assert.equal(docData.count, 1);
  } finally {
    setRedisClientForTesting(null);
    if (orig !== undefined) process.env.RATE_LIMIT_BACKEND = orig;
    else delete process.env.RATE_LIMIT_BACKEND;
  }
});
