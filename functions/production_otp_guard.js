'use strict';

/** Deployed Firebase project IDs that must never run OTP test/demo backdoors. */
const PRODUCTION_PROJECT_IDS = ['medibond-45fad'];

const DEMO_PHONE_ENV_KEYS = [
  'DEMO_PHONE_PATIENT',
  'GOOGLE_PLAY_REVIEW_PHONE',
  'TEST_PHONE_NUMBER',
  'DEMO_PHONE_DOCTOR',
  'DEMO_PHONE_MEDICAL_STORE',
  'DEMO_PHONE_PHARMACY',
  'DEMO_PHONE_LAB',
  'DEMO_PHONE_AMBULANCE',
];

function resolveFirebaseProjectId(env = process.env) {
  const direct = String(env.GCLOUD_PROJECT || env.GOOGLE_CLOUD_PROJECT || '').trim();
  if (direct) {
    return direct;
  }
  try {
    const parsed = JSON.parse(String(env.FIREBASE_CONFIG || '{}'));
    return String(parsed.projectId || '').trim();
  } catch (_) {
    return '';
  }
}

function isProductionFirebaseProject(
  env = process.env,
  productionProjectIds = PRODUCTION_PROJECT_IDS,
) {
  const projectId = resolveFirebaseProjectId(env);
  return productionProjectIds.includes(projectId);
}

/** True when code is executing inside deployed Cloud Functions / Cloud Run. */
function isCloudFunctionsRuntime(env = process.env) {
  return Boolean(
    env.K_SERVICE
    || env.FUNCTION_TARGET
    || env.FUNCTION_NAME,
  );
}

function isFunctionsEmulator(env = process.env) {
  return String(env.FUNCTIONS_EMULATOR || '').trim().toLowerCase() === 'true';
}

function isOtpTestModeConfigured(env = process.env) {
  const mode = String(env.OTP_TEST_MODE || '').trim().toLowerCase();
  return mode === 'true' || mode === '1';
}

function listConfiguredDemoPhoneEnvKeys(env = process.env) {
  return DEMO_PHONE_ENV_KEYS.filter((key) => String(env[key] || '').trim().length > 0);
}

function collectProductionOtpViolations(
  env = process.env,
  productionProjectIds = PRODUCTION_PROJECT_IDS,
) {
  if (!isProductionFirebaseProject(env, productionProjectIds)) {
    return [];
  }

  const violations = [];
  if (isOtpTestModeConfigured(env)) {
    violations.push('OTP_TEST_MODE is enabled');
  }

  const demoKeys = listConfiguredDemoPhoneEnvKeys(env);
  if (demoKeys.length > 0) {
    violations.push(`demo phone env configured (${demoKeys.join(', ')})`);
  }

  return violations;
}

function logCriticalOtpSecurityEvent(action, detail, extra = {}) {
  console.error(JSON.stringify({
    securityEvent: true,
    severity: 'CRITICAL',
    category: 'config',
    action,
    detail,
    ...extra,
  }));
}

/**
 * Hard fail on cold start when test/demo OTP backdoors are configured in production.
 * Skipped during local deploy analysis and the Functions emulator so dev `.env` files
 * with demo numbers do not block `firebase deploy`.
 */
function assertProductionOtpSafety(
  env = process.env,
  { productionProjectIds = PRODUCTION_PROJECT_IDS } = {},
) {
  const projectId = resolveFirebaseProjectId(env);
  if (!isCloudFunctionsRuntime(env) || isFunctionsEmulator(env)) {
    return { projectId, blocked: false, skipped: true };
  }

  const violations = collectProductionOtpViolations(env, productionProjectIds);
  if (violations.length === 0) {
    return { projectId, blocked: false };
  }

  const detail = violations.join('; ');
  logCriticalOtpSecurityEvent('production_otp_backdoor_blocked', detail, { projectId });
  const err = new Error(`Production OTP safety check failed for ${projectId}: ${detail}`);
  err.code = 'failed-precondition';
  throw err;
}

module.exports = {
  PRODUCTION_PROJECT_IDS,
  DEMO_PHONE_ENV_KEYS,
  resolveFirebaseProjectId,
  isProductionFirebaseProject,
  isCloudFunctionsRuntime,
  isFunctionsEmulator,
  isOtpTestModeConfigured,
  listConfiguredDemoPhoneEnvKeys,
  collectProductionOtpViolations,
  assertProductionOtpSafety,
};
