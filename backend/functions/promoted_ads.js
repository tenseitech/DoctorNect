const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const crypto = require('crypto');
const https = require('https');
const { enforceAbuseLimit, assertAppCheck } = require('./abuse_rate_limit');
const { readSecret } = require('./secure_config');

const ENFORCE_ABUSE_APP_CHECK = String(
  process.env.ENFORCE_ABUSE_APP_CHECK || process.env.ENFORCE_OTP_APP_CHECK || 'true',
)
  .trim()
  .toLowerCase() !== 'false';

const SUPER_ADMIN_EMAILS = ['admin@doctornect.com'];

function isSuperAdmin(auth, userDoc) {
  const email = String(auth?.token?.email || '').trim().toLowerCase();
  const emailVerified = auth?.token?.email_verified === true;
  if (email && emailVerified && SUPER_ADMIN_EMAILS.includes(email)) return true;
  const role = userDoc?.role || '';
  return role === 'super_admin' || role === 'superAdmin' || role === 'admin';
}

const razorpayWebhookSecret = defineSecret('RAZORPAY_WEBHOOK_SECRET');
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
};

function getRazorpayCredentials() {
  const keyId = (process.env.RAZORPAY_KEY_ID || '').trim();
  const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();
  if (!keyId || !keySecret) {
    throw new HttpsError('failed-precondition', 'Razorpay credentials not configured');
  }
  return { keyId, keySecret };
}

/** Helper: verify provider ownership by auth.uid or users/{uid}.profileId */
async function isAdOwner(db, adData, uid) {
  if (!adData || !uid) return false;
  if (adData.providerId === uid) return true;
  try {
    const userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      const profileId = userDoc.data()?.profileId;
      if (profileId && adData.providerId === profileId) return true;
    }
  } catch (err) {
    console.warn('[isAdOwner] Failed to check user profileId:', err.message);
  }
  return false;
}

/** Helper: ensure patients cannot create or pay for promotional campaigns */
async function assertCanPromote(db, uid) {
  try {
    const userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      const role = String(userDoc.data()?.role || '').toLowerCase();
      if (role === 'patient') {
        throw new HttpsError('permission-denied', 'Patients are not permitted to create promotions.');
      }
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.warn('[assertCanPromote] Failed to check user role:', err.message);
  }
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
          reject(new Error(`Failed to parse Razorpay response: ${body}`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (postData) {
      req.write(postData);
    }
    req.end();
  });
}

/**
 * 1. Callable Cloud Function: createRazorpayOrder
 * Input: { adId: string, durationHours: number }
 */
