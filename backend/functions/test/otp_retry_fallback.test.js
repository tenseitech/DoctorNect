'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const https = require('https');
const { EventEmitter } = require('events');
const adminFirestore = require('firebase-admin/firestore');
const { Timestamp, FieldValue } = adminFirestore;

// Setup environment and stubs before requiring registration_otp
adminFirestore.getFirestore = () => ({
  collection: (col) => ({
    doc: (d) => ({
      get: async () => ({ exists: false }),
    }),
  }),
});

process.env.MSG91_AUTHKEY = 'mock_auth_key_123';
process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'mock_dlt_template_reg';
process.env.MSG91_TEMPLATE_ID = 'mock_dlt_template_shared';
process.env.MSG91_SENDER_ID = 'DRNECT';
delete process.env.OTP_TEST_MODE;
delete process.env.MSG91_PROXY_URL;

const { setRedisClientForTesting } = require('../redis');
const redisMockStore = new Map();
setRedisClientForTesting({
  set: async (k, v) => { redisMockStore.set(k, v); return 'OK'; },
  get: async (k) => redisMockStore.get(k) || null,
  del: async (...keys) => { for (const k of keys) redisMockStore.delete(k); return 1; },
});

const { sendUserRegistrationOtp } = require('../registration_otp');

function mobileHash(role, digits) {
  return crypto.createHash('sha256').update(`${role}:${digits}`).digest('hex');
}

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
      async set(data, { merge } = {}) {
        if (merge && docs.has(key)) {
          docs.set(key, { ...docs.get(key), ...data });
        } else {
          docs.set(key, { ...data });
        }
      },
      async delete() {
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
        where() {
          return {
            where() { return this; },
            limit() {
              return {
                get: async () => ({ empty: true, docs: [] }),
              };
            },
            get: async () => ({ empty: true, docs: [] }),
          };
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

test('retry fails with session expired -> fallback to fresh send, stale challenge replaced, exactly one SMS sent', async () => {
  const db = createMockFirestore();
  const redisStore = new Map();
  setRedisClientForTesting({
    set: async (k, v) => { redisStore.set(k, v); return 'OK'; },
    get: async (k) => redisStore.get(k) || null,
    del: async (...keys) => { for (const k of keys) redisStore.delete(k); return 1; },
  });

  const phone = '9876543210';
  const role = 'patient';
  const chKey = `otp_challenges/${mobileHash(role, phone)}`;
  const staleHash = 'stale_hash_from_previous_attempt';

  // Seed stale challenge document older than cooldown window (2 minutes old)
  db.docs.set(chKey, {
    role,
    mobileDigits: phone,
    otpHash: staleHash,
    sentAt: Timestamp.fromDate(new Date(Date.now() - 120000)),
    attempts: 3,
  });
  redisStore.set(`otp:challenge:${phone}`, JSON.stringify({ otpHash: staleHash }));
  redisStore.set(`otp:challenge:${role}:${phone}`, JSON.stringify({ otpHash: staleHash }));

  const httpCalls = [];
  const warnings = [];
  const origWarn = console.warn;
  console.warn = (...args) => {
    warnings.push(args);
    origWarn(...args);
  };

  const origHttpsRequest = https.request;
  https.request = (options, cb) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    let postData = '';
    req.write = (chunk) => { if (chunk) postData += chunk; };
    req.end = () => {
      process.nextTick(() => {
        const path = options.path || '';
        const method = options.method || 'GET';
        if (path.includes('/api/v5/otp/retry')) {
          httpCalls.push({ type: 'retry', path, method });
          // MSG91 returns error indicating expired session
          const res = new EventEmitter();
          res.statusCode = 200;
          cb(res);
          res.emit('data', JSON.stringify({ message: 'No OTP request found to retryotp', type: 'error' }));
          res.emit('end');
        } else if (path.includes('/api/v5/otp')) {
          httpCalls.push({ type: 'send', path, method, postData });
          // MSG91 fresh send succeeds
          const res = new EventEmitter();
          res.statusCode = 200;
          cb(res);
          res.emit('data', JSON.stringify({ message: 'fresh_request_id_999', type: 'success' }));
          res.emit('end');
        }
      });
    };
    return req;
  };

  try {
    const result = await sendUserRegistrationOtp(db, {
      mobile: phone,
      role,
      otpType: 'registration',
    }, { clientIp: '127.0.0.1' });

    assert.equal(result.ok, true);

    // 1 retry attempt was made and failed, 1 fresh send attempt was made and succeeded
    const retries = httpCalls.filter((c) => c.type === 'retry');
    const sends = httpCalls.filter((c) => c.type === 'send');
    assert.equal(retries.length, 1, 'Exactly one retry call was made');
    assert.equal(sends.length, 1, 'Exactly one fresh send call was made');

    // Warning logged with reason RETRY_FAILED_FALLBACK_TO_FRESH_SEND and mobileLast4
    const fallbackWarning = warnings.find((w) =>
      w.some((arg) => typeof arg === 'object' && arg?.reason === 'RETRY_FAILED_FALLBACK_TO_FRESH_SEND')
    );
    assert.ok(fallbackWarning, 'Fallback warning must be logged');
    const warnPayload = fallbackWarning.find((arg) => typeof arg === 'object' && arg?.reason === 'RETRY_FAILED_FALLBACK_TO_FRESH_SEND');
    assert.equal(warnPayload.mobileLast4, '3210');

    // Stale challenge in Firestore was replaced with fresh challenge
    const freshDoc = db.docs.get(chKey);
    assert.ok(freshDoc, 'Fresh challenge document must exist in Firestore');
    assert.notEqual(freshDoc.otpHash, staleHash, 'Stale hash must be replaced with newly generated hash');
    assert.equal(freshDoc.attempts, 0, 'Attempts must be reset to 0');
    assert.equal(freshDoc.mobileDigits, phone);

    // Redis contains updated challenge
    const redisVal = redisStore.get(`otp:challenge:${phone}`);
    assert.ok(redisVal);
    const parsedRedis = JSON.parse(redisVal);
    assert.notEqual(parsedRedis.otpHash, staleHash);
  } finally {
    https.request = origHttpsRequest;
    console.warn = origWarn;
  }
});

test.after(() => {
  setRedisClientForTesting(null);
});

test('retry fails with non-HttpsError (network error) -> fallback to fresh send', async () => {
  const db = createMockFirestore();
  const phone = '9876543211';
  const role = 'doctor';
  const chKey = `otp_challenges/${mobileHash(role, phone)}`;
  const staleHash = 'stale_hash_network_test';

  db.docs.set(chKey, {
    role,
    mobileDigits: phone,
    otpHash: staleHash,
    sentAt: Timestamp.fromDate(new Date(Date.now() - 120000)),
    attempts: 1,
  });

  const httpCalls = [];
  const origHttpsRequest = https.request;
  https.request = (options, cb) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = () => {};
    req.end = () => {
      process.nextTick(() => {
        const path = options.path || '';
        if (path.includes('/api/v5/otp/retry')) {
          httpCalls.push({ type: 'retry' });
          // Simulate network connection failure
          req.emit('error', new Error('connect ECONNREFUSED 10.0.0.1:443'));
        } else if (path.includes('/api/v5/otp')) {
          httpCalls.push({ type: 'send' });
          const res = new EventEmitter();
          res.statusCode = 200;
          cb(res);
          res.emit('data', JSON.stringify({ message: 'fresh_id_ok', type: 'success' }));
          res.emit('end');
        }
      });
    };
    return req;
  };

  try {
    const result = await sendUserRegistrationOtp(db, {
      mobile: phone,
      role,
      otpType: 'registration',
    }, { clientIp: '127.0.0.1' });

    assert.equal(result.ok, true);
    assert.equal(httpCalls.filter((c) => c.type === 'retry').length, 1);
    assert.equal(httpCalls.filter((c) => c.type === 'send').length, 1);

    const freshDoc = db.docs.get(chKey);
    assert.notEqual(freshDoc.otpHash, staleHash);
    assert.equal(freshDoc.attempts, 0);
  } finally {
    https.request = origHttpsRequest;
  }
});

