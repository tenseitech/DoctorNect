'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { razorpayWebhookHandler } = require('../promoted_ads');

const TEST_SECRET = 'test_webhook_secret_key_123';

function createMockReqRes({
  method = 'POST',
  headers = {},
  rawBody = undefined,
  body = null,
} = {}) {
  let resolvedRawBody = rawBody;
  if (resolvedRawBody === undefined && body) {
    resolvedRawBody = Buffer.from(JSON.stringify(body), 'utf8');
  }

  const req = {
    method,
    headers: { ...headers },
    rawBody: resolvedRawBody,
    body: body || (resolvedRawBody ? JSON.parse(resolvedRawBody.toString('utf8')) : null),
  };

  const res = {
    _status: 200,
    _data: null,
    _sent: false,
    status(code) {
      this._status = code;
      return this;
    },
    send(data) {
      this._data = data;
      this._sent = true;
      return this;
    },
    json(data) {
      this._data = data;
      this._sent = true;
      return this;
    },
  };

  return { req, res };
}

function computeSignature(payloadBuffer, secret = TEST_SECRET) {
  return crypto.createHmac('sha256', secret).update(payloadBuffer).digest('hex');
}

function createMockFirestore(initialData = {}) {
  const store = new Map();
  for (const [k, v] of Object.entries(initialData)) {
    store.set(k, { ...v });
  }

  function docRef(coll, id) {
    const key = `${coll}/${id}`;
    return {
      id,
      key,
      collection: coll,
      async get() {
        const d = store.get(key);
        return {
          exists: d != null,
          data: () => (d == null ? undefined : { ...d }),
        };
      },
      async set(data, options = {}) {
        if (options.merge && store.has(key)) {
          store.set(key, { ...store.get(key), ...data });
        } else {
          store.set(key, { ...data });
        }
      },
      async update(data) {
        if (!store.has(key)) throw new Error(`Doc ${key} does not exist`);
        store.set(key, { ...store.get(key), ...data });
      },
      async delete() {
        store.delete(key);
      },
    };
  }

  return {
    store,
    collection(name) {
      return {
        doc(id) {
          return docRef(name, id);
        },
      };
    },
    async runTransaction(updateFunction) {
      const tx = {
        async get(ref) {
          return await ref.get();
        },
        set(ref, data, options) {
          if (options && options.merge && store.has(ref.key)) {
            store.set(ref.key, { ...store.get(ref.key), ...data });
          } else {
            store.set(ref.key, { ...data });
          }
        },
        update(ref, data) {
          if (!store.has(ref.key)) throw new Error(`Doc ${ref.key} does not exist`);
          store.set(ref.key, { ...store.get(ref.key), ...data });
        },
        delete(ref) {
          store.delete(ref.key);
        },
      };
      return await updateFunction(tx);
    },
  };
}

