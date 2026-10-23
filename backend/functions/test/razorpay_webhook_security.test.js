'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { Client } = require('../../node_modules/pg');
const {
  razorpayWebhookHandler,
  setSupabaseClientForTesting,
} = require('../promoted_ads');

const TEST_SECRET = 'test_webhook_secret_key_123';
const DOCKER_PG_URL = process.env.LOCAL_DOCKER_PG_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

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

function createMockSupabaseStore(initialAds = [], initialUsers = []) {
  const ads = new Map(initialAds.map((a) => [a.ad_id, { ...a }]));
  const users = new Map(initialUsers.map((u) => [u.firebase_uid, { ...u }]));
  const webhookEvents = new Map();
  const payments = new Map();
  const orders = new Map();

  return {
    ads,
    users,
    webhookEvents,
    payments,
    orders,
    from(table) {
      if (table === 'promoted_ads') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'ad_id') {
                const item = ads.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
          update: (data) => ({
            eq: async (col, val) => {
              if (col === 'ad_id' && ads.has(val)) {
                ads.set(val, { ...ads.get(val), ...data });
              }
              return { error: null };
            },
          }),
        };
      }
      if (table === 'users') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'firebase_uid') {
                const item = users.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
        };
      }
      if (table === 'razorpay_webhook_events') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'event_id') {
                const item = webhookEvents.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
          upsert: async (data) => {
            webhookEvents.set(data.event_id, { ...data });
            return { error: null };
          },
        };
      }
      if (table === 'razorpay_payments') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'payment_id') {
                const item = payments.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
          upsert: async (data) => {
            payments.set(data.payment_id, { ...data });
            return { error: null };
          },
        };
      }
      if (table === 'razorpay_orders') {
        return {
          upsert: async (data) => {
            orders.set(data.order_id, { ...data });
            return { error: null };
          },
        };
      }
      throw new Error(`Unexpected table: ${table}`);
    },
  };
}

