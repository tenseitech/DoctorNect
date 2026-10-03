const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const crypto = require('crypto');
const https = require('https');
const { enforceAbuseLimit } = require('./abuse_rate_limit');
const { readSecret } = require('./secure_config');
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
const createRazorpayOrder = onCall({ region: 'asia-south1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to create payment order.');
  }
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
  if (adData.providerId !== request.auth.uid) {
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
});

/**
 * 2. Callable Cloud Function: verifyRazorpayPayment
 * Input: { adId: string, orderId: string, paymentId: string, signature: string }
 */
const verifyRazorpayPayment = onCall({ region: 'asia-south1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required to verify payment.');
  }
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
  if (adData.providerId !== request.auth.uid) {
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

  // Duration and price derived ONLY from order.notes, never from the Firestore row
  const noteDurationHours = parseInt(order.notes?.durationHours, 10);
  const expectedPriceINR = AD_PRICING_TABLE[noteDurationHours];
  if (!expectedPriceINR || payment.amount !== expectedPriceINR * 100) {
    throw new HttpsError('failed-precondition', 'Payment amount or duration mismatch.');
  }

  const paymentLedgerRef = db.collection('razorpayPayments').doc(safePaymentId);
  const now = Timestamp.now();
  const endTime = Timestamp.fromMillis(now.toMillis() + noteDurationHours * 3600 * 1000);

  let isIdempotentSuccess = false;
  let resStartTime = now;
  let resEndTime = endTime;

  // Activation inside a Firestore transaction
  await db.runTransaction(async (tx) => {
    const [currentAdDoc, ledgerDoc] = await Promise.all([
      tx.get(adRef),
      tx.get(paymentLedgerRef),
    ]);

    if (!currentAdDoc.exists) {
      throw new HttpsError('not-found', 'Promoted ad document not found.');
    }

    const currentAd = currentAdDoc.data();
    if (currentAd.providerId !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'You do not own this promoted ad document.');
    }

    // Ledger check: if it exists for the same adId and the ad is already active, return idempotent success; if for a different ad, reject.
    if (ledgerDoc.exists) {
      const ledgerData = ledgerDoc.data();
      if (ledgerData.adId === safeAdId && currentAd.status === 'active' && currentAd.razorpayPaymentId === safePaymentId) {
        isIdempotentSuccess = true;
        resStartTime = currentAd.startTime || now;
        resEndTime = currentAd.endTime || endTime;
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
      providerUid: request.auth.uid,
      paymentId: safePaymentId,
      createdAt: FieldValue.serverTimestamp(),
    });

    // Write durationHours, amountPaid, startTime, endTime from notes-derived values
    tx.update(adRef, {
      paymentStatus: 'verified',
      status: 'active',
      razorpayOrderId: safeOrderId,
      razorpayPaymentId: safePaymentId,
      durationHours: noteDurationHours,
      amountPaid: expectedPriceINR,
      startTime: now,
      endTime: endTime,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return {
    success: true,
    idempotent: isIdempotentSuccess,
    message: isIdempotentSuccess
      ? 'Payment already verified and banner ad is active (idempotent)'
      : 'Payment verified and banner ad activated successfully!',
    adId: safeAdId,
    startTime: resStartTime.toDate ? resStartTime.toDate().toISOString() : new Date(resStartTime).toISOString(),
    endTime: resEndTime.toDate ? resEndTime.toDate().toISOString() : new Date(resEndTime).toISOString(),
  };
});

/**
 * 3. Scheduled Cloud Function: expirePromotedAds
 * Runs hourly to set status = 'expired' on any active ad whose endTime has passed.
 */
const expirePromotedAds = onSchedule({ schedule: '0 * * * *', region: 'asia-south1' }, async () => {
  const db = getFirestore();
  const now = Timestamp.now();

  try {
    const snap = await db
      .collection('promotedAds')
      .where('status', '==', 'active')
      .where('endTime', '<=', now)
      .get();

    if (snap.empty) {
      console.log('[expirePromotedAds] No expired ads found.');
      return;
    }

    const batch = db.batch();
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: 'expired',
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`[expirePromotedAds] Successfully expired ${snap.docs.length} ads.`);
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
  expirePromotedAds,
};
