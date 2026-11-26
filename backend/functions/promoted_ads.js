const { safeErrorForLog } = require('./log_safe');
const { resolveCallerIdentity } = require('./caller_identity');
// onCall runs handlers inside the verified-auth context (data-plane routing, demo ambulance).
const { onCall, onRequest, HttpsError } = require('./callable_with_auth_context');
const { withDataPlaneSecrets } = require('./demo_plane_secrets');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const crypto = require('crypto');

let _testingSupabaseClient = null;
function setSupabaseClientForTesting(client) {
  _testingSupabaseClient = client;
}

/**
 * Server-side DB client. Pass the ad owner's Firebase UID so production demo accounts route to the
 * staging plane and real users to RDS (never mix planes for one payment).
 */
function getSupabaseAdmin(firebaseUid = null) {
  if (_testingSupabaseClient) return _testingSupabaseClient;
  try {
    const { getDatabaseClient } = require('./src/db/client');
    return getDatabaseClient(firebaseUid ? { firebaseUid } : {});
  } catch (_) {
    return null;
  }
}

const SAFE_UID_RE = /^[A-Za-z0-9_\-:.]{1,128}$/;

/**
 * Postgres path: loads promoted_ads row and enforces caller ownership + non-patient role.
 * Fails closed when the caller profile cannot be resolved.
 */
async function loadOwnedPromotedAdRow(supabase, adId, uid) {
  if (!SAFE_UID_RE.test(String(uid || ''))) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  const { data: adRows, error: adErr } = await supabase
    .from('promoted_ads')
    .select('*')
    .eq('ad_id', adId);
  if (adErr) {
    throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
  }
  const ad = Array.isArray(adRows) ? adRows[0] : null;
  if (!ad) {
    throw new HttpsError('not-found', 'Promoted ad document not found.');
  }
  let caller = null;
  try {
    caller = await resolveCallerIdentity({ uid, supabaseClient: supabase, forceSupabase: true });
  } catch (_) {
    caller = null;
  }
  if (!caller) {
    throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
  }
  if (String(caller.role || '').toLowerCase() === 'patient') {
    throw new HttpsError('permission-denied', 'Patients are not permitted to create promotions.');
  }
  const profileId = caller.profileId || caller.profile_id || null;
  if (ad.provider_id !== uid && !(profileId && ad.provider_id === profileId)) {
    throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
  }
  return ad;
}
const https = require('https');
const { enforceAbuseLimit, assertAppCheck } = require('./abuse_rate_limit');
const { readSecret } = require('./secure_config');

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

// Super admin = verified email in SUPER_ADMIN_EMAILS + admin custom claim (lib/super_admin.js).
const { isSuperAdmin } = require('./lib/super_admin');
const { isDemoUid } = require('./lib/demo_accounts');

const razorpayWebhookSecret = defineSecret('RAZORPAY_WEBHOOK_SECRET');
const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');
const {
  requireDocId,
  requireIntInSet,
  requireRazorpayId,
  requireString,
} = require('./input_sanitize');

/** Pricing Table (Amount in INR) */
const AD_PRICING_TABLE = {
  6: 100,
  12: 180,
  24: 300,
  72: 750,
  168: 1500,
  // Matches PromotedAdsService.defaultPricingTiers / BannerConfigModel (30 days).
  720: 5000,
};

const DEMO_PAYMENTS_DISABLED_MESSAGE = 'Payments are disabled for demo accounts.';

/**
 * Razorpay credentials for a caller. Demo accounts (lib/demo_accounts.js) may only ever use
 * Razorpay TEST mode: RAZORPAY_TEST_KEY_ID / RAZORPAY_TEST_KEY_SECRET, or the main keys when
 * they are themselves test keys (staging). A live key is never returned for a demo UID, so a
 * demo account cannot create a real charge.
 */