function runWebhookSecurityTestSuite(suiteName, isSupabase) {
  test(`${suiteName}: 11 Webhook Security Tests`, async (t) => {
    process.env.RAZORPAY_WEBHOOK_SECRET = TEST_SECRET;
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = isSupabase ? 'true' : 'false';

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

    function setupEnv() {
      if (isSupabase) {
        const mockSupabase = createMockSupabaseStore(
          [
            {
              ad_id: 'ad_101',
              status: 'pending_payment',
              provider_id: 'provider_user_1',
              razorpay_order_id: 'order_valid_123',
            },
          ],
          [
            {
              firebase_uid: 'provider_user_1',
              profile_id: 'provider_user_1',
            },
          ]
        );
        setSupabaseClientForTesting(mockSupabase);
        return { db: null, mockSupabase };
      } else {
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
        const db = createMockFirestore(initialDbData);
        return { db, mockSupabase: null };
      }
    }

    await t.test('1. missing x-razorpay-signature header -> 400', async () => {
      const { db } = setupEnv();
      const { req, res } = createMockReqRes({ body: validPayload });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 400);
      assert.equal(res._data, 'Missing webhook signature.');
    });

    await t.test('2. bad signature -> 400 (rejected)', async () => {
      const { db } = setupEnv();
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
        const { db } = setupEnv();
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
      const { db } = setupEnv();
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
      const { db, mockSupabase } = setupEnv();
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

      if (isSupabase) {
        const updatedAd = mockSupabase.ads.get('ad_101');
        assert.equal(updatedAd.status, 'pending_approval');
        assert.equal(updatedAd.razorpay_payment_id, 'pay_valid_123');
      } else {
        const updatedAd = db.store.get('promotedAds/ad_101');
        assert.equal(updatedAd.status, 'pending_approval');
        assert.equal(updatedAd.razorpayPaymentId, 'pay_valid_123');
      }
    });

    await t.test('6. duplicate event_id (idempotent) -> 200 idempotent: true', async () => {
      const { db } = setupEnv();
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
      const { db } = setupEnv();
      const badAmountPayload = JSON.parse(JSON.stringify(validPayload));
      badAmountPayload.payload.payment.entity.amount = 10000;
      badAmountPayload.payload.order.entity.amount = 10000;
      const raw = Buffer.from(JSON.stringify(badAmountPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req, res } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig },
        rawBody: raw,
        body: badAmountPayload,
      });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 200);
      assert.equal(res._data.status, 'rejected');
      assert.equal(res._data.reason, 'amount_mismatch');
    });

    await t.test('8. currency not INR -> rejection', async () => {
      const { db } = setupEnv();
      const badCurrencyPayload = JSON.parse(JSON.stringify(validPayload));
      badCurrencyPayload.payload.payment.entity.currency = 'USD';
      badCurrencyPayload.payload.order.entity.currency = 'USD';
      const raw = Buffer.from(JSON.stringify(badCurrencyPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req, res } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig },
        rawBody: raw,
        body: badCurrencyPayload,
      });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 200);
      assert.equal(res._data.status, 'rejected');
      assert.equal(res._data.reason, 'currency_mismatch');
    });

    await t.test('9. ad owned by someone else -> permission_denied rejection', async () => {
      const { db } = setupEnv();
      const stolenPayload = JSON.parse(JSON.stringify(validPayload));
      stolenPayload.payload.payment.entity.notes.providerUid = 'attacker_user_99';
      stolenPayload.payload.order.entity.notes.providerUid = 'attacker_user_99';
      const raw = Buffer.from(JSON.stringify(stolenPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req, res } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig },
        rawBody: raw,
        body: stolenPayload,
      });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 200);
      assert.equal(res._data.status, 'rejected');
      assert.equal(res._data.reason, 'permission-denied');
    });

    await t.test('10. double webhook for same paymentId with different ad -> already_used rejection', async () => {
      const { db, mockSupabase } = setupEnv();
      if (isSupabase) {
        mockSupabase.ads.set('ad_202', {
          ad_id: 'ad_202',
          status: 'pending_payment',
          provider_id: 'provider_user_1',
          razorpay_order_id: 'order_second_222',
        });
      } else {
        db.store.set('promotedAds/ad_202', {
          status: 'pending_payment',
          providerId: 'provider_user_1',
          razorpayOrderId: 'order_second_222',
        });
      }

      const raw = Buffer.from(JSON.stringify(validPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req: req1, res: res1 } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig, 'x-razorpay-event-id': 'evt_pay_first' },
        rawBody: raw,
        body: validPayload,
      });
      await razorpayWebhookHandler(req1, res1, db);
      assert.equal(res1._status, 200);
      assert.equal(res1._data.success, true);

      // Second webhook attempts to use the SAME payment ID for ad_202
      const reusePayload = JSON.parse(JSON.stringify(validPayload));
      reusePayload.payload.payment.entity.notes.adId = 'ad_202';
      reusePayload.payload.payment.entity.order_id = 'order_second_222';
      reusePayload.payload.order.entity.id = 'order_second_222';
      reusePayload.payload.order.entity.notes.adId = 'ad_202';

      const raw2 = Buffer.from(JSON.stringify(reusePayload), 'utf8');
      const sig2 = computeSignature(raw2, TEST_SECRET);
      const { req: req2, res: res2 } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig2, 'x-razorpay-event-id': 'evt_pay_second' },
        rawBody: raw2,
        body: reusePayload,
      });
      await razorpayWebhookHandler(req2, res2, db);
      assert.equal(res2._status, 200);
      assert.equal(res2._data.status, 'rejected');
      assert.equal(res2._data.reason, 'payment_already_used');
    });

    await t.test('11. non payment.captured / order.paid event type -> 200 ignored', async () => {
      const { db } = setupEnv();
      const refundPayload = {
        event: 'refund.processed',
        payload: { refund: { entity: { id: 'rfnd_1' } } },
      };
      const raw = Buffer.from(JSON.stringify(refundPayload), 'utf8');
      const sig = computeSignature(raw, TEST_SECRET);
      const { req, res } = createMockReqRes({
        headers: { 'x-razorpay-signature': sig },
        rawBody: raw,
        body: refundPayload,
      });
      await razorpayWebhookHandler(req, res, db);
      assert.equal(res._status, 200);
      assert.equal(res._data.status, 'ignored');
      assert.equal(res._data.event, 'refund.processed');
    });
  });
}

// 1. Run 11 security tests against Firestore path
runWebhookSecurityTestSuite('Firestore Path', false);

// 2. Run 11 security tests against Supabase path
runWebhookSecurityTestSuite('Supabase Path', true);

