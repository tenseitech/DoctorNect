'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

// Helpers for Razorpay Phase E.3
async function recordOrderInSupabase({
  supabase,
  orderId,
  userUid,
  adId,
  amountPaise,
  currency = 'INR',
  receipt,
}) {
  if (!supabase) return { recorded: false };
  const orderRes = await supabase.from('razorpay_orders').upsert({
    order_id: orderId,
    user_uid: userUid,
    ad_id: adId,
    amount_paise: amountPaise,
    currency: currency,
    receipt: receipt || (adId || 'receipt').slice(0, 40),
    status: 'created',
    updated_at: new Date().toISOString(),
  }, { onConflict: 'order_id' });

  if (adId) {
    await supabase.from('promoted_ads').update({
      razorpay_order_id: orderId,
      amount_paid: amountPaise / 100,
      status: 'pending_payment',
      payment_status: 'pending',
      updated_at: new Date().toISOString(),
    }).eq('ad_id', adId);
  }

  return { recorded: true, error: orderRes?.error || null };
}

async function recordPaymentInSupabase({
  supabase,
  adId,
  orderId,
  paymentId,
  userUid,
  amountPaise,
  currency = 'INR',
  eventId = null,
  signature = null,
  method = 'upi',
}) {
  if (!supabase) return { recorded: false };

  // 1. Record webhook event if eventId provided
  if (eventId) {
    await supabase.from('razorpay_webhook_events').upsert({
      event_id: eventId,
      event_type: 'payment.captured',
      payload: { adId, orderId, paymentId },
      processed_at: new Date().toISOString(),
    }, { onConflict: 'event_id' });
  }

  // 2. Upsert order to 'paid'
  await supabase.from('razorpay_orders').upsert({
    order_id: orderId,
    user_uid: userUid,
    ad_id: adId,
    amount_paise: amountPaise,
    currency: currency,
    receipt: (adId || 'receipt').slice(0, 40),
    status: 'paid',
    updated_at: new Date().toISOString(),
  }, { onConflict: 'order_id' });

  // 3. Upsert payment
  const paymentRes = await supabase.from('razorpay_payments').upsert({
    payment_id: paymentId,
    order_id: orderId,
    signature: signature || 'verified',
    amount_paise: amountPaise,
    currency: currency,
    status: 'captured',
    method: method,
  }, { onConflict: 'payment_id' });

  // 4. Update promoted_ads to pending_approval
  if (adId) {
    await supabase.from('promoted_ads').update({
      payment_status: 'verified',
      status: 'pending_approval',
      razorpay_order_id: orderId,
      razorpay_payment_id: paymentId,
      amount_paid: amountPaise / 100,
      updated_at: new Date().toISOString(),
    }).eq('ad_id', adId);
  }

  return { recorded: true, error: paymentRes?.error || null };
}

function verifyRazorpayWebhookSignature(rawBody, signature, secret) {
  if (!rawBody || !signature || !secret) return false;
  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  const bufExpected = Buffer.from(expected.toLowerCase(), 'utf8');
  const bufReceived = Buffer.from(signature.trim().toLowerCase(), 'utf8');
  if (bufExpected.length !== bufReceived.length) return false;
  return crypto.timingSafeEqual(bufExpected, bufReceived);
}