function getRazorpayCredentials(uid = null) {
  if (uid && isDemoUid(uid)) {
    const mainId = (process.env.RAZORPAY_KEY_ID || '').trim();
    const testId = (process.env.RAZORPAY_TEST_KEY_ID || '').trim()
      || (mainId.startsWith('rzp_test_') ? mainId : '');
    const testSecret = (process.env.RAZORPAY_TEST_KEY_SECRET || '').trim()
      || (mainId.startsWith('rzp_test_') ? (process.env.RAZORPAY_KEY_SECRET || '').trim() : '');
    if (!testId.startsWith('rzp_test_') || !testSecret) {
      throw new HttpsError('failed-precondition', DEMO_PAYMENTS_DISABLED_MESSAGE);
    }
    return { keyId: testId, keySecret: testSecret, testMode: true };
  }
  const keyId = (process.env.RAZORPAY_KEY_ID || '').trim();
  const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();
  if (!keyId || !keySecret) {
    throw new HttpsError('failed-precondition', 'Razorpay credentials not configured');
  }
  return { keyId, keySecret, testMode: keyId.startsWith('rzp_test_') };
}

/** Helper: Send HTTPS Request to Razorpay REST API */
function makeRazorpayRequest(path, method = 'GET', payload = null, keyId, keySecret) {
  return new Promise((resolve, reject) => {
    const authHeader = 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64');
    const postData = payload ? JSON.stringify(payload) : null;

    const headers = {
      Authorization: authHeader,
    };
    if (postData) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(postData);
    }

    const options = {
      hostname: 'api.razorpay.com',
      port: 443,
      path: path,
      method: method,
      headers: headers,
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(parsed);
          } else {
            reject(new Error(parsed.error?.description || `Razorpay error HTTP ${res.statusCode}`));
          }
        } catch (err) {
          // Never echo the gateway body (may contain payment details) into logs/errors.
          reject(new Error(`Failed to parse Razorpay response (HTTP ${res.statusCode})`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (typeof req.setTimeout === 'function') {
      req.setTimeout(10000, () => req.destroy(new Error('Razorpay request timed out')));
    }
    if (postData) {
      req.write(postData);
    }
    req.end();
  });
}

/**
 * Postgres (Supabase staging / RDS production) order creation. Amount always comes from
 * AD_PRICING_TABLE on the server; client-sent amounts are never read.
 */
async function createRazorpayOrderPostgres(uid, safeAdId, hours, amountINR) {
  const supabase = getSupabaseAdmin(uid);
  if (!supabase) {
    throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
  }
  const ad = await loadOwnedPromotedAdRow(supabase, safeAdId, uid);
  if (ad.status !== 'draft' && ad.status !== 'pending_payment') {
    throw new HttpsError(
      'failed-precondition',
      `Cannot create payment order for ad with status '${ad.status}'.`,
    );
  }

  const { keyId, keySecret } = getRazorpayCredentials(uid);
  const amountPaise = amountINR * 100;

  if (ad.status === 'pending_payment' && ad.razorpay_order_id && Number(ad.duration_hours) === hours) {
    const existingOrderId = String(ad.razorpay_order_id).trim();
    try {
      const existingOrder = await makeRazorpayRequest(`/v1/orders/${encodeURIComponent(existingOrderId)}`, 'GET', null, keyId, keySecret);
      const notes = existingOrder.notes || {};
      if (
        existingOrder.id === existingOrderId &&
        existingOrder.amount === amountPaise &&
        existingOrder.currency === 'INR' &&
        existingOrder.status !== 'paid' &&
        notes.adId === safeAdId &&
        notes.providerUid === uid &&
        parseInt(notes.durationHours, 10) === hours
      ) {
        return { orderId: existingOrder.id, keyId, amount: amountINR, currency: 'INR' };
      }
    } catch (err) {
      console.warn('[createRazorpayOrder] Could not reuse existing order; creating new one.');
    }
  }

  let razorpayOrder;
  try {
    razorpayOrder = await makeRazorpayRequest(
      '/v1/orders',
      'POST',
      {
        amount: amountPaise,
        currency: 'INR',
        receipt: safeAdId.slice(0, 40),
        notes: { adId: safeAdId, providerUid: uid, durationHours: String(hours) },
      },
      keyId,
      keySecret,
    );
  } catch (err) {
    console.error('[createRazorpayOrder] Razorpay order creation failed:', err?.message || 'unknown');
    throw new HttpsError('internal', 'Failed to create Razorpay order.');
  }

  const nowIso = new Date().toISOString();
  const { error: updErr } = await supabase
    .from('promoted_ads')
    .update({
      razorpay_order_id: razorpayOrder.id,
      duration_hours: hours,
      status: 'pending_payment',
      payment_status: 'pending',
      updated_at: nowIso,
    })
    .eq('ad_id', safeAdId);
  if (updErr) {
    throw new HttpsError('internal', 'Failed to create Razorpay order.');
  }
  const { error: orderErr } = await supabase.from('razorpay_orders').upsert({
    order_id: razorpayOrder.id,
    user_uid: uid,
    ad_id: safeAdId,
    amount_paise: amountPaise,
    currency: 'INR',
    receipt: safeAdId.slice(0, 40),
    status: 'created',
    updated_at: nowIso,
  }, { onConflict: 'order_id' });
  if (orderErr) {
    console.warn('[createRazorpayOrder] razorpay_orders ledger write failed');
  }

  return { orderId: razorpayOrder.id, keyId, amount: amountINR, currency: 'INR' };
}

/**
 * 1. Callable Cloud Function: createRazorpayOrder
 * Input: { adId: string, durationHours: number }
 */
const createRazorpayOrder = onCall(
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: withDataPlaneSecrets([supabaseServiceRoleKey]) },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to create payment order.');
  }
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(null, request, 'payment', {
    message: 'Too many payment attempts. Please try again later.',
  });

  const { adId, durationHours } = request.data || {};
  const safeAdId = requireDocId(adId, 'adId');
  const hours = requireIntInSet(
    durationHours,
    'durationHours',
    Object.keys(AD_PRICING_TABLE).map(Number),
  );
  const amountINR = AD_PRICING_TABLE[hours];

  return createRazorpayOrderPostgres(request.auth.uid, safeAdId, hours, amountINR);
  },
);

