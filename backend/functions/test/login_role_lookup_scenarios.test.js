'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('https');
const { EventEmitter } = require('events');

const {
  lookupMobileRegistration,
  postOtpAccountFieldsFromSearch,
  resolveMobileLookupConflict,
  sendUserRegistrationOtp,
  verifyUserRegistrationOtp,
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

function emptyFirestoreDb() {
  const emptySnap = { empty: true, docs: [] };
  const chain = {
    where: () => chain,
    limit: () => ({ get: async () => emptySnap }),
    doc: () => ({ get: async () => ({ exists: false }) }),
  };
  return { collection: () => chain };
}

test('resolveMobileLookupConflict — existing patient login with matching role is allowed', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'patient',
      requestedRole: 'patient',
      intent: 'login',
    }),
    false,
  );
});

test('postOtpAccountFieldsFromSearch — maps findUserByMobileDigits shape', () => {
  assert.deepEqual(postOtpAccountFieldsFromSearch({ found: false }), {
    exists: false,
    role: null,
  });
  assert.deepEqual(postOtpAccountFieldsFromSearch({ found: true, role: 'patient' }), {
    exists: true,
    role: 'patient',
  });
});

function createMockFirestore() {
  const docs = new Map();
  function docRef(collection, id) {
    const key = `${collection}/${id}`;
    return {
      id,
      key,
      async get() {
        const data = docs.get(key);
        return { exists: data != null, data: () => (data == null ? undefined : { ...data }) };
      },
      async set(data, { merge } = {}) {
        if (merge && docs.has(key)) docs.set(key, { ...docs.get(key), ...data });
        else docs.set(key, { ...data });
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
            where() {
              return this;
            },
            limit() {
              return { get: async () => ({ empty: true, docs: [] }) };
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
          const existing = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
          return {
            exists: existing != null,
            data: () => (existing == null ? undefined : { ...existing }),
          };
        },
        set(ref, data, { merge } = {}) {
          const base = (pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key)) || {};
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
    },
  };
}

function stubSms(onCode) {
  const original = https.request;
  https.request = (options, callback) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = () => {};
    req.end = () => {
      const query = String(options.path || '').split('?')[1] || '';
      const code = new URLSearchParams(query).get('otp');
      if (code) onCode(code);
      const isVerify = String(options.path || '').includes('/otp/verify');
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = isVerify ? 400 : 200;
        callback(res);
        res.emit(
          'data',
          JSON.stringify(isVerify ? { type: 'error', message: 'invalid' } : { type: 'success' }),
        );
        res.emit('end');
      });
    };
    return req;
  };
  return () => {
    https.request = original;
  };
}

test('verifyUserRegistrationOtp — failed OTP throws (no exists/role in success payload)', async () => {
  delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
  process.env.MSG91_AUTH_KEY = 'unit-test-hmac-key';
  process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'unit-test-template';
  process.env.MSG91_TEMPLATE_ID = 'unit-test-template';
  process.env.MSG91_SENDER_ID = 'DRNECT';

  const db = createMockFirestore();
  let sentCode = null;
  const restoreSms = stubSms((code) => {
    sentCode = code;
  });
  const mobile = '9000000099';
  const role = 'patient';
  try {
    await sendUserRegistrationOtp(
      db,
      { mobile, role, otpType: 'registration' },
      { clientIp: '127.0.0.1' },
    );
    assert.ok(sentCode);
    await assert.rejects(
      () =>
        verifyUserRegistrationOtp(
          db,
          { mobile, role, otp: '000000', otpType: 'registration' },
          null,
          { clientIp: '127.0.0.1' },
        ),
      (err) => err && typeof err.code === 'string',
    );
  } finally {
    restoreSms();
  }
});

test('verifyUserRegistrationOtp — successful registration OTP returns exists/role only after verify', async () => {
  delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
  process.env.MSG91_AUTH_KEY = 'unit-test-hmac-key';
  process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'unit-test-template';
  process.env.MSG91_TEMPLATE_ID = 'unit-test-template';
  process.env.MSG91_SENDER_ID = 'DRNECT';

  const db = createMockFirestore();
  let sentCode = null;
  const restoreSms = stubSms((code) => {
    sentCode = code;
  });
  const mobile = '9000000088';
  const role = 'patient';
  try {
    await sendUserRegistrationOtp(
      db,
      { mobile, role, otpType: 'registration' },
      { clientIp: '127.0.0.1' },
    );
    const verified = await verifyUserRegistrationOtp(
      db,
      { mobile, role, otp: sentCode, otpType: 'registration' },
      null,
      { clientIp: '127.0.0.1' },
    );
    assert.equal(verified.ok, true);
    assert.equal(verified.exists, false);
    assert.equal(verified.role, null);
  } finally {
    restoreSms();
  }
});

test('lookupMobileRegistration — returns conflict plus exists/role for client login routing', async () => {
  const res = await lookupMobileRegistration(emptyFirestoreDb(), {
    mobile: '9876543210',
    intent: 'login',
    role: 'patient',
  });
  assert.equal(res.ok, true);
  assert.ok(Object.prototype.hasOwnProperty.call(res, 'conflict'));
  assert.equal(res.exists, false);
  assert.equal(res.role, null);
});
