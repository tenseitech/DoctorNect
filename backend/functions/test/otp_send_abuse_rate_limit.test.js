'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const adminFirestore = require('firebase-admin/firestore');
const { LIMITS, enforceAbuseLimit } = require('../abuse_rate_limit');
const { enforceSendUserRegistrationOtpRateLimit } = require('../index');
const { setRedisClientForTesting } = require('../redis');

let origLegacyCutover;
let origRateLimitBackend;
test.beforeEach(() => {
  origLegacyCutover = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  origRateLimitBackend = process.env.RATE_LIMIT_BACKEND;
  process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
  process.env.RATE_LIMIT_BACKEND = 'firestore';
  setRedisClientForTesting(null);
  try {
    const { _resetRemoteConfigCache } = require('../sync_flags');
    _resetRemoteConfigCache();
  } catch (_) {}
});

test.afterEach(() => {
  setRedisClientForTesting(null);
  delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  if (origLegacyCutover === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacyCutover;
  if (origRateLimitBackend === undefined) delete process.env.RATE_LIMIT_BACKEND;
  else process.env.RATE_LIMIT_BACKEND = origRateLimitBackend;
  try {
    const { _resetRemoteConfigCache } = require('../sync_flags');
    _resetRemoteConfigCache();
  } catch (_) {}
});

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

// Ensure remote demo config fetches resolve immediately during tests
const origGetFirestore = adminFirestore.getFirestore;
adminFirestore.getFirestore = () => ({
  collection: (col) => ({
    doc: (d) => ({
      get: async () => ({
        exists: true,
        data: () => ({
          demoOtp: '000000',
          demoPhones: {
            patient: ['9999900001'],
            doctor: ['9999900002'],
            medicalStore: ['9999900003'],
            lab: ['9999900004'],
            ambulance: ['9999900005'],
            superAdmin: ['9999988888'],
          },
          enableDemoSuperAdmin: true,
        }),
      }),
    }),
  }),
});

test('LIMITS contains otp_send configuration', () => {
  assert.deepEqual(LIMITS.otp_send, {
    ip: { windowMs: 15 * 60 * 1000, max: 30 },
    id: { windowMs: 15 * 60 * 1000, max: 6 },
  });
});

test('a. login OTP does not increment any signup_* bucket', async () => {
  const db = createMockFirestore();
  const request = {
    data: {
      otpType: 'login',
      mobile: '+919876500001',
      role: 'doctor',
    },
    rawRequest: {
      ip: '203.0.113.1',
    },
  };

  await enforceSendUserRegistrationOtpRateLimit(db, request);

  const keys = [...db.docs.keys()];
  const signupKeys = keys.filter((k) => k.includes('/signup_'));
  assert.equal(signupKeys.length, 0, 'No signup bucket keys should be created for login OTP');

  const otpSendIdKeys = keys.filter((k) => k.includes('/otp_send_id_'));
  const otpSendIpKeys = keys.filter((k) => k.includes('/otp_send_ip_'));
  assert.equal(otpSendIdKeys.length, 1, 'Exactly one otp_send id bucket should be created');
  assert.equal(otpSendIpKeys.length, 1, 'Exactly one otp_send ip bucket should be created');
  assert.equal(db.docs.get(otpSendIdKeys[0]).count, 1);

  // Different formats of same number share the same bucket
  const requestPlain = {
    data: { otpType: 'login', mobile: '9876500001', role: 'doctor' },
    rawRequest: { ip: '203.0.113.1' },
  };
  await enforceSendUserRegistrationOtpRateLimit(db, requestPlain);
  assert.equal(db.docs.get(otpSendIdKeys[0]).count, 2);

  const requestWith0 = {
    data: { otpType: 'login', mobile: '09876500001', role: 'doctor' },
    rawRequest: { ip: '203.0.113.1' },
  };
  await enforceSendUserRegistrationOtpRateLimit(db, requestWith0);
  assert.equal(db.docs.get(otpSendIdKeys[0]).count, 3);

  // Verify signup buckets still remain untouched
  const finalSignupKeys = [...db.docs.keys()].filter((k) => k.includes('/signup_'));
  assert.equal(finalSignupKeys.length, 0);
});

test('b. registration OTP still increments signup_* buckets and is blocked after the limit', async () => {
  const db = createMockFirestore();
  const makeRequest = () => ({
    data: {
      otpType: 'registration',
      mobile: '+919876500002',
      role: 'patient',
    },
    rawRequest: {
      ip: '203.0.113.2',
    },
  });

  // Limit for signup is max: 3 for id (24h)
  await enforceSendUserRegistrationOtpRateLimit(db, makeRequest());
  await enforceSendUserRegistrationOtpRateLimit(db, makeRequest());
  await enforceSendUserRegistrationOtpRateLimit(db, makeRequest());

  const keys = [...db.docs.keys()];
  const signupIdKeys = keys.filter((k) => k.includes('/signup_id_'));
  assert.equal(signupIdKeys.length, 1);
  assert.equal(db.docs.get(signupIdKeys[0]).count, 3);

  // 4th attempt exceeds max: 3 and is blocked
  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(db, makeRequest()),
    (err) => {
      assert.equal(err.code, 'resource-exhausted');
      assert.equal(err.message, 'Too many account creation attempts. Please try again later.');
      return true;
    },
  );
});

