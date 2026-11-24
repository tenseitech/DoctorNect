'use strict';

const { defineSecret } = require('firebase-functions/params');

/** Play Store / reviewer fixed OTP — Secret Manager only (not in materialized .env). */
const reviewFixedOtp = defineSecret('REVIEW_FIXED_OTP');

module.exports = {
  reviewFixedOtp,
};