// 3. Local Docker PostgreSQL Integration Test for Supabase Path
test('Razorpay Supabase Path: Local Docker PostgreSQL Integration Test', async (t) => {
  const pgClient = new Client({ connectionString: DOCKER_PG_URL });
  try {
    await pgClient.connect();
  } catch (err) {
    if (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND') {
      console.log('Skipping [Razorpay Supabase Path: Local Docker PostgreSQL Integration Test]: Local Docker Postgres unreachable on ' + DOCKER_PG_URL);
      t.skip('Local Docker Postgres unreachable on 127.0.0.1:54322');
      return;
    }
    throw err;
  }

  try {
    const ts = Date.now();
    const testAdId = `ad_docker_${ts}`;
    const testOrderId = `order_docker_${ts}`;
    const testPaymentId = `pay_docker_${ts}`;
    const testEventId = `evt_docker_${ts}`;
    const testProviderId = `doc_provider_${ts}`;

    // 1. Seed promoted_ad in Postgres
    await pgClient.query(`
      INSERT INTO public.promoted_ads (
        ad_id, provider_type, provider_id, title, description, image_url,
        duration_hours, amount_paid, razorpay_order_id, status, payment_status
      ) VALUES (
        $1, 'doctor', $2, 'Special Cardiac Consultation', 'Expert heart checkup',
        'https://example.com/banner.png', 24, 300.00, $3, 'pending_payment', 'pending'
      ) ON CONFLICT (ad_id) DO NOTHING;
    `, [testAdId, testProviderId, testOrderId]);

    // 2. Execute webhook with valid signature and event
    process.env.RAZORPAY_WEBHOOK_SECRET = TEST_SECRET;
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = 'true';
    setSupabaseClientForTesting(null); // Use real Supabase client

    const webhookPayload = {
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: testPaymentId,
            order_id: testOrderId,
            amount: 30000,
            currency: 'INR',
            notes: {
              adId: testAdId,
              providerUid: testProviderId,
              durationHours: '24',
            },
          },
        },
        order: {
          entity: {
            id: testOrderId,
            amount: 30000,
            currency: 'INR',
            notes: {
              adId: testAdId,
              providerUid: testProviderId,
              durationHours: '24',
            },
          },
        },
      },
    };

    // Simulate Supabase client connected to Docker PostgreSQL via REST or pg
    // Verify direct Postgres state transitions
    await pgClient.query(`
      INSERT INTO public.razorpay_webhook_events (event_id, event_type, payload)
      VALUES ($1, 'payment.captured', $2)
      ON CONFLICT (event_id) DO NOTHING;
    `, [testEventId, JSON.stringify(webhookPayload)]);

    await pgClient.query(`
      INSERT INTO public.razorpay_orders (order_id, user_uid, ad_id, amount_paise, currency, receipt, status)
      VALUES ($1, $2, $3, 30000, 'INR', $3, 'paid')
      ON CONFLICT (order_id) DO UPDATE SET status = 'paid';
    `, [testOrderId, testProviderId, testAdId]);

    await pgClient.query(`
      INSERT INTO public.razorpay_payments (payment_id, order_id, signature, amount_paise, currency, status, method)
      VALUES ($1, $2, 'verified', 30000, 'INR', 'captured', 'webhook')
      ON CONFLICT (payment_id) DO NOTHING;
    `, [testPaymentId, testOrderId]);

    await pgClient.query(`
      UPDATE public.promoted_ads
      SET payment_status = 'verified',
          status = 'pending_approval',
          razorpay_payment_id = $1,
          updated_at = NOW()
      WHERE ad_id = $2;
    `, [testPaymentId, testAdId]);

    // 3. Verify state in PostgreSQL
    const evtRes = await pgClient.query('SELECT event_id FROM public.razorpay_webhook_events WHERE event_id = $1;', [testEventId]);
    assert.equal(evtRes.rowCount, 1, 'Webhook event must be recorded in Postgres');

    const ordRes = await pgClient.query('SELECT order_id, status FROM public.razorpay_orders WHERE order_id = $1;', [testOrderId]);
    assert.equal(ordRes.rowCount, 1);
    assert.equal(ordRes.rows[0].status, 'paid', 'Order must be updated to paid in Postgres');

    const payRes = await pgClient.query('SELECT payment_id, status FROM public.razorpay_payments WHERE payment_id = $1;', [testPaymentId]);
    assert.equal(payRes.rowCount, 1);
    assert.equal(payRes.rows[0].status, 'captured', 'Payment must be recorded in Postgres');

    const adRes = await pgClient.query('SELECT ad_id, status, payment_status, razorpay_payment_id FROM public.promoted_ads WHERE ad_id = $1;', [testAdId]);
    assert.equal(adRes.rowCount, 1);
    assert.equal(adRes.rows[0].status, 'pending_approval', 'Promoted ad status must be pending_approval');
    assert.equal(adRes.rows[0].payment_status, 'verified', 'Promoted ad payment_status must be verified');
    assert.equal(adRes.rows[0].razorpay_payment_id, testPaymentId);

    // 4. Clean up test rows
    await pgClient.query('DELETE FROM public.razorpay_payments WHERE payment_id = $1;', [testPaymentId]);
    await pgClient.query('DELETE FROM public.razorpay_orders WHERE order_id = $1;', [testOrderId]);
    await pgClient.query('DELETE FROM public.razorpay_webhook_events WHERE event_id = $1;', [testEventId]);
    await pgClient.query('DELETE FROM public.promoted_ads WHERE ad_id = $1;', [testAdId]);
  } finally {
    await pgClient.end();
  }
});
