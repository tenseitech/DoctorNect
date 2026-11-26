'use strict';

/**
 * verifyRazorpayPayment on the Postgres path (replaces the Firestore-only
 * promoted_ads_verification.test.js): signature, ownership, order binding, notes binding,
 * server-side pricing, replay idempotency and payment re-use.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const https = require('https');
const { EventEmitter } = require('events');

const promotedAds = require('../promoted_ads');
const { createPromotedAdsSupabaseMock } = require('./helpers/promoted_ads_supabase_mock');

const SECRET = 'unit_verify_secret';
const ORDER = 'order_verify_0001';
const PAY = 'pay_verify_00001';

function sign(orderId, paymentId) {
  return crypto.createHmac('sha256', SECRET).update(`${orderId}|${paymentId}`).digest('hex');
}

function mockRazorpay({ payment = {}, order = {} } = {}) {
  const original = https.request;
  const sent = [];
  https.request = (options, cb) => {
    const req = new EventEmitter();
    req.write = () => {};
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.end = () => {
      sent.push(options.path);
      const res = new EventEmitter();
      res.statusCode = 200;
      cb(res);
      const isPayment = options.path.startsWith('/v1/payments/');
      const body = isPayment
        ? { id: PAY, status: 'captured', order_id: ORDER, amount: 30000, currency: 'INR', ...payment }
        : { id: ORDER, notes: { adId: 'ad_1', providerUid: 'doc_uid', durationHours: '24' }, ...order };
      res.emit('data', JSON.stringify(body));
      res.emit('end');
    };
    return req;
  };
  return { sent, restore: () => { https.request = original; } };
}

function setup(adOverrides = {}) {
  const sb = createPromotedAdsSupabaseMock({
    ads: {
      ad_1: { ad_id: 'ad_1', provider_id: 'doc_uid', status: 'pending_payment', razorpay_order_id: ORDER, ...adOverrides },
      ad_2: { ad_id: 'ad_2', provider_id: 'doc_uid', status: 'pending_payment', razorpay_order_id: 'order_verify_0002' },
    },
    users: {
      doc_uid: { id: 'doc_uid', firebase_uid: 'doc_uid', role: 'doctor', profile_id: 'doc_uid' },
      other_uid: { id: 'other_uid', firebase_uid: 'other_uid', role: 'doctor', profile_id: 'other_uid' },
    },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  return sb;
}

function call(uid, data) {
  return promotedAds.verifyRazorpayPayment.run({ auth: { uid }, app: { appId: 'x' }, data });
}

const good = () => ({ adId: 'ad_1', orderId: ORDER, paymentId: PAY, signature: sign(ORDER, PAY) });

let prev;
test.beforeEach(() => {
  prev = { id: process.env.RAZORPAY_KEY_ID, secret: process.env.RAZORPAY_KEY_SECRET };
  process.env.RAZORPAY_KEY_ID = 'rzp_test_unit';
  process.env.RAZORPAY_KEY_SECRET = SECRET;
});
test.afterEach(() => {
  promotedAds.setSupabaseClientForTesting(null);
  for (const [k, v] of [['RAZORPAY_KEY_ID', prev.id], ['RAZORPAY_KEY_SECRET', prev.secret]]) {
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
});

test('valid payment moves the ad to pending_approval with server-side price; replay is idempotent', async () => {
  const sb = setup();
  const http = mockRazorpay();
  try {
    const first = await call('doc_uid', good());
    assert.equal(first.success, true);
    assert.equal(first.idempotent, false);
    const ad = sb.ads.get('ad_1');
    assert.equal(ad.status, 'pending_approval');
    assert.equal(ad.payment_status, 'verified');
    assert.equal(ad.amount_paid, 300);
    assert.equal(ad.razorpay_payment_id, PAY);
    assert.equal(sb.payments.get(PAY).order_id, ORDER);

    const replay = await call('doc_uid', good());
    assert.equal(replay.idempotent, true);
    assert.equal(sb.ads.get('ad_1').status, 'pending_approval');
  } finally {
    http.restore();
  }
});

test('bad signature is rejected before any gateway call or DB write', async () => {
  const sb = setup();
  const http = mockRazorpay();
  try {
    await assert.rejects(call('doc_uid', { ...good(), signature: 'a'.repeat(64) }), (e) => e.code === 'invalid-argument');
    assert.deepEqual(http.sent, []);
    assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
    assert.equal(sb.payments.size, 0);
  } finally {
    http.restore();
  }
});

test('non-owner cannot verify a payment for someone else\'s ad', async () => {
  const sb = setup();
  const http = mockRazorpay();
  try {
    await assert.rejects(call('other_uid', good()), (e) => e.code === 'permission-denied');
    assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
  } finally {
    http.restore();
  }
});

test('order id must match the order stored on the ad', async () => {
  setup();
  const http = mockRazorpay();
  try {
    const otherOrder = 'order_verify_0002';
    await assert.rejects(
      call('doc_uid', { adId: 'ad_1', orderId: otherOrder, paymentId: PAY, signature: sign(otherOrder, PAY) }),
      (e) => e.code === 'invalid-argument',
    );
  } finally {
    http.restore();
  }
});

test('order notes bound to another ad/provider, uncaptured payment, or underpaid amount are rejected', async () => {
  const cases = [
    { order: { notes: { adId: 'ad_2', providerUid: 'doc_uid', durationHours: '24' } } },
    { order: { notes: { adId: 'ad_1', providerUid: 'other_uid', durationHours: '24' } } },
    { payment: { status: 'authorized' } },
    { payment: { amount: 100 } },
    { payment: { currency: 'USD' } },
  ];
  for (const c of cases) {
    const sb = setup();
    const http = mockRazorpay(c);
    try {
      await assert.rejects(call('doc_uid', good()), (e) => e.code === 'failed-precondition', JSON.stringify(c));
      assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
    } finally {
      http.restore();
    }
  }
});

test('a payment already used for one ad cannot activate another ad', async () => {
  const sb = setup();
  sb.payments.set(PAY, { payment_id: PAY, order_id: 'order_verify_0002' });
  const http = mockRazorpay();
  try {
    await assert.rejects(call('doc_uid', good()), (e) => e.code === 'already-exists');
    assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
  } finally {
    http.restore();
  }
});
