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
function makeRazorpayRequest(path, method, payload, keyId, keySecret) {
  return new Promise((resolve, reject) => {
    const authHeader = 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64');
    const postData = JSON.stringify(payload);

    const options = {
      hostname: 'api.razorpay.com',
      port: 443,
      path: path,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': authHeader,
        'Content-Length': Buffer.byteLength(postData),
      },
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
    req.write(postData);
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

  const { keyId, keySecret } = getRazorpayCredentials();
  const amountPaise = amountINR * 100;

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

  const { keySecret } = getRazorpayCredentials();

  // Server-side HMAC SHA256 signature verification per Razorpay spec
  const payload = `${safeOrderId}|${safePaymentId}`;
  const generatedSignature = crypto
    .createHmac('sha256', keySecret)
    .update(payload)
    .digest('hex');

  const isVerified = generatedSignature.toLowerCase() === safeSignature.toLowerCase();

  if (!isVerified) {
    console.warn(`[verifyRazorpayPayment] Signature mismatch for ad ${safeAdId}`);
    await adRef.update({
      paymentStatus: 'failed',
      status: 'rejected',
      razorpayPaymentId: safePaymentId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError('invalid-argument', 'Razorpay payment signature verification failed.');
  }

  const durationHours = parseInt(adData.durationHours || 24, 10);
  const now = Timestamp.now();
  const endTime = Timestamp.fromMillis(now.toMillis() + durationHours * 3600 * 1000);

  // Update via Admin SDK: set status to active and paymentStatus to verified
  await adRef.update({
    paymentStatus: 'verified',
    status: 'active',
    razorpayOrderId: safeOrderId,
    razorpayPaymentId: safePaymentId,
    startTime: now,
    endTime: endTime,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    message: 'Payment verified and banner ad activated successfully!',
    adId: safeAdId,
    startTime: now.toDate().toISOString(),
    endTime: endTime.toDate().toISOString(),
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
  createRazorpayOrder,
  verifyRazorpayPayment,
  expirePromotedAds,
};
