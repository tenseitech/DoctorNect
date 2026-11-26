'use strict';

const { defineSecret } = require('firebase-functions/params');

/**
 * Dedicated OTP HMAC pepper (48 random bytes, base64). Secret Manager only: bound to the OTP
 * send/verify callables through OTP_DATA_PLANE_SECRETS in index.js, so it is injected as
 * process.env.OTP_HMAC_SECRET there and never materialized into the deployed .env.
 */
const otpHmacSecret = defineSecret('OTP_HMAC_SECRET');

module.exports = { otpHmacSecret };
