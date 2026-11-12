#!/usr/bin/env node
/**
 * scripts/check_reviewer_config.js
 *
 * Pre-deployment verification for Google Play reviewer test accounts.
 * Reads backend/functions/.env and checks:
 * 1. Whether REVIEW_ACCESS_UNTIL exists, whether it is in the future, and days remaining.
 * 2. Whether REVIEW_TEST_NUMBERS has exactly 5 entries.
 * 3. Whether REVIEW_FIXED_OTP is configured (without printing the value).
 *
 * STRICT SECURITY RULE:
 * NEVER print or log the fixed OTP or secret credentials.
 */

'use strict';

const fs = require('fs');
const path = require('path');

function parseDotEnv(content) {
  const env = {};
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    let val = trimmed.slice(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
  return env;
}

function checkReviewerConfig(envPath) {
  console.log('================================================================');
  console.log('DOCTORNECT: REVIEWER ACCOUNT CONFIGURATION PREFLIGHT AUDIT');
  console.log('================================================================');
  console.log(`Checking env file: ${envPath}\n`);

  if (!fs.existsSync(envPath)) {
    console.error(`❌ ERROR: Env file not found at ${envPath}`);
    return { ok: false, error: 'FILE_NOT_FOUND' };
  }

  const content = fs.readFileSync(envPath, 'utf8');
  const env = parseDotEnv(content);

  let allChecksPassed = true;

  // 1. Check REVIEW_ACCESS_UNTIL
  const reviewUntilStr = (env.REVIEW_ACCESS_UNTIL || '').trim();
  if (!reviewUntilStr) {
    console.log('⚠️  REVIEW_ACCESS_UNTIL: Not configured (reviewer bypass window is inactive)');
    allChecksPassed = false;
  } else {
    const untilDate = new Date(reviewUntilStr);
    if (isNaN(untilDate.getTime())) {
      console.log(`❌ REVIEW_ACCESS_UNTIL: Invalid date format ("${reviewUntilStr}")`);
      allChecksPassed = false;
    } else {
      const now = new Date();
      const msRemaining = untilDate.getTime() - now.getTime();
      const daysRemaining = Math.ceil(msRemaining / (1000 * 60 * 60 * 24));
      const isInFuture = msRemaining > 0;

      console.log(`✓ REVIEW_ACCESS_UNTIL: Configured`);
      console.log(`  - Expiration Date: ${untilDate.toISOString()}`);
      console.log(`  - In Future: ${isInFuture ? 'YES (Valid)' : 'NO (EXPIRED)'}`);
      console.log(`  - Days Remaining: ${daysRemaining} day(s)`);

      if (!isInFuture) {
        console.log(`❌ CRITICAL: Review access date is in the past! Review accounts will fail to log in.`);
        allChecksPassed = false;
      }
    }
  }

  // 2. Check REVIEW_TEST_NUMBERS (Must have exactly 5 entries for the 5 app roles)
  const numbersStr = (env.REVIEW_TEST_NUMBERS || '').trim();
  if (!numbersStr) {
    console.log('\n⚠️  REVIEW_TEST_NUMBERS: Not configured');
    allChecksPassed = false;
  } else {
    const numbers = numbersStr
      .split(',')
      .map((n) => n.trim())
      .filter((n) => n.length > 0);

    const has5Entries = numbers.length === 5;
    console.log(`\n${has5Entries ? '✓' : '❌'} REVIEW_TEST_NUMBERS: ${numbers.length} entries detected`);
    console.log(`  - Exactly 5 entries: ${has5Entries ? 'YES' : 'NO (Expected 5 entries: Doctor, Patient, Pharmacy, Lab, Ambulance)'}`);

    if (!has5Entries) {
      allChecksPassed = false;
    }
  }

  // 3. Check REVIEW_FIXED_OTP (Presence only - NEVER print value)
  const otpStr = (env.REVIEW_FIXED_OTP || '').trim();
  const hasFixedOtp = otpStr.length > 0;
  console.log(`\n${hasFixedOtp ? '✓' : '⚠️ '} REVIEW_FIXED_OTP: ${hasFixedOtp ? 'CONFIGURED [Value Hidden]' : 'NOT CONFIGURED'}`);

  console.log('\n================================================================');
  if (allChecksPassed && hasFixedOtp) {
    console.log('✅ PREFLIGHT PASSED: Reviewer accounts are valid and active.');
    console.log('================================================================');
    return { ok: true };
  } else {
    console.log('⚠️  PREFLIGHT ADVISORY: Reviewer bypass is inactive or incomplete in this environment.');
    console.log('   Ensure REVIEW_ACCESS_UNTIL, REVIEW_TEST_NUMBERS, and REVIEW_FIXED_OTP are');
    console.log('   configured before submitting builds for Google Play review.');
    console.log('================================================================');
    return { ok: false };
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);
  let targetFile = path.resolve(__dirname, '../backend/functions/.env');
  for (const arg of args) {
    if (arg.startsWith('--env-file=')) {
      targetFile = path.resolve(arg.split('=')[1]);
    }
  }

  const result = checkReviewerConfig(targetFile);
  // Preflight check script returns 0 so it does not break local development pipelines when review accounts are dormant
  process.exit(0);
}

module.exports = { checkReviewerConfig, parseDotEnv };