const createRazorpayOrder = onCall(
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to create payment order.');
  }
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(getFirestore(), request, 'payment', {
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

  const db = getFirestore();
  const adRef = db.collection('promotedAds').doc(safeAdId);
  const adSnap = await adRef.get();

  if (!adSnap.exists) {
    throw new HttpsError('not-found', 'Promoted ad document not found.');
  }

  const adData = adSnap.data();
  await assertCanPromote(db, request.auth.uid);
  const isOwner = await isAdOwner(db, adData, request.auth.uid);
  if (!isOwner) {
    throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
  }

  if (adData.status !== 'draft' && adData.status !== 'pending_payment') {
    throw new HttpsError(
      'failed-precondition',
      `Cannot create payment order for ad with status '${adData.status}'.`
    );
  }

  const { keyId, keySecret } = getRazorpayCredentials();
  const amountPaise = amountINR * 100;

  // If pending_payment with existing razorpayOrderId for same durationHours, reuse verified existing order
  if (
    adData.status === 'pending_payment' &&
    adData.razorpayOrderId &&
    Number(adData.durationHours) === hours
  ) {
    const existingOrderId = String(adData.razorpayOrderId).trim();
    try {
      const existingOrder = await makeRazorpayRequest(
        `/v1/orders/${existingOrderId}`,
        'GET',
        null,
        keyId,
        keySecret
      );

      const notes = existingOrder.notes || {};
      const orderDuration = parseInt(notes.durationHours, 10);

      if (
        existingOrder.id === existingOrderId &&
        existingOrder.amount === amountPaise &&
        notes.adId === safeAdId &&
        notes.providerUid === request.auth.uid &&
        orderDuration === hours
      ) {
        return {
          orderId: existingOrder.id,
          keyId: keyId,
          amount: amountINR,
          currency: 'INR',
        };
      }
    } catch (err) {
      console.warn(`[createRazorpayOrder] Failed to reuse existing order ${existingOrderId}, creating new:`, err.message);
    }
  }

  try {
    const razorpayOrder = await makeRazorpayRequest(
      '/v1/orders',
      'POST',
      {
        amount: amountPaise,
        currency: 'INR',
        receipt: safeAdId.slice(0, 40),
        notes: {
          adId: safeAdId,
          providerUid: request.auth.uid,
          durationHours: String(hours),
        },
      },
      keyId,
      keySecret,
    );

    // Save order ID and amount server-side
    await adRef.update({
      razorpayOrderId: razorpayOrder.id,
      amountPaid: amountINR,
      durationHours: hours,
      status: 'pending_payment',
      paymentStatus: 'pending',
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      orderId: razorpayOrder.id,
      keyId: keyId,
      amount: amountINR,
      currency: 'INR',
    };
  } catch (err) {
    console.error('[createRazorpayOrder] Error creating order:', err);
    throw new HttpsError('internal', 'Failed to create Razorpay order.');
  }
  },
);

/**
 * Shared Activation Helper for Promoted Ad Payments (verifyRazorpayPayment & razorpayWebhook).
 * Runs a single Firestore transaction to verify ad status, validate ledger idempotency,
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

  const adRef = db.collection('promotedAds').doc(safeAdId);
  const paymentLedgerRef = db.collection('razorpayPayments').doc(safePaymentId);
  const paidStatuses = new Set(['pending_approval', 'active', 'rejected']);

  let isIdempotentSuccess = false;
  let resStartTime = null;
  let resEndTime = null;

  await db.runTransaction(async (tx) => {
    const [currentAdDoc, ledgerDoc] = await Promise.all([
      tx.get(adRef),
      tx.get(paymentLedgerRef),
    ]);

    if (!currentAdDoc.exists) {
      throw new HttpsError('not-found', 'Promoted ad document not found.');
    }

    const currentAd = currentAdDoc.data();

    // Verify ownership
    const ownerUid = callerUid || providerUid;
    if (ownerUid) {
      if (currentAd.providerId !== ownerUid) {
        const callerUserDoc = await tx.get(db.collection('users').doc(ownerUid));
        const callerProfileId = callerUserDoc.exists ? callerUserDoc.data()?.profileId : null;
        if (!callerProfileId || currentAd.providerId !== callerProfileId) {
          throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
        }
      }
    }

    // Ledger check: same ad + already paid (pending_approval/active/rejected) is idempotent; other ads reject.
    if (ledgerDoc.exists) {
      const ledgerData = ledgerDoc.data();
      if (
        ledgerData.adId === safeAdId &&
        paidStatuses.has(currentAd.status) &&
        currentAd.razorpayPaymentId === safePaymentId
      ) {
        isIdempotentSuccess = true;
        resStartTime = currentAd.startTime || null;
        resEndTime = currentAd.endTime || null;
        return;
      }
      throw new HttpsError('already-exists', 'This payment has already been used.');
    }

    // Require ad.status === 'pending_payment' and ad.razorpayOrderId === orderId
    if (currentAd.status !== 'pending_payment' || currentAd.razorpayOrderId !== safeOrderId) {
      throw new HttpsError(
        'failed-precondition',
        `Ad is not in pending_payment state or order ID mismatch (status: ${currentAd.status}).`
      );
    }

    // Create ledger doc in same transaction
    tx.set(paymentLedgerRef, {
      adId: safeAdId,
      orderId: safeOrderId,
      providerUid: ownerUid || currentAd.providerId,
      paymentId: safePaymentId,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(adRef, {
      paymentStatus: 'verified',
      status: 'pending_approval',
      razorpayOrderId: safeOrderId,
      razorpayPaymentId: safePaymentId,
      durationHours: noteDurationHours,
      amountPaid: expectedPriceINR,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return {
    success: true,
    idempotent: isIdempotentSuccess,
    message: isIdempotentSuccess
      ? 'Payment already verified and banner ad is under review (idempotent)'
      : 'Payment verified. Banner ad submitted for review.',
    adId: safeAdId,
    startTime: resStartTime,
    endTime: resEndTime,
  };
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
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to verify payment.');
  }
  assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
  await enforceAbuseLimit(getFirestore(), request, 'payment');

  const { adId, orderId, paymentId, signature } = request.data || {};
  const safeAdId = requireDocId(adId, 'adId');
  const safeOrderId = requireRazorpayId(orderId, 'orderId');
  const safePaymentId = requireRazorpayId(paymentId, 'paymentId');
  const safeSignature = requireString(signature, 'signature', {
    min: 32,
    max: 128,
    pattern: /^[a-fA-F0-9]+$/,
  });

  const db = getFirestore();
  const adRef = db.collection('promotedAds').doc(safeAdId);
  const adSnap = await adRef.get();

  if (!adSnap.exists) {
    throw new HttpsError('not-found', 'Promoted ad document not found.');
  }

  const adData = adSnap.data();
  const isOwner = await isAdOwner(db, adData, request.auth.uid);
  if (!isOwner) {
    throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
  }

  const expectedOrderId = String(adData.razorpayOrderId || '').trim();
  if (!expectedOrderId || expectedOrderId !== safeOrderId) {
    throw new HttpsError('invalid-argument', 'Order does not match this advertisement.');
  }

  const { keyId, keySecret } = getRazorpayCredentials();

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
    console.error('[verifyRazorpayPayment] Error fetching payment/order from Razorpay:', err);
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
    res.status(500).send('Webhook secret not configured.');
    return;
  }

  let rawBodyBuffer;
  if (Buffer.isBuffer(req.rawBody)) {
    rawBodyBuffer = req.rawBody;
  } else if (typeof req.rawBody === 'string') {
    rawBodyBuffer = Buffer.from(req.rawBody, 'utf8');
  } else if (Buffer.isBuffer(req.body)) {
    rawBodyBuffer = req.body;
  } else if (typeof req.body === 'string') {
    rawBodyBuffer = Buffer.from(req.body, 'utf8');
  } else if (req.body && typeof req.body === 'object') {
    rawBodyBuffer = Buffer.from(JSON.stringify(req.body), 'utf8');
  } else {
    rawBodyBuffer = Buffer.from('');
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

  const eventPayload = event?.payload || {};
  const paymentEntity = eventPayload?.payment?.entity;
  const orderEntity = eventPayload?.order?.entity;

  // Extract order notes (strictly from order/payment notes, never from request query)
  const notes = orderEntity?.notes || paymentEntity?.notes || {};
  const adId = typeof notes.adId === 'string' ? notes.adId.trim() : null;
  const providerUid = typeof notes.providerUid === 'string' ? notes.providerUid.trim() : null;
  const durationHours = notes.durationHours ? parseInt(notes.durationHours, 10) : null;

  if (!adId || !providerUid || !durationHours) {
    console.warn('[razorpayWebhook] Permanently invalid event: order notes missing adId, providerUid, or durationHours');
    res.status(200).json({ status: 'rejected', reason: 'order_notes_missing' });
    return;
  }

  const paymentId = paymentEntity?.id;
  const orderId = orderEntity?.id || paymentEntity?.order_id;
  const amountPaise = paymentEntity?.amount ?? orderEntity?.amount;
  const currency = paymentEntity?.currency || orderEntity?.currency;

  if (!paymentId || !orderId) {
    console.warn('[razorpayWebhook] Permanently invalid event: missing paymentId or orderId');
    res.status(200).json({ status: 'rejected', reason: 'missing_identifiers' });
    return;
  }

  if (currency !== 'INR') {
    console.warn(`[razorpayWebhook] Permanently invalid event: currency must be INR (received: ${currency})`);
    res.status(200).json({ status: 'rejected', reason: 'currency_mismatch' });
    return;
  }

  const expectedPriceINR = AD_PRICING_TABLE[durationHours];
  if (!expectedPriceINR || amountPaise !== expectedPriceINR * 100) {
    console.warn('[razorpayWebhook] Permanently invalid event: amount mismatch against pricing table');
    res.status(200).json({ status: 'rejected', reason: 'amount_mismatch' });
    return;
  }

  const firestore = db || getFirestore();
  const adRef = firestore.collection('promotedAds').doc(adId);
  const adSnap = await adRef.get();

  if (!adSnap.exists) {
    console.warn('[razorpayWebhook] Permanently invalid event: promoted ad not found');
    res.status(200).json({ status: 'rejected', reason: 'ad_not_found' });
    return;
  }

  const adData = adSnap.data() || {};
  const expectedOrderId = String(adData.razorpayOrderId || '').trim();
  if (!expectedOrderId || expectedOrderId !== orderId) {
    console.warn('[razorpayWebhook] Permanently invalid event: razorpayOrderId mismatch with ad doc');
    res.status(200).json({ status: 'rejected', reason: 'order_id_mismatch' });
    return;
  }

  try {
    const activation = await activatePromotedAdPayment(firestore, {
      adId,
      orderId,
      paymentId,
      providerUid,
      durationHours,
      amountPaise,
      currency,
    });

    console.info(`[razorpayWebhook] Successfully processed ${eventType} for ad ${adId} (idempotent: ${activation.idempotent})`);
    res.status(200).json({
      success: true,
      idempotent: activation.idempotent,
      adId: activation.adId,
    });
  } catch (err) {
    if (err instanceof HttpsError) {
      if (err.code === 'already-exists') {
        console.warn(`[razorpayWebhook] Permanently invalid event: payment ${paymentId} already used for another ad`);
        res.status(200).json({ status: 'rejected', reason: 'payment_already_used' });
        return;
      }
      if (
        err.code === 'failed-precondition' ||
        err.code === 'not-found' ||
        err.code === 'permission-denied' ||
        err.code === 'invalid-argument'
      ) {
        console.warn(`[razorpayWebhook] Permanently invalid event: ${err.message}`);
        res.status(200).json({ status: 'rejected', reason: err.code });
        return;
      }
    }

    console.error('[razorpayWebhook] Transient error committing activation transaction:', err.message);
    res.status(500).send('Internal Server Error');
  }
}

/**
 * 3. onRequest Cloud Function: razorpayWebhook
 * Webhook endpoint for Razorpay payment and order completion events.
 */
const razorpayWebhook = onRequest(
  {
    region: 'asia-south1',
    secrets: [razorpayWebhookSecret],
    invoker: 'public',
  },
  async (req, res) => {
    return razorpayWebhookHandler(req, res, getFirestore());
  }
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

  const userSnap = await db.collection('users').doc(auth.uid).get();
  const userDoc = userSnap.exists ? (userSnap.data() || {}) : {};
  if (!isSuperAdmin(auth, userDoc)) {
    throw new HttpsError('permission-denied', 'Super admin access required.');
  }

  const adRef = db.collection('promotedAds').doc(safeAdId);
  const adSnap = await adRef.get();
  if (!adSnap.exists) {
    throw new HttpsError('not-found', 'Promoted ad document not found.');
  }
  const adData = adSnap.data() || {};
  if (adData.status !== 'pending_approval') {
    throw new HttpsError(
      'failed-precondition',
      `Ad is not pending approval (status: ${adData.status}).`,
    );
  }

  if (safeDecision === 'approve') {
    const hours = parseInt(adData.durationHours, 10);
    if (!AD_PRICING_TABLE[hours]) {
      throw new HttpsError('failed-precondition', 'Ad duration is invalid.');
    }
    const now = Timestamp.now();
    const endTime = Timestamp.fromMillis(now.toMillis() + hours * 3600 * 1000);
    await adRef.update({
      status: 'active',
      startTime: now,
      endTime,
      reviewedBy: auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      reviewDecision: 'approve',
      ...(safeReason ? { reviewReason: safeReason } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, adId: safeAdId, status: 'active' };
  }

  await adRef.update({
    status: 'rejected',
    reviewReason: safeReason || 'Rejected by admin',
    reviewedBy: auth.uid,
    reviewedAt: FieldValue.serverTimestamp(),
    reviewDecision: 'reject',
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, adId: safeAdId, status: 'rejected' };
}

const reviewPromotedAd = onCall(
  { region: 'asia-south1', enforceAppCheck: ENFORCE_ABUSE_APP_CHECK },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }
    assertAppCheck(request, { enforce: ENFORCE_ABUSE_APP_CHECK });
    await enforceAbuseLimit(getFirestore(), request, 'api', {
      message: 'Too many requests. Please try again later.',
    });
    return reviewPromotedAdHandler(getFirestore(), request.data || {}, request.auth);
  },
);

const EXPIRE_BATCH_LIMIT = 400;

async function expirePromotedAdsHandler(db, customNow, chunkSize = EXPIRE_BATCH_LIMIT) {
  const now = customNow || Timestamp.now();
  let totalExpired = 0;
  let batchCount = 0;

  while (true) {
    const snap = await db
      .collection('promotedAds')
      .where('status', '==', 'active')
      .where('endTime', '<=', now)
      .limit(chunkSize)
      .get();

    if (snap.empty) {
      break;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: 'expired',
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    batchCount++;
    totalExpired += snap.docs.length;

    if (snap.docs.length < chunkSize) {
      break;
    }
  }

  return { totalExpired, batchCount };
}

/**
 * 3. Scheduled Cloud Function: expirePromotedAds
 * Runs hourly to set status = 'expired' on any active ad whose endTime has passed.
 */
const expirePromotedAds = onSchedule({ schedule: '0 * * * *', region: 'asia-south1' }, async () => {
  const db = getFirestore();

  try {
    const { totalExpired, batchCount } = await expirePromotedAdsHandler(db);
    if (totalExpired === 0) {
      console.log('[expirePromotedAds] No expired ads found.');
    } else {
      console.log(`[expirePromotedAds] Successfully expired ${totalExpired} ads across ${batchCount} batch(es).`);
    }
  } catch (err) {
    console.error('[expirePromotedAds] Error expiring ads:', err);
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
  razorpayWebhookSecret,
};
