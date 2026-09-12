'use strict';

/**
 * Centralized secret / config access for Cloud Functions.
 *
 * Production: bind secrets with Google Secret Manager, e.g.
 *   firebase functions:secrets:set MSG91_AUTHKEY
 *   firebase functions:secrets:set RAZORPAY_KEY_SECRET
 *
 * Then declare them on each function via `secrets: [...]` (see MSG91_SECRETS /
 * PAYMENT_SECRETS below). Bound secrets appear in process.env at runtime.
 *
 * Local emulator: put values in functions/.secret.local (gitignored), not in
 * the Flutter app or dart-define. Never log raw secret values.
 */

const { defineSecret } = require('firebase-functions/params');

/** MSG91 SMS auth key (server-only). */
const MSG91_AUTHKEY = defineSecret('MSG91_AUTHKEY');

/** Bind to OTP / MSG91 callables. */
const MSG91_SECRETS = [MSG91_AUTHKEY];

/** Payment secrets (see promoted_ads.js). */
const PAYMENT_SECRETS = [];

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
  MSG91_AUTHKEY,
  MSG91_SECRETS,
  PAYMENT_SECRETS,
  readSecret,
  readMsg91AuthKey,
  isProduction,
  assertProductionSecrets,
};