/**
 * Shared Activation Helper for Promoted Ad Payments (verifyRazorpayPayment & razorpayWebhook).
 * Verifies ad status and ledger idempotency in Postgres (compare-and-set transition),
 * create the ledger document, and transition ad from pending_payment to pending_approval.
 */
async function activatePromotedAdPayment(db, {
  adId,
  orderId,
  paymentId,
  providerUid,
  durationHours,
  amountPaise,
  currency,
  callerUid = null,
  customNow = null,
  eventId = null,
}) {
  const safeAdId = requireDocId(adId, 'adId');
  const safeOrderId = requireRazorpayId(orderId, 'orderId');
  const safePaymentId = requireRazorpayId(paymentId, 'paymentId');

  if (currency !== 'INR') {
    throw new HttpsError('failed-precondition', 'Payment currency must be INR.');
  }

  const noteDurationHours = parseInt(durationHours, 10);
  const expectedPriceINR = AD_PRICING_TABLE[noteDurationHours];
  if (!expectedPriceINR || amountPaise !== expectedPriceINR * 100) {
    throw new HttpsError('failed-precondition', 'Payment amount or duration mismatch.');
  }

  {
    const supabase = getSupabaseAdmin(callerUid || providerUid);
    if (!supabase) {
      throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
    }

    const safeEventId = eventId ? requireDocId(eventId, 'eventId') : null;
    // Fail closed: a DB read error must never be treated as "not processed yet".
    const dbUnavailable = () => new HttpsError('unavailable', 'Database service temporarily unavailable.');

    // 1. Check event idempotency
    if (safeEventId) {
      const { data: eventRows, error: eventErr } = await supabase
        .from('razorpay_webhook_events')
        .select('*')
        .eq('event_id', safeEventId);
      if (eventErr) throw dbUnavailable();
      if (eventRows && eventRows.length > 0) {
        return {
          success: true,
          idempotent: true,
          message: 'Webhook event already processed (idempotent)',
          adId: safeAdId,
        };
      }
    }

    // 2. Check existing payment in razorpay_payments
    const { data: existingPayments, error: payErr } = await supabase
      .from('razorpay_payments')
      .select('*')
      .eq('payment_id', safePaymentId);
    if (payErr) throw dbUnavailable();

    if (existingPayments && existingPayments.length > 0) {
      const prevPay = existingPayments[0];
      if (prevPay.order_id === safeOrderId) {
        return {
          success: true,
          idempotent: true,
          message: 'Payment already processed (idempotent)',
          adId: safeAdId,
        };
      }
      throw new HttpsError('already-exists', 'This payment has already been used.');
    }

    // 3. Query promoted_ads row
    const { data: adRows, error: adErr } = await supabase
      .from('promoted_ads')
      .select('*')
      .eq('ad_id', safeAdId);
    if (adErr) throw dbUnavailable();

    if (!adRows || adRows.length === 0) {
      throw new HttpsError('not-found', 'Promoted ad document not found.');
    }

    const currentAd = adRows[0];

    // Verify ownership (order notes / caller must identify the ad owner; never skip).
    const ownerUid = callerUid || providerUid;
    if (!ownerUid) {
      throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
    }
    {
      if (currentAd.provider_id !== ownerUid) {
        const { data: userRows } = await supabase
          .from('users')
          .select('profile_id')
          .eq('firebase_uid', ownerUid);
        const profileId = userRows && userRows[0] ? userRows[0].profile_id : null;
        if (!profileId || currentAd.provider_id !== profileId) {
          throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
        }
      }
    }

    const paidStatuses = new Set(['pending_approval', 'active', 'rejected']);
    if (paidStatuses.has(currentAd.status) && currentAd.razorpay_payment_id === safePaymentId) {
      return {
        success: true,
        idempotent: true,
        message: 'Payment already verified and banner ad is under review (idempotent)',
        adId: safeAdId,
      };
    }

    if (currentAd.status !== 'pending_payment' || currentAd.razorpay_order_id !== safeOrderId) {
      throw new HttpsError(
        'failed-precondition',
        `Ad is not in pending_payment state or order ID mismatch (status: ${currentAd.status}).`
      );
    }

    // 4. Transition the ad first with a compare-and-set (status + order id) so concurrent
    //    verify/webhook deliveries cannot double-activate; then write ledgers; record the
    //    webhook event last so a failed run is retried by Razorpay instead of being skipped.
    const nowIso = new Date().toISOString();
    const { data: transitioned, error: adUpdErr } = await supabase.from('promoted_ads').update({
      payment_status: 'verified',
      status: 'pending_approval',
      razorpay_order_id: safeOrderId,
      razorpay_payment_id: safePaymentId,
      duration_hours: noteDurationHours,
      amount_paid: expectedPriceINR,
      updated_at: nowIso,
    })
      .eq('ad_id', safeAdId)
      .eq('status', 'pending_payment')
      .eq('razorpay_order_id', safeOrderId)
      .select('ad_id');
    if (adUpdErr) throw dbUnavailable();
    if (!Array.isArray(transitioned) || transitioned.length === 0) {
      // Lost the race to a concurrent activation of the same order.
      return {
        success: true,
        idempotent: true,
        message: 'Payment already processed (idempotent)',
        adId: safeAdId,
      };
    }

    await supabase.from('razorpay_orders').upsert({
      order_id: safeOrderId,
      user_uid: ownerUid || currentAd.provider_id,
      ad_id: safeAdId,
      amount_paise: expectedPriceINR * 100,
      currency: currency || 'INR',
      receipt: safeAdId.slice(0, 40),
      status: 'paid',
      updated_at: nowIso,
    }, { onConflict: 'order_id' });

    await supabase.from('razorpay_payments').upsert({
      payment_id: safePaymentId,
      order_id: safeOrderId,
      signature: 'verified',
      amount_paise: expectedPriceINR * 100,
      currency: currency || 'INR',
      status: 'captured',
      method: safeEventId ? 'webhook' : 'client_verify',
    }, { onConflict: 'payment_id' });

    if (safeEventId) {
      await supabase.from('razorpay_webhook_events').upsert({
        event_id: safeEventId,
        event_type: 'payment.captured',
        payload: { adId: safeAdId, orderId: safeOrderId, paymentId: safePaymentId },
        processed_at: nowIso,
      }, { onConflict: 'event_id' });
    }

    return {
      success: true,
      idempotent: false,
      message: 'Payment verified. Banner ad submitted for review.',
      adId: safeAdId,
      startTime: currentAd.start_time || null,
      endTime: currentAd.end_time || null,
    };
  }
}

