'use strict';

/**
 * Demo accounts (lib/demo_accounts.js) can never: use live Razorpay keys, touch RDS, use the
 * production S3 prefix, or trigger e-mail/SMS to outside recipients.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { DEMO_ACCOUNTS } = require('../lib/demo_accounts');
const promotedAds = require('../promoted_ads');
const { resolveDataPlane, objectStoragePrefix, isDemoFirebaseUid } = require('../lib/demo_routing');
const { assertDemoUidNotOnRds } = require('../../../scripts/lib/rds_demo_uid_guard');
const { processMailQueue } = require('../mail_dispatcher');
const { shouldSkipMsg91ForPhone } = require('../registration_otp');

const KEYS = ['RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET', 'RAZORPAY_TEST_KEY_ID', 'RAZORPAY_TEST_KEY_SECRET',
  'APP_ENV', 'DEMO_REAL_ROUTING_ENABLED', 'DEMO_FIREBASE_UID_ALLOWLIST'];
let saved;
test.beforeEach(() => {
  saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  for (const k of KEYS) delete process.env[k];
});
test.afterEach(() => {
  for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
});

const demoUid = DEMO_ACCOUNTS[0].uid;

test('demo accounts never get live Razorpay keys', () => {
  process.env.RAZORPAY_KEY_ID = 'rzp_live_realkey';
  process.env.RAZORPAY_KEY_SECRET = 'live-secret';
  assert.throws(() => promotedAds.getRazorpayCredentials(demoUid), (e) => e.code === 'failed-precondition');
  process.env.RAZORPAY_TEST_KEY_ID = 'rzp_live_mislabelled';
  process.env.RAZORPAY_TEST_KEY_SECRET = 'x';
  assert.throws(() => promotedAds.getRazorpayCredentials(demoUid), (e) => e.code === 'failed-precondition',
    'a "test" slot holding a live key is refused');
  process.env.RAZORPAY_TEST_KEY_ID = 'rzp_test_demo';
  process.env.RAZORPAY_TEST_KEY_SECRET = 'test-secret';
  const c = promotedAds.getRazorpayCredentials(demoUid);
  assert.equal(c.keyId, 'rzp_test_demo');
  assert.equal(c.testMode, true);
  const real = promotedAds.getRazorpayCredentials('real_user_uid');
  assert.equal(real.keyId, 'rzp_live_realkey', 'real users keep the live keys');
});

test('staging (main keys are test keys) works for demo accounts', () => {
  process.env.RAZORPAY_KEY_ID = 'rzp_test_staging';
  process.env.RAZORPAY_KEY_SECRET = 's';
  assert.equal(promotedAds.getRazorpayCredentials(demoUid).keyId, 'rzp_test_staging');
});

test('createRazorpayOrder for a demo account refuses before any Razorpay call when only live keys exist', async () => {
  process.env.RAZORPAY_KEY_ID = 'rzp_live_realkey';
  process.env.RAZORPAY_KEY_SECRET = 'live-secret';
  const { createPromotedAdsSupabaseMock } = require('./helpers/promoted_ads_supabase_mock');
  const sb = createPromotedAdsSupabaseMock({
    ads: { ad_1: { ad_id: 'ad_1', provider_id: demoUid, status: 'draft', duration_hours: 24 } },
    users: { [demoUid]: { id: demoUid, firebase_uid: demoUid, role: 'doctor', profile_id: demoUid } },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  const https = require('https');
  const orig = https.request;
  let called = false;
  https.request = () => { called = true; throw new Error('must not call Razorpay'); };
  try {
    await assert.rejects(
      promotedAds.createRazorpayOrder.run({ auth: { uid: demoUid }, app: { appId: 'x' }, data: { adId: 'ad_1', durationHours: 24 } }),
      (e) => e.code === 'failed-precondition',
    );
    assert.equal(called, false);
  } finally {
    https.request = orig;
    promotedAds.setSupabaseClientForTesting(null);
  }
});

test('demo UIDs always use the staging plane and demo/ S3 prefix in production, never RDS', () => {
  for (const a of DEMO_ACCOUNTS) {
    for (const routing of [undefined, '1']) {
      const env = { APP_ENV: 'production', ...(routing ? { DEMO_REAL_ROUTING_ENABLED: routing } : {}) };
      assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: a.uid, env }), 'supabase', a.uid);
      assert.equal(objectStoragePrefix({ appEnv: 'production', firebaseUid: a.uid, env }), 'demo/', a.uid);
      assert.equal(isDemoFirebaseUid(a.uid, env), true);
      assert.throws(() => assertDemoUidNotOnRds(a.uid, env), (e) => e.code === 'demo_uid_rds_forbidden');
    }
  }
  assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: 'real_uid', env: { APP_ENV: 'production' } }), 'rds');
});

test('no SMS for demo numbers; mail dispatcher never sends to .invalid addresses', async () => {
  for (const a of DEMO_ACCOUNTS) assert.equal(shouldSkipMsg91ForPhone(a.digits), true);
  const updates = [];
  const sent = [];
  const sb = {
    from() {
      const q = {
        select: () => q, eq: () => q, order: () => q,
        limit: async () => ({
          data: [
            { mail_id: 'm1', to_address: 'rev_fb_doc_001@demo.doctornect.invalid', subject: 's', attempts: 0 },
            { mail_id: 'm2', to_address: 'someone@example.com', subject: 's', attempts: 0 },
          ],
          error: null,
        }),
        update: (patch) => ({ eq: async (_c, id) => { updates.push({ id, ...patch }); return { error: null }; } }),
      };
      return q;
    },
  };
  const res = await processMailQueue({ supabase: sb, sendEmail: async ({ toEmail }) => { sent.push(toEmail); } });
  assert.deepEqual(sent, ['someone@example.com']);
  assert.equal(updates.find((u) => u.id === 'm1').status, 'failed');
  assert.equal(res.sent, 1);
});
