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
});