function toIsoDateString(val) {
  if (!val) return new Date().toISOString();
  if (typeof val.toDate === 'function') return val.toDate().toISOString();
  if (typeof val._seconds === 'number') return new Date(val._seconds * 1000).toISOString();
  if (val instanceof Date) return val.toISOString();
  const d = new Date(val);
  return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

/**
 * 2. Callable Cloud Function: verifyRazorpayPayment
 * Input: { adId: string, orderId: string, paymentId: string, signature: string }
 */
const verifyRazorpayPayment = onCall(
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: withDataPlaneSecrets([supabaseServiceRoleKey]) },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to verify payment.');
  }
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(null, request, 'payment');

  const { adId, orderId, paymentId, signature } = request.data || {};
  const safeAdId = requireDocId(adId, 'adId');
  const safeOrderId = requireRazorpayId(orderId, 'orderId');
  const safePaymentId = requireRazorpayId(paymentId, 'paymentId');
  const safeSignature = requireString(signature, 'signature', {
    min: 32,
    max: 128,
    pattern: /^[a-fA-F0-9]+$/,
  });

  const supabase = getSupabaseAdmin(request.auth.uid);
  if (!supabase) {
    throw new HttpsError('unavailable', 'Database service temporarily unavailable.');
  }
  const row = await loadOwnedPromotedAdRow(supabase, safeAdId, request.auth.uid);
  const adData = { razorpayOrderId: row.razorpay_order_id };
  const db = null;

  const expectedOrderId = String(adData.razorpayOrderId || '').trim();
  if (!expectedOrderId || expectedOrderId !== safeOrderId) {
    throw new HttpsError('invalid-argument', 'Order does not match this advertisement.');
  }

  const { keyId, keySecret } = getRazorpayCredentials(request.auth.uid);

  // Server-side HMAC SHA256 signature verification per Razorpay spec
  const payload = `${safeOrderId}|${safePaymentId}`;
  const generatedSignature = crypto
    .createHmac('sha256', keySecret)
    .update(payload)
    .digest('hex');

  const bufExpected = Buffer.from(generatedSignature.toLowerCase(), 'utf8');
  const bufReceived = Buffer.from(safeSignature.toLowerCase(), 'utf8');

  // Constant-time compare with length check; on mismatch write NOTHING
  if (bufExpected.length !== bufReceived.length || !crypto.timingSafeEqual(bufExpected, bufReceived)) {
    console.warn(`[verifyRazorpayPayment] Signature mismatch for ad ${safeAdId}`);
    throw new HttpsError('invalid-argument', 'Razorpay payment signature verification failed.');
  }

  // GET the Razorpay payment and order (reuse makeRazorpayRequest)
  let payment, order;
  try {
    [payment, order] = await Promise.all([
      makeRazorpayRequest(`/v1/payments/${safePaymentId}`, 'GET', null, keyId, keySecret),
      makeRazorpayRequest(`/v1/orders/${safeOrderId}`, 'GET', null, keyId, keySecret),
    ]);
  } catch (err) {
    console.error('[verifyRazorpayPayment] Error fetching payment/order from Razorpay:', safeErrorForLog(err));
    throw new HttpsError('internal', 'Failed to verify payment with payment gateway.');
  }

  if (payment.status !== 'captured' || payment.order_id !== safeOrderId) {
    throw new HttpsError('failed-precondition', 'Payment not captured or order mismatch.');
  }

  if (payment.currency !== 'INR') {
    throw new HttpsError('failed-precondition', 'Payment currency must be INR.');
  }

  if (order.notes?.adId !== safeAdId || order.notes?.providerUid !== request.auth.uid) {
    throw new HttpsError('failed-precondition', 'Order notes mismatch.');
  }

  const noteDurationHours = parseInt(order.notes?.durationHours, 10);

  const activation = await activatePromotedAdPayment(db, {
    adId: safeAdId,
    orderId: safeOrderId,
    paymentId: safePaymentId,
    providerUid: request.auth.uid,
    callerUid: request.auth.uid,
    durationHours: noteDurationHours,
    amountPaise: payment.amount,
    currency: payment.currency,
  });

  return {
    success: activation.success,
    idempotent: activation.idempotent,
    message: activation.message,
    adId: activation.adId,
    startTime: activation.startTime ? toIsoDateString(activation.startTime) : null,
    endTime: activation.endTime ? toIsoDateString(activation.endTime) : null,
  };
  },
);

