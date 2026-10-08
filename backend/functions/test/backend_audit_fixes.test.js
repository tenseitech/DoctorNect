'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

test('H-9: Firestore triggers default to asia-south1 and no asia-south2 remains in index.js', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(
    src,
    /FIRESTORE_TRIGGER_REGION = String\(process\.env\.FIRESTORE_TRIGGER_REGION \|\| 'asia-south1'\)/,
  );
  assert.equal(src.includes('asia-south2'), false);
  assert.match(src, /region: FIRESTORE_TRIGGER_REGION/);
});

test('H-6: REDIS_SECRETS bind only when OTP_REDIS_MIRROR is on', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(src, /OTP_REDIS_MIRROR_ON = String\(process\.env\.OTP_REDIS_MIRROR \|\| ''\)\.trim\(\)\.toLowerCase\(\) === 'on'/);
  assert.match(src, /secrets: require\('\.\/redis'\)\.REDIS_SECRETS/);
  assert.match(src, /\.\.\.OTP_REDIS_SECRET_OPTIONS/);
});

test('M-5: lookupMobileRegistration and Razorpay callables enforce App Check', () => {
  const indexSrc = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(
    indexSrc,
    /exports\.lookupMobileRegistration = onCall\(\s*\{\s*region: CALLABLE_REGION, enforceAppCheck: ENFORCE_ABUSE_APP_CHECK/,
  );

  const adsSrc = fs.readFileSync(path.join(__dirname, '../promoted_ads.js'), 'utf8');
  assert.match(adsSrc, /enforceAppCheck: ENFORCE_ABUSE_APP_CHECK/);
  assert.match(adsSrc, /const createRazorpayOrder = onCall\(/);
  assert.match(adsSrc, /const verifyRazorpayPayment = onCall\(/);
});

test('H-4: deleteMyAccount binds Supabase service-role secrets', () => {
  const src = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.match(src, /secrets: \[awsAccessKeyId, awsSecretAccessKey, supabaseUrl, supabaseServiceRoleKey\]/);
});

test('H-7: paid ads go to pending_approval and live queries use status == active', () => {
  const src = fs.readFileSync(path.join(__dirname, '../promoted_ads.js'), 'utf8');
  assert.match(src, /status: 'pending_approval'/);
  assert.match(src, /where\('status', '==', 'active'\)/);
  assert.match(src, /async function reviewPromotedAdHandler/);
});