test.describe('Phase E.3: Razorpay Monetization & Promoted Ads (Supabase)', () => {
  test('recordOrderInSupabase upserts order and updates ad to pending_payment', async () => {
    const ordersUpserted = [];
    const adsUpdated = [];

    const mockSupabase = {
      from: (table) => {
        if (table === 'razorpay_orders') {
          return {
            upsert: async (data) => {
              ordersUpserted.push(data);
              return { error: null };
            },
          };
        }
        if (table === 'promoted_ads') {
          return {
            update: (data) => ({
              eq: async (col, val) => {
                adsUpdated.push({ col, val, data });
                return { error: null };
              },
            }),
          };
        }
        throw new Error(`Unexpected table: ${table}`);
      },
    };

    const res = await recordOrderInSupabase({
      supabase: mockSupabase,
      orderId: 'order_test_999',
      userUid: 'uid_doctor_1',
      adId: 'AD-E3-TEST',
      amountPaise: 30000,
      currency: 'INR',
      receipt: 'rcpt_test_999',
    });

    assert.equal(res.recorded, true);
    assert.equal(ordersUpserted.length, 1);
    assert.equal(ordersUpserted[0].order_id, 'order_test_999');
    assert.equal(ordersUpserted[0].status, 'created');
    assert.equal(ordersUpserted[0].amount_paise, 30000);

    assert.equal(adsUpdated.length, 1);
    assert.equal(adsUpdated[0].val, 'AD-E3-TEST');
    assert.equal(adsUpdated[0].data.status, 'pending_payment');
    assert.equal(adsUpdated[0].data.payment_status, 'pending');
  });

  test('recordPaymentInSupabase records webhook event, payment, order status, and ad approval status', async () => {
    const eventsUpserted = [];
    const ordersUpserted = [];
    const paymentsUpserted = [];
    const adsUpdated = [];

    const mockSupabase = {
      from: (table) => {
        if (table === 'razorpay_webhook_events') {
          return {
            upsert: async (data) => {
              eventsUpserted.push(data);
              return { error: null };
            },
          };
        }
        if (table === 'razorpay_orders') {
          return {
            upsert: async (data) => {
              ordersUpserted.push(data);
              return { error: null };
            },
          };
        }
        if (table === 'razorpay_payments') {
          return {
            upsert: async (data) => {
              paymentsUpserted.push(data);
              return { error: null };
            },
          };
        }
        if (table === 'promoted_ads') {
          return {
            update: (data) => ({
              eq: async (col, val) => {
                adsUpdated.push({ col, val, data });
                return { error: null };
              },
            }),
          };
        }
        throw new Error(`Unexpected table: ${table}`);
      },
    };

    const res = await recordPaymentInSupabase({
      supabase: mockSupabase,
      adId: 'AD-E3-TEST',
      orderId: 'order_test_999',
      paymentId: 'pay_test_999',
      userUid: 'uid_doctor_1',
      amountPaise: 30000,
      currency: 'INR',
      eventId: 'evt_delivery_999',
      signature: 'valid_sig_hash',
      method: 'card',
    });

    assert.equal(res.recorded, true);
    assert.equal(eventsUpserted.length, 1);
    assert.equal(eventsUpserted[0].event_id, 'evt_delivery_999');

    assert.equal(ordersUpserted.length, 1);
    assert.equal(ordersUpserted[0].status, 'paid');

    assert.equal(paymentsUpserted.length, 1);
    assert.equal(paymentsUpserted[0].payment_id, 'pay_test_999');
    assert.equal(paymentsUpserted[0].status, 'captured');
    assert.equal(paymentsUpserted[0].method, 'card');

    assert.equal(adsUpdated.length, 1);
    assert.equal(adsUpdated[0].data.status, 'pending_approval');
    assert.equal(adsUpdated[0].data.payment_status, 'verified');
  });

  test('verifyRazorpayWebhookSignature validates genuine HMAC and blocks invalid signatures', () => {
    const secret = 'webhook_secret_key_12345';
    const body = Buffer.from(JSON.stringify({ event: 'payment.captured', entity: { id: 'pay_123' } }), 'utf8');

    const validSig = crypto.createHmac('sha256', secret).update(body).digest('hex');
    assert.equal(verifyRazorpayWebhookSignature(body, validSig, secret), true);

    const invalidSig = 'deadbeef'.repeat(8);
    assert.equal(verifyRazorpayWebhookSignature(body, invalidSig, secret), false);

    assert.equal(verifyRazorpayWebhookSignature(null, validSig, secret), false);
    assert.equal(verifyRazorpayWebhookSignature(body, null, secret), false);
    assert.equal(verifyRazorpayWebhookSignature(body, validSig, ''), false);
  });
});