/**
 * Core HTTP handler for Razorpay webhook events.
 * Accepts POST only; verifies x-razorpay-signature before parsing; processes payment.captured and order.paid;
 * extracts parameters strictly from order notes; activates promoted ads idempotently.
 */
async function razorpayWebhookHandler(req, res, db) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Method Not Allowed. POST required.' } });
    return;
  }

  const receivedSignature = req.headers['x-razorpay-signature'];
  if (!receivedSignature || typeof receivedSignature !== 'string') {
    res.status(400).send('Missing webhook signature.');
    return;
  }

  let webhookSecret = '';
  try {
    webhookSecret = razorpayWebhookSecret.value();
  } catch (_) {}
  if (!webhookSecret) {
    webhookSecret = (process.env.RAZORPAY_WEBHOOK_SECRET || '').trim();
  }
  if (!webhookSecret) {
    console.error('[razorpayWebhook] RAZORPAY_WEBHOOK_SECRET is not configured.');
    res.status(503).json({ error: { message: 'Webhook secret not configured.' } });
    return;
  }

  let rawBodyBuffer = null;
  if (Buffer.isBuffer(req.rawBody)) {
    rawBodyBuffer = req.rawBody;
  } else if (typeof req.rawBody === 'string') {
    rawBodyBuffer = Buffer.from(req.rawBody, 'utf8');
  }
  if (!rawBodyBuffer || rawBodyBuffer.length === 0) {
    console.warn('[razorpayWebhook] Missing raw request body; refusing to verify a re-serialized body.');
    res.status(400).send('Missing raw request body.');
    return;
  }

  const generatedSignature = crypto
    .createHmac('sha256', webhookSecret)
    .update(rawBodyBuffer)
    .digest('hex');

  const bufExpected = Buffer.from(generatedSignature.toLowerCase(), 'utf8');
  const bufReceived = Buffer.from(receivedSignature.trim().toLowerCase(), 'utf8');

  // Constant-time compare with length check; on bad signature reject immediately with 400
  if (
    bufExpected.length !== bufReceived.length ||
    !crypto.timingSafeEqual(bufExpected, bufReceived)
  ) {
    console.warn('[razorpayWebhook] Invalid signature received on webhook request.');
    res.status(400).send('Invalid webhook signature.');
    return;
  }

  // Signature verified: parse body
  let event;
  try {
    if (typeof req.body === 'object' && req.body !== null && !Buffer.isBuffer(req.body)) {
      event = req.body;
    } else {
      event = JSON.parse(rawBodyBuffer.toString('utf8'));
    }
  } catch (_) {
    console.warn('[razorpayWebhook] Failed to parse verified webhook payload as JSON');
    res.status(400).send('Invalid JSON payload.');
    return;
  }

  const eventType = String(event?.event || '').trim();
  if (eventType !== 'payment.captured' && eventType !== 'order.paid') {
    console.info(`[razorpayWebhook] Ignored non-handled event type: ${eventType || 'unknown'}`);
    res.status(200).json({ status: 'ignored', event: eventType });
    return;
  }

  const eventId = String(req.headers['x-razorpay-event-id'] || '').trim();
  const eventPayload = event?.payload || {};
  const paymentEntity = eventPayload?.payment?.entity;
  const orderEntity = eventPayload?.order?.entity;

  // Extract payment/order metadata early for dead-letter context
  const paymentId = paymentEntity?.id;
  const orderId = orderEntity?.id || paymentEntity?.order_id;
  const amountPaise = paymentEntity?.amount ?? orderEntity?.amount;
  const currency = paymentEntity?.currency || orderEntity?.currency;

  // Extract order notes (strictly from order/payment notes, never from request query)
  const notes = orderEntity?.notes || paymentEntity?.notes || {};
  const adId = typeof notes.adId === 'string' ? notes.adId.trim() : null;
  const providerUid = typeof notes.providerUid === 'string' ? notes.providerUid.trim() : null;
  const durationHours = notes.durationHours ? parseInt(notes.durationHours, 10) : null;

  {
    if (providerUid && !SAFE_UID_RE.test(providerUid)) {
      res.status(200).json({ status: 'rejected', reason: 'order_notes_invalid' });
      return;
    }
    const supabase = getSupabaseAdmin(providerUid);
    if (!supabase) {
      res.status(503).json({ error: { message: 'Database service unavailable' } });
      return;
    }

    if (!adId || !providerUid || !durationHours) {
      console.warn('[razorpayWebhook] order_notes_missing');
      res.status(200).json({ status: 'rejected', reason: 'order_notes_missing' });
      return;
    }

    if (!paymentId || !orderId) {
      console.warn('[razorpayWebhook] missing_identifiers');
      res.status(200).json({ status: 'rejected', reason: 'missing_identifiers' });
      return;
    }

    if (currency !== 'INR') {
      console.warn('[razorpayWebhook] currency_mismatch');
      res.status(200).json({ status: 'rejected', reason: 'currency_mismatch' });
      return;
    }

    const expectedPriceINR = AD_PRICING_TABLE[durationHours];
    if (!expectedPriceINR || amountPaise !== expectedPriceINR * 100) {
      console.warn('[razorpayWebhook] amount_mismatch');
      res.status(200).json({ status: 'rejected', reason: 'amount_mismatch' });
      return;
    }

    const { data: adRows, error: adReadErr } = await supabase.from('promoted_ads').select('*').eq('ad_id', adId);
    if (adReadErr) {
      // 5xx so Razorpay retries delivery instead of dropping a real payment.
      res.status(503).json({ error: { message: 'Database service unavailable' } });
      return;
    }
    if (!adRows || adRows.length === 0) {
      console.warn('[razorpayWebhook] ad_not_found');
      res.status(200).json({ status: 'rejected', reason: 'ad_not_found' });
      return;
    }

    const adData = adRows[0];
    const expectedOrderId = String(adData.razorpay_order_id || '').trim();
    if (!expectedOrderId || expectedOrderId !== orderId) {
      console.warn('[razorpayWebhook] order_id_mismatch');
      res.status(200).json({ status: 'rejected', reason: 'order_id_mismatch' });
      return;
    }

    try {
      const activation = await activatePromotedAdPayment(null, {
        adId,
        orderId,
        paymentId,
        providerUid,
        durationHours,
        amountPaise,
        currency,
        eventId,
      });

      console.info(`[razorpayWebhook] Successfully processed ${eventType} for ad ${adId} (idempotent: ${activation.idempotent})`);
      res.status(200).json({
        success: true,
        idempotent: activation.idempotent,
        adId: activation.adId,
      });
      return;
    } catch (err) {
      if (err instanceof HttpsError) {
        if (err.code === 'unavailable') {
          res.status(503).json({ error: { message: 'Database service unavailable' } });
          return;
        }
        if (err.code === 'already-exists') {
          res.status(200).json({ status: 'rejected', reason: 'payment_already_used' });
          return;
        }
        if (err.code === 'permission-denied') {
          res.status(200).json({ status: 'rejected', reason: 'permission-denied' });
          return;
        }
        res.status(200).json({ status: 'rejected', reason: err.code });
        return;
      }
      res.status(500).json({ error: { message: 'Failed to process webhook' } });
      return;
    }
  }

}

