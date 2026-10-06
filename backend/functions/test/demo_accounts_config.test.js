'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getDemoConfig,
  isDemoPhone,
  setDemoConfigDocForTesting,
  resetDemoConfigCacheForTesting,
} = require('../registration_otp');

const PROD_PROJECT = 'medibond-45fad';

test.describe('Demo accounts configuration gating', () => {
  const origGcloud = process.env.GCLOUD_PROJECT;
  const origGoogleCloud = process.env.GOOGLE_CLOUD_PROJECT;
  const origEmulator = process.env.FUNCTIONS_EMULATOR;

  test.afterEach(() => {
    // Restore env & reset testing overrides
    if (origGcloud === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = origGcloud;

    if (origGoogleCloud === undefined) delete process.env.GOOGLE_CLOUD_PROJECT;
    else process.env.GOOGLE_CLOUD_PROJECT = origGoogleCloud;

    if (origEmulator === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = origEmulator;

    setDemoConfigDocForTesting(undefined);
    resetDemoConfigCacheForTesting();
  });

  test('Case 1: production with no doc -> demo login is OFF for all roles', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting(null); // Document does not exist

    const config = await getDemoConfig();
    assert.equal(config, null, 'getDemoConfig must return null when app_config doc is missing in production');

    const patientAllowed = await isDemoPhone('7058809803', 'patient');
    assert.equal(patientAllowed, false, 'Patient demo login must be OFF in production with missing doc');

    const doctorAllowed = await isDemoPhone('7666892394', 'doctor');
    assert.equal(doctorAllowed, false, 'Doctor demo login must be OFF in production with missing doc');

    const storeAllowed = await isDemoPhone('9359503874', 'medicalStore');
    assert.equal(storeAllowed, false, 'Medical store demo login must be OFF in production with missing doc');

    const labAllowed = await isDemoPhone('9409858233', 'lab');
    assert.equal(labAllowed, false, 'Lab demo login must be OFF in production with missing doc');

    const ambulanceAllowed = await isDemoPhone('9307583929', 'ambulance');
    assert.equal(ambulanceAllowed, false, 'Ambulance demo login must be OFF in production with missing doc');
  });

  test('Case 2: production with the flag false -> demo login is OFF for all roles', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: false,
      demoOtp: '000000',
      demoPhones: {
        patient: ['7058809803'],
        doctor: ['7666892394'],
      },
    });

    const config = await getDemoConfig();
    assert.equal(config, null, 'getDemoConfig must return null when demoLoginEnabled is false in production');

    const patientAllowed = await isDemoPhone('7058809803', 'patient');
    assert.equal(patientAllowed, false, 'Patient demo login must be OFF when demoLoginEnabled is false');

    const doctorAllowed = await isDemoPhone('7666892394', 'doctor');
    assert.equal(doctorAllowed, false, 'Doctor demo login must be OFF when demoLoginEnabled is false');
  });

  test('Case 3: production with the flag true -> demo login is ON for configured roles', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: true,
      demoOtp: '000000',
      demoPhones: {
        patient: ['7058809803'],
        doctor: ['7666892394'],
      },
    });

    const config = await getDemoConfig();
    assert.ok(config, 'getDemoConfig must return data when demoLoginEnabled is true in production');
    assert.equal(config.demoLoginEnabled, true);

    const patientAllowed = await isDemoPhone('7058809803', 'patient');
    assert.equal(patientAllowed, true, 'Configured patient demo phone must be allowed');

    const doctorAllowed = await isDemoPhone('7666892394', 'doctor');
    assert.equal(doctorAllowed, true, 'Configured doctor demo phone must be allowed');

    const unconfiguredAllowed = await isDemoPhone('9999999999', 'patient');
    assert.equal(unconfiguredAllowed, false, 'Unconfigured phone number must be rejected');
  });

  test('Case 4: non-production fallback -> falls back to DEFAULT_DEMO_CONFIG', async () => {
    process.env.GCLOUD_PROJECT = 'demo-doctornect-local';
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting(null); // Missing doc in non-prod

    const config = await getDemoConfig();
    assert.ok(config, 'getDemoConfig must return DEFAULT_DEMO_CONFIG in non-production');
    assert.equal(config.demoOtp, '000000');
    assert.ok(Array.isArray(config.demoPhones?.patient));

    const patientAllowed = await isDemoPhone('7058809803', 'patient');
    assert.equal(patientAllowed, true, 'Default demo patient must be allowed in non-production fallback');

    const doctorAllowed = await isDemoPhone('7666892394', 'doctor');
    assert.equal(doctorAllowed, true, 'Default demo doctor must be allowed in non-production fallback');
  });

  test('Case 5: Stale demo challenge in production when demo login is disabled is rejected and deleted', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting(null); // demo login disabled

    const { consumeOtpChallengeAtomically, hashOtp } = require('../registration_otp');
    const { Timestamp } = require('firebase-admin/firestore');

    const docs = new Map();
    const challengeKey = 'test_challenge_stale_demo';
    const initialChallenge = {
      role: 'patient',
      mobileDigits: '7058809803',
      otpHash: hashOtp('000000', 'patient', '7058809803'),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
      attempts: 0,
      demoAccount: true, // tagged as demo account from earlier demo session
    };
    docs.set(`otp_challenges/${challengeKey}`, initialChallenge);

    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
          delete(ref) {
            pending.set(ref.key, null);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) {
          if (v == null) docs.delete(k);
          else docs.set(k, v);
        }
        return result;
      },
    };

    // Attempting to verify '000000' against stale demo challenge must be rejected with permission-denied
    await assert.rejects(
      consumeOtpChallengeAtomically(mockDb, {
        challengeKey,
        otp: '000000',
        isDemoAccount: false,
        mobileDigits: '7058809803',
        role: 'patient',
      }),
      (err) => err.code === 'permission-denied' && err.message.includes('Invalid OTP'),
    );

    // Document MUST be deleted from Firestore to prevent any further probing
    assert.equal(docs.has(`otp_challenges/${challengeKey}`), false, 'Stale demo challenge document must be deleted from Firestore');
  });

  test('Case 6: Demo challenge when demo login is enabled in production succeeds', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: true,
      demoOtp: '000000',
      demoPhones: {
        patient: ['7058809803'],
      },
    });

    const { consumeOtpChallengeAtomically, hashOtp } = require('../registration_otp');
    const { Timestamp } = require('firebase-admin/firestore');

    const docs = new Map();
    const challengeKey = 'test_challenge_active_demo';
    docs.set(`otp_challenges/${challengeKey}`, {
      role: 'patient',
      mobileDigits: '7058809803',
      otpHash: hashOtp('000000', 'patient', '7058809803'),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
      attempts: 0,
      demoAccount: true,
    });

    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
          delete(ref) {
            pending.set(ref.key, null);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) {
          if (v == null) docs.delete(k);
          else docs.set(k, v);
        }
        return result;
      },
    };

    const outcome = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey,
      otp: '000000',
      isDemoAccount: true,
      mobileDigits: '7058809803',
      role: 'patient',
    });

    assert.equal(outcome.consumed, true, 'Active demo challenge must be successfully consumed');
  });

  test('Case 7: Normal challenge in production is unaffected by demo checks', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting(null); // demo login disabled

    const { consumeOtpChallengeAtomically, hashOtp } = require('../registration_otp');
    const { Timestamp } = require('firebase-admin/firestore');

    const docs = new Map();
    const challengeKey = 'test_challenge_normal';
    docs.set(`otp_challenges/${challengeKey}`, {
      role: 'patient',
      mobileDigits: '9876543210',
      otpHash: hashOtp('482910', 'patient', '9876543210'),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
      attempts: 0,
      demoAccount: false,
    });

    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
          delete(ref) {
            pending.set(ref.key, null);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) {
          if (v == null) docs.delete(k);
          else docs.set(k, v);
        }
        return result;
      },
    };

    const outcome = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey,
      otp: '482910',
      isDemoAccount: false,
      mobileDigits: '9876543210',
      role: 'patient',
    });

    assert.equal(outcome.consumed, true, 'Normal challenge must be successfully consumed');
  });

  test('Case 8: Production demo sends capped at 10 per hour; 11th send rejected', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: true,
      demoOtp: '000000',
      demoPhones: { patient: ['7058809803'] },
    });

    const { enforceSendOtpRateLimits } = require('../registration_otp');
    const docs = new Map();
    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) docs.set(k, v);
        return result;
      },
    };

    // 10 sends must succeed
    for (let i = 1; i <= 10; i++) {
      await enforceSendOtpRateLimits(mockDb, {
        clientIp: '192.168.1.1',
        role: 'patient',
        digits: '7058809803',
      });
    }

    // 11th send must be rejected with resource-exhausted
    await assert.rejects(
      enforceSendOtpRateLimits(mockDb, {
        clientIp: '192.168.1.1',
        role: 'patient',
        digits: '7058809803',
      }),
      (err) => err.code === 'resource-exhausted' && err.message.includes('Too many OTP requests'),
    );
  });

  test('Case 9: Production demo failed verifications capped at 10 per hour; 11th failed verify rejected', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: true,
      demoOtp: '000000',
      demoPhones: { patient: ['7058809803'] },
    });

    const {
      consumeOtpChallengeAtomically,
      enforceVerifyOtpRateLimits,
      hashOtp,
    } = require('../registration_otp');
    const { Timestamp } = require('firebase-admin/firestore');

    const docs = new Map();
    const challengeKey = 'test_challenge_demo_fail_limit';

    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
          delete(ref) {
            pending.set(ref.key, null);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) {
          if (v == null) docs.delete(k);
          else docs.set(k, v);
        }
        return result;
      },
    };

    // Run 10 failed verify attempts
    for (let i = 1; i <= 10; i++) {
      // Refresh challenge document for each attempt so it's not locked by challenge-level attempts
      docs.set(`otp_challenges/${challengeKey}`, {
        role: 'patient',
        mobileDigits: '7058809803',
        otpHash: hashOtp('000000', 'patient', '7058809803'),
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
        attempts: 0,
        demoAccount: true,
      });

      await enforceVerifyOtpRateLimits(mockDb, {
        clientIp: '192.168.1.1',
        role: 'patient',
        digits: '7058809803',
      });

      await assert.rejects(
        consumeOtpChallengeAtomically(mockDb, {
          challengeKey,
          otp: '999999', // wrong OTP
          isDemoAccount: true,
          mobileDigits: '7058809803',
          role: 'patient',
        }),
        (err) => err.code === 'permission-denied',
      );
    }

    // 11th verify attempt must be rejected at enforceVerifyOtpRateLimits with resource-exhausted
    await assert.rejects(
      enforceVerifyOtpRateLimits(mockDb, {
        clientIp: '192.168.1.1',
        role: 'patient',
        digits: '7058809803',
      }),
      (err) => err.code === 'resource-exhausted' && err.message.includes('Too many invalid OTP attempts'),
    );
  });

  test('Case 10: Correct demo OTP within limits works, and successful login does not reset failure counter', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting({
      demoLoginEnabled: true,
      demoOtp: '000000',
      demoPhones: { patient: ['7058809803'] },
    });

    const {
      consumeOtpChallengeAtomically,
      enforceVerifyOtpRateLimits,
      hashOtp,
    } = require('../registration_otp');
    const { Timestamp } = require('firebase-admin/firestore');

    const docs = new Map();
    const challengeKey = 'test_challenge_demo_success';

    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
          delete(ref) {
            pending.set(ref.key, null);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) {
          if (v == null) docs.delete(k);
          else docs.set(k, v);
        }
        return result;
      },
    };

    // 1. Record 2 failed attempts
    docs.set(`otp_challenges/${challengeKey}`, {
      role: 'patient',
      mobileDigits: '7058809803',
      otpHash: hashOtp('000000', 'patient', '7058809803'),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
      attempts: 0,
      demoAccount: true,
    });
    for (let i = 0; i < 2; i++) {
      await assert.rejects(
        consumeOtpChallengeAtomically(mockDb, {
          challengeKey,
          otp: '111111',
          isDemoAccount: true,
          mobileDigits: '7058809803',
          role: 'patient',
        }),
        (err) => err.code === 'permission-denied',
      );
    }

    // 2. Perform successful login with correct demo OTP
    docs.set(`otp_challenges/${challengeKey}`, {
      role: 'patient',
      mobileDigits: '7058809803',
      otpHash: hashOtp('000000', 'patient', '7058809803'),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 600000)),
      attempts: 0,
      demoAccount: true,
    });
    const outcome = await consumeOtpChallengeAtomically(mockDb, {
      challengeKey,
      otp: '000000',
      isDemoAccount: true,
      mobileDigits: '7058809803',
      role: 'patient',
    });
    assert.equal(outcome.consumed, true);

    // 3. Verify failure counter in otp_rate_limits is STILL present (count: 2) and was NOT cleared
    let foundFailureDoc = false;
    for (const [key, val] of docs.entries()) {
      if (key.includes('verify_demo_fail_')) {
        foundFailureDoc = true;
        assert.equal(val.count, 2, 'Successful login must NOT reset failed attempt count');
      }
    }
    assert.equal(foundFailureDoc, true, 'Failed attempts document must remain in Firestore');
  });

  test('Case 11: Non-demo phone is unaffected by demo limits in production', async () => {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    delete process.env.FUNCTIONS_EMULATOR;

    setDemoConfigDocForTesting(null);

    const { enforceSendOtpRateLimits } = require('../registration_otp');
    const docs = new Map();
    const mockDb = {
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              id: docId,
              collection: collName,
              key,
              async get() {
                const data = docs.get(key);
                return { exists: data != null, data: () => data };
              },
            };
          },
        };
      },
      async runTransaction(txFn) {
        const pending = new Map();
        const tx = {
          async get(ref) {
            const data = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key);
            return { exists: data != null, data: () => data };
          },
          set(ref, data, opts) {
            const base = pending.has(ref.key) ? pending.get(ref.key) : docs.get(ref.key) || {};
            pending.set(ref.key, opts?.merge ? { ...base, ...data } : data);
          },
        };
        const result = await txFn(tx);
        for (const [k, v] of pending) docs.set(k, v);
        return result;
      },
    };

    // Standard non-demo phone send check
    await enforceSendOtpRateLimits(mockDb, {
      clientIp: '1.2.3.4',
      role: 'patient',
      digits: '9876543210',
    });

    let foundNonDemoBucket = false;
    let foundDemoBucket = false;
    for (const key of docs.keys()) {
      if (key.includes('send_mobile_')) foundNonDemoBucket = true;
      if (key.includes('send_demo_')) foundDemoBucket = true;
    }
    assert.equal(foundNonDemoBucket, true, 'Non-demo phone must write to standard send_mobile bucket');
    assert.equal(foundDemoBucket, false, 'Non-demo phone must NOT write to send_demo bucket');
  });
});