test('Razorpay Webhook Security Suite', async (t) => {
  process.env.RAZORPAY_WEBHOOK_SECRET = TEST_SECRET;

  // 24 hours -> 300 INR -> 30000 paise in AD_PRICING_TABLE
  const validPayload = {
    event: 'payment.captured',
    payload: {
      payment: {
        entity: {
          id: 'pay_valid_123',
          order_id: 'order_valid_123',
          amount: 30000,
          currency: 'INR',
          notes: {
            adId: 'ad_101',
            providerUid: 'provider_user_1',
            durationHours: '24',
          },
        },
      },
      order: {
        entity: {
          id: 'order_valid_123',
          amount: 30000,
          currency: 'INR',
          notes: {
            adId: 'ad_101',
            providerUid: 'provider_user_1',
            durationHours: '24',
          },
        },
      },
    },
  };

  const initialDbData = {
    'promotedAds/ad_101': {
      status: 'pending_payment',
      providerId: 'provider_user_1',
      razorpayOrderId: 'order_valid_123',
    },
    'users/provider_user_1': {
      profileId: 'provider_user_1',
    },
  };

  await t.test('1. missing x-razorpay-signature header -> 400', async () => {
    const db = createMockFirestore(initialDbData);
    const { req, res } = createMockReqRes({ body: validPayload });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 400);
    assert.equal(res._data, 'Missing webhook signature.');
  });

  await t.test('2. bad signature -> 400 (rejected)', async () => {
    const db = createMockFirestore(initialDbData);
    const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': '0000000000000000000000000000000000000000000000000000000000000000' },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 400);
    assert.equal(res._data, 'Invalid webhook signature.');
  });

  await t.test('3. missing RAZORPAY_WEBHOOK_SECRET -> 503', async () => {
    delete process.env.RAZORPAY_WEBHOOK_SECRET;
    try {
      const db = createMockFirestore(initialDbData);
      const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req, res } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig },
        rawBody: raw,
        body: validPayload,
      });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 503);
    } finally {
      process.env.RAZORPAY_WEBHOOK_SECRET = TEST_SECRET;
    }
  });

  await t.test('4. missing rawBody -> 400', async () => {
    const db = createMockFirestore(initialDbData);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': 'abc' },
      rawBody: null,
      body: null,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 400);
    assert.equal(res._data, 'Missing raw request body.');
  });

  await t.test('5. valid signature + payment.captured -> 200 success', async () => {
    const db = createMockFirestore(initialDbData);
    const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: {
        'x-razorpay-signature': sig,
        'x-razorpay-event-id': 'evt_first_123',
      },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.success, true);
    assert.equal(res._data.idempotent, false);

    const updatedAd = db.store.get('promotedAds/ad_101');
    assert.equal(updatedAd.status, 'pending_approval');
    assert.equal(updatedAd.razorpayPaymentId, 'pay_valid_123');
  });

  await t.test('6. duplicate event_id (idempotent) -> 200 idempotent: true', async () => {
    const db = createMockFirestore(initialDbData);
    const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req: req1, res: res1 } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig, 'x-razorpay-event-id': 'evt_idem_999' },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req1, res1, db);
    assert.equal(res1._status, 200);
    assert.equal(res1._data.idempotent, false);

    // Replay same event id
    const { req: req2, res: res2 } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig, 'x-razorpay-event-id': 'evt_idem_999' },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req2, res2, db);
    assert.equal(res2._status, 200);
    assert.equal(res2._data.idempotent, true);
  });

  await t.test('7. amount mismatch -> recorded rejection', async () => {
    const db = createMockFirestore(initialDbData);
    const tamperedPayload = JSON.parse(JSON.stringify(validPayload));
    tamperedPayload.payload.payment.entity.amount = 10000; // Expected 30000 for 24h
    tamperedPayload.payload.order.entity.amount = 10000;
    const raw = Buffer.from(JSON.stringify(tamperedPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig },
      rawBody: raw,
      body: tamperedPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.status, 'rejected');
    assert.equal(res._data.reason, 'amount_mismatch');
  });

  await t.test('8. currency not INR -> rejection', async () => {
    const db = createMockFirestore(initialDbData);
    const usdPayload = JSON.parse(JSON.stringify(validPayload));
    usdPayload.payload.payment.entity.currency = 'USD';
    usdPayload.payload.order.entity.currency = 'USD';
    const raw = Buffer.from(JSON.stringify(usdPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig },
      rawBody: raw,
      body: usdPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.status, 'rejected');
    assert.equal(res._data.reason, 'currency_mismatch');
  });

  await t.test('9. ad owned by someone else -> permission_denied rejection', async () => {
    const db = createMockFirestore({
      ...initialDbData,
      'promotedAds/ad_101': {
        status: 'pending_payment',
        providerId: 'actual_owner_888',
        razorpayOrderId: 'order_valid_123',
      },
      'users/provider_user_1': {
        profileId: 'provider_user_1',
      },
    });
    const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.status, 'rejected');
    assert.equal(res._data.reason, 'permission-denied');
  });

  await t.test('10. double webhook for same paymentId with different ad -> already_used rejection', async () => {
    const db = createMockFirestore({
      ...initialDbData,
      'razorpayPayments/pay_valid_123': {
        adId: 'different_ad_999',
        orderId: 'order_other_111',
      },
    });
    const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig },
      rawBody: raw,
      body: validPayload,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.status, 'rejected');
    assert.equal(res._data.reason, 'payment_already_used');
  });

  await t.test('11. non payment.captured / order.paid event type -> 200 ignored', async () => {
    const db = createMockFirestore(initialDbData);
    const otherEvent = { event: 'refund.processed', payload: {} };
    const raw = Buffer.from(JSON.stringify(otherEvent), 'utf8');
    const sig = computeSignature(raw, TEST_SECRET);
    const { req, res } = createMockReqRes({
      headers: { 'x-razorpay-signature': sig },
      rawBody: raw,
      body: otherEvent,
    });
    await razorpayWebhookHandler(req, res, db);
    assert.equal(res._status, 200);
    assert.equal(res._data.status, 'ignored');
  });
});