/**
 * 3. onRequest Cloud Function: razorpayWebhook
 * Webhook endpoint for Razorpay payment and order completion events.
 */
const razorpayWebhook = onRequest(
  {
    region: 'asia-south1',
    secrets: withDataPlaneSecrets([razorpayWebhookSecret, supabaseServiceRoleKey]),
    invoker: 'public',
  },
  require('./http_endpoint_security').withApiSecurityHeaders(async (req, res) => razorpayWebhookHandler(req, res, null)),
);

/**
 * Super-admin review of a paid promoted ad.
 * Input: { adId: string, decision: 'approve'|'reject', reason?: string }
 */
async function reviewPromotedAdHandler(db, data, auth) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  const safeAdId = requireDocId(data?.adId, 'adId');
  const safeDecision = requireString(data?.decision, 'decision', {
    min: 6,
    max: 7,
    pattern: /^(approve|reject)$/,
  });
  const rawReason = data?.reason == null ? '' : data.reason;
  const safeReason = String(rawReason || '').trim()
    ? requireString(String(rawReason), 'reason', { min: 1, max: 500 })
    : '';

  const userDoc = await resolveCallerIdentity({ db, uid: auth.uid });
  if (!isSuperAdmin(auth, userDoc)) {
    throw new HttpsError('permission-denied', 'Super admin access required.');
  }

  {
    const { getSupabaseAdminClient } = require('./caller_identity');
    const sb = getSupabaseAdminClient();
    if (!sb) throw new HttpsError('internal', 'Supabase client not configured.');

    const { data: adData, error } = await sb
      .from('promoted_ads')
      .select('*')
      .eq('ad_id', safeAdId)
      .maybeSingle();

    if (error || !adData) {
      throw new HttpsError('not-found', 'Promoted ad document not found.');
    }
    if (adData.status !== 'pending_approval' && adData.status !== 'pending_review') {
      throw new HttpsError(
        'failed-precondition',
        `Ad is not pending approval (status: ${adData.status}).`,
      );
    }

    const providerId = String(adData.provider_id || '').trim();
    const callerProfileId = String(userDoc.profileId || userDoc.profile_id || '').trim();
    if (
      providerId
      && (providerId === auth.uid || (callerProfileId && providerId === callerProfileId))
    ) {
      throw new HttpsError('permission-denied', 'You cannot review your own promoted ad.');
    }

    const now = new Date();
    const nowIso = now.toISOString();
    if (safeDecision === 'approve') {
      // Never activate an ad whose payment was not verified server-side.
      if (adData.payment_status !== 'verified' || !adData.razorpay_payment_id) {
        throw new HttpsError('failed-precondition', 'Ad payment has not been verified.');
      }
      const hours = parseInt(adData.duration_hours, 10);
      if (!AD_PRICING_TABLE[hours]) {
        throw new HttpsError('failed-precondition', 'Ad duration is invalid.');
      }
      const endTimeIso = new Date(now.getTime() + hours * 3600 * 1000).toISOString();
      await sb.from('promoted_ads').update({
        status: 'active',
        start_time: nowIso,
        end_time: endTimeIso,
        updated_at: nowIso,
      }).eq('ad_id', safeAdId);
      return { ok: true, adId: safeAdId, status: 'active' };
    }

    await sb.from('promoted_ads').update({
      status: 'rejected',
      rejection_reason: safeReason || 'Rejected by admin',
      updated_at: nowIso,
    }).eq('ad_id', safeAdId);
    return { ok: true, adId: safeAdId, status: 'rejected' };
  }
}