test('cooldown early exit is not bypassed by retry fallback', async () => {
  const db = createMockFirestore();
  const phone = '9876543212';
  const role = 'patient';
  const chKey = `otp_challenges/${mobileHash(role, phone)}`;

  // Seed challenge sent 10 seconds ago (active cooldown)
  db.docs.set(chKey, {
    role,
    mobileDigits: phone,
    otpHash: 'active_hash',
    sentAt: Timestamp.fromDate(new Date(Date.now() - 10000)),
    attempts: 1,
  });

  let httpInvoked = false;
  const origHttpsRequest = https.request;
  https.request = () => {
    httpInvoked = true;
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.end = () => {};
    return req;
  };

  try {
    await assert.rejects(
      () => sendUserRegistrationOtp(db, {
        mobile: phone,
        role,
        otpType: 'registration',
      }, { clientIp: '127.0.0.1' }),
      (err) => {
        assert.equal(err.code, 'resource-exhausted');
        assert.match(err.message, /wait a minute/i);
        return true;
      },
    );
    assert.equal(httpInvoked, false, 'No HTTP calls should be made during cooldown');
  } finally {
    https.request = origHttpsRequest;
  }
});

test('fallback to fresh send works across all roles', async () => {
  const roles = [
    { role: 'doctor', phone: '9876543220' },
    { role: 'patient', phone: '9876543221' },
    { role: 'medicalStore', phone: '9876543222' },
    { role: 'lab', phone: '9876543223' },
    { role: 'ambulance', phone: '9876543224' },
    { role: 'superAdmin', phone: '9876543225' },
  ];

  for (const { role, phone } of roles) {
    const db = createMockFirestore();
    const chKey = `otp_challenges/${mobileHash(role, phone)}`;
    const staleHash = `stale_for_${role}`;

    db.docs.set(chKey, {
      role,
      mobileDigits: phone,
      otpHash: staleHash,
      sentAt: Timestamp.fromDate(new Date(Date.now() - 120000)),
      attempts: 2,
    });

    const calls = [];
    const origHttpsRequest = https.request;
    https.request = (options, cb) => {
      const req = new EventEmitter();
      req.setTimeout = () => {};
      req.destroy = () => {};
      req.write = () => {};
      req.end = () => {
        process.nextTick(() => {
          const path = options.path || '';
          if (path.includes('/api/v5/otp/retry')) {
            calls.push('retry');
            const res = new EventEmitter();
            res.statusCode = 200;
            cb(res);
            res.emit('data', JSON.stringify({ message: 'No OTP request found to retryotp', type: 'error' }));
            res.emit('end');
          } else if (path.includes('/api/v5/otp')) {
            calls.push('send');
            const res = new EventEmitter();
            res.statusCode = 200;
            cb(res);
            res.emit('data', JSON.stringify({ message: `req_${role}`, type: 'success' }));
            res.emit('end');
          }
        });
      };
      return req;
    };

    try {
      const res = await sendUserRegistrationOtp(db, {
        mobile: phone,
        role,
        otpType: 'registration',
      }, { clientIp: '127.0.0.1' });

      assert.equal(res.ok, true, `Role ${role} should succeed`);
      assert.deepEqual(calls, ['retry', 'send'], `Role ${role} should attempt retry then fresh send`);

      const updated = db.docs.get(chKey);
      assert.notEqual(updated.otpHash, staleHash, `Role ${role} challenge should be refreshed`);
      assert.equal(updated.attempts, 0);
    } finally {
      https.request = origHttpsRequest;
    }
  }
});