test('c. otp_send blocks the 7th request for the same mobile within 15 minutes', async () => {
  const db = createMockFirestore();
  const makeLoginRequest = (i) => ({
    data: {
      otpType: 'login',
      mobile: '9876500003',
      role: 'superAdmin',
    },
    rawRequest: {
      // Use different IPs so we only trigger id rate limit (max 6) and not ip limit (max 30)
      ip: `203.0.113.${10 + i}`,
    },
  });

  // Requests 1 to 6 must succeed
  for (let i = 1; i <= 6; i++) {
    await enforceSendUserRegistrationOtpRateLimit(db, makeLoginRequest(i));
  }

  const idKey = [...db.docs.keys()].find((k) => k.includes('/otp_send_id_'));
  assert.ok(idKey);
  assert.equal(db.docs.get(idKey).count, 6);

  // 7th request must be blocked
  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(db, makeLoginRequest(7)),
    (err) => {
      assert.equal(err.code, 'resource-exhausted');
      assert.equal(err.message, 'Too many OTP requests. Please try again in a few minutes.');
      return true;
    },
  );

  // Also verify forgot_password uses the same otp_send category limit
  const makeForgotRequest = () => ({
    data: {
      otpType: 'forgot_password',
      mobile: '9876500003',
      role: 'superAdmin',
    },
    rawRequest: {
      ip: '203.0.113.99',
    },
  });

  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(db, makeForgotRequest()),
    (err) => {
      assert.equal(err.code, 'resource-exhausted');
      assert.equal(err.message, 'Too many OTP requests. Please try again in a few minutes.');
      return true;
    },
  );
});

test('d. formerly-demo phone does not bypass limits and is properly rate limited', async () => {
  const db = createMockFirestore();
  const phone = '9999900001';
  // First 3 registrations pass signup limit
  for (let i = 0; i < 3; i++) {
    await assert.doesNotReject(() => enforceSendUserRegistrationOtpRateLimit(db, {
      data: { otpType: 'registration', mobile: phone, role: 'patient' },
      rawRequest: { ip: '198.51.100.99' },
    }));
  }
  // 4th request must be rejected with resource-exhausted
  await assert.rejects(
    () => enforceSendUserRegistrationOtpRateLimit(db, {
      data: { otpType: 'registration', mobile: phone, role: 'patient' },
      rawRequest: { ip: '198.51.100.99' },
    }),
    (err) => err.code === 'resource-exhausted'
  );
});