const reviewPromotedAd = onCall(
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK, secrets: withDataPlaneSecrets([supabaseServiceRoleKey]) },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }
    assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
    await enforceAbuseLimit(null, request, 'api', {
      message: 'Too many requests. Please try again later.',
    });
    return reviewPromotedAdHandler(null, request.data || {}, request.auth);
  },
);

const EXPIRE_BATCH_LIMIT = 400;

/**
 * Postgres expiry sweep: active ads whose end_time has passed become 'expired'.
 * (pg_cron does the same on Supabase; this keeps RDS correct until its pg_cron is attached.)
 */
async function expirePromotedAdsHandler(_db, customNow = null, supabaseClient = null) {
  const sb = supabaseClient || getSupabaseAdmin();
  if (!sb) {
    throw new Error('Database client unavailable for promoted ad expiry.');
  }
  const nowIso = (customNow instanceof Date ? customNow : new Date()).toISOString();
  const { data, error } = await sb
    .from('promoted_ads')
    .update({ status: 'expired', updated_at: nowIso })
    .eq('status', 'active')
    .lte('end_time', nowIso)
    .select('ad_id');
  if (error) {
    throw new Error(`promoted ad expiry failed: ${error.message || 'unknown'}`);
  }
  const totalExpired = Array.isArray(data) ? data.length : 0;
  return { totalExpired, batchCount: totalExpired > 0 ? 1 : 0 };
}

/**
 * Scheduled Cloud Function: expirePromotedAds (hourly).
 */
const expirePromotedAds = onSchedule({ schedule: '0 * * * *', region: 'asia-south1', secrets: withDataPlaneSecrets([supabaseServiceRoleKey]) }, async () => {
  try {
    const { totalExpired } = await expirePromotedAdsHandler(null);
    console.log(`[expirePromotedAds] expired ${totalExpired} ad(s).`);
  } catch (err) {
    console.error('[expirePromotedAds] Error expiring ads:', err?.message || err);
  }
});

module.exports = {
  AD_PRICING_TABLE,
  getRazorpayCredentials,
  makeRazorpayRequest,
  createRazorpayOrder,
  verifyRazorpayPayment,
  reviewPromotedAd,
  reviewPromotedAdHandler,
  isSuperAdmin,
  expirePromotedAds,
  expirePromotedAdsHandler,
  EXPIRE_BATCH_LIMIT,
  activatePromotedAdPayment,
  razorpayWebhook,
  razorpayWebhookHandler,
  setSupabaseClientForTesting,
  getSupabaseAdmin,
  razorpayWebhookSecret,
};
