'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const {
  PRODUCTION_PROJECT_IDS,
  assertProductionOtpSafety,
  collectProductionOtpViolations,
  isProductionFirebaseProject,
} = require('../production_otp_guard');

const PROD_PROJECT = PRODUCTION_PROJECT_IDS[0];

function baseEnv(overrides = {}) {
  return {
    GCLOUD_PROJECT: 'demo-doctornect-local',
    OTP_TEST_MODE: 'false',
    ...overrides,
  };
}

function cloudRuntimeEnv(overrides = {}) {
  return baseEnv({
    K_SERVICE: 'getvalidationrules',
    ...overrides,
  });
}

test('production OTP guard allows test/demo config outside production project', () => {
  const env = baseEnv({
    OTP_TEST_MODE: 'true',
    DEMO_PHONE_PATIENT: '9359503874',
  });

  assert.equal(isProductionFirebaseProject(env), false);
  assert.deepEqual(collectProductionOtpViolations(env), []);
  assert.doesNotThrow(() => assertProductionOtpSafety(env));
});

test('production OTP guard skips local deploy analysis even with prod project env', () => {
  const env = baseEnv({
    GCLOUD_PROJECT: PROD_PROJECT,
    OTP_TEST_MODE: 'true',
    DEMO_PHONE_PATIENT: '9359503874',
  });

  assert.doesNotThrow(() => assertProductionOtpSafety(env));
});

test('production OTP guard blocks cold start when OTP_TEST_MODE is enabled', () => {
  const env = cloudRuntimeEnv({
    GCLOUD_PROJECT: PROD_PROJECT,
    OTP_TEST_MODE: 'true',
  });

  assert.throws(
    () => assertProductionOtpSafety(env),
    (err) => err.message.includes('OTP_TEST_MODE is enabled')
      && err.message.includes(PROD_PROJECT),
  );
});

test('production OTP guard blocks cold start when demo phone env is configured', () => {
  const env = cloudRuntimeEnv({
    GCLOUD_PROJECT: PROD_PROJECT,
    DEMO_PHONE_DOCTOR: '9876543210',
  });

  assert.throws(
    () => assertProductionOtpSafety(env),
    (err) => err.message.includes('demo phone env configured')
      && err.message.includes('DEMO_PHONE_DOCTOR'),
  );
});

test('registration OTP backdoors are disabled on production project', async () => {
  const savedEnv = {
    GCLOUD_PROJECT: process.env.GCLOUD_PROJECT,
    OTP_TEST_MODE: process.env.OTP_TEST_MODE,
    DEMO_PHONE_PATIENT: process.env.DEMO_PHONE_PATIENT,
  };

  try {
    process.env.GCLOUD_PROJECT = PROD_PROJECT;
    process.env.OTP_TEST_MODE = 'true';
    process.env.DEMO_PHONE_PATIENT = '9359503874';

    for (const modulePath of [
      '../production_otp_guard',
      '../registration_otp',
    ]) {
      delete require.cache[require.resolve(modulePath)];
    }

    const { isTestMode, isDemoPhone } = require('../registration_otp');
    assert.equal(isTestMode(), false);
    assert.equal(await isDemoPhone('9359503874', 'patient'), false);
  } finally {
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    for (const modulePath of [
      '../production_otp_guard',
      '../registration_otp',
    ]) {
      delete require.cache[require.resolve(path.join(__dirname, modulePath))];
    }
  }
});
