'use strict';

/**
 * Centralized secret / config access for Cloud Functions.
 *
 * All secrets are now strictly loaded via `functions/.env` files.
 * Firebase Secret Manager bindings have been removed to resolve overlap crashes.
 */

// No more defineSecret

function readSecret(name, { required = false } = {}) {
  const value = String(process.env[name] || '').trim();
  if (required && !value) {
    const err = new Error(`Missing required secret: ${name}`);
    err.code = 'failed-precondition';
    throw err;
  }
  return value;
}

/** Resolves MSG91 auth key from Secret Manager binding or local env aliases. */
function readMsg91AuthKey({ required = true } = {}) {
  const value = String(
    process.env.MSG91_AUTHKEY ||
      process.env.MSG91_AUTH_KEY ||
      process.env.AUTH_KEY ||
      '',
  ).trim();
  if (required && !value) {
    const err = new Error('Missing required secret: MSG91_AUTHKEY');
    err.code = 'failed-precondition';
    throw err;
  }
  return value;
}

function isProduction() {
  return String(process.env.FUNCTION_TARGET || '').length > 0
    && String(process.env.OTP_TEST_MODE || '').toLowerCase() !== 'true';
}

function assertProductionSecrets() {
  if (String(process.env.OTP_TEST_MODE || '').trim().toLowerCase() === 'true') {
    console.warn(JSON.stringify({
      securityEvent: true,
      severity: 'WARNING',
      category: 'config',
      action: 'otp_test_mode_enabled',
      detail: 'OTP_TEST_MODE=true — disable in production',
    }));
  }
  if (String(process.env.ENFORCE_OTP_APP_CHECK || 'true').toLowerCase() === 'false') {
    console.warn(JSON.stringify({
      securityEvent: true,
      severity: 'WARNING',
      category: 'config',
      action: 'app_check_disabled',
      detail: 'ENFORCE_OTP_APP_CHECK=false — enable in production',
    }));
  }
}

module.exports = {
  readSecret,
  readMsg91AuthKey,
  isProduction,
  assertProductionSecrets,
};
