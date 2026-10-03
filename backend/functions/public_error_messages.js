'use strict';

const { HttpsError } = require('firebase-functions/v2/https');

const GENERIC_ACCOUNT_LOOKUP_FAILED = 'Could not verify account. Please try again.';
const GENERIC_PASSWORD_UPDATE_FAILED = 'Could not update password. Please try again.';
const GENERIC_MOBILE_LOGIN_FAILED = 'Could not complete login. Please try again.';
const GENERIC_AMBULANCE_LOGIN_FAILED = 'Could not verify ambulance login. Please try again.';

/** Never expose internal error details to clients. */
function clientFacingHttpsMessage(err, fallback) {
  if (!(err instanceof HttpsError)) return fallback;
  if (err.code === 'internal') return fallback;
  return err.message || fallback;
}

function logInternalError(scope, err, context = {}) {
  console.error(`[${scope}] Internal error`, { ...context, error: err });
}

module.exports = {
  GENERIC_ACCOUNT_LOOKUP_FAILED,
  GENERIC_PASSWORD_UPDATE_FAILED,
  GENERIC_MOBILE_LOGIN_FAILED,
  GENERIC_AMBULANCE_LOGIN_FAILED,
  clientFacingHttpsMessage,
  logInternalError,
};
