'use strict';

const { before, after, beforeEach, test, describe } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const EventEmitter = require('events');
const https = require('https');
const path = require('path');
const fs = require('fs');

// ----------------------------------------------------------------------------
// PART 1: RULES UNIT TESTS (using @firebase/rules-unit-testing on real firestore.rules)
// Requires Firestore emulator running (FIRESTORE_EMULATOR_HOST).
// ----------------------------------------------------------------------------
const EMULATOR_RUNNING = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

if (!EMULATOR_RUNNING) {
  test('firestore.rules security tests (NOT RUN: FIRESTORE_EMULATOR_HOST not set; requires emulator with JDK 21+)', { skip: 'FIRESTORE_EMULATOR_HOST not set' }, () => {});
} else {
  const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
  const PROJECT_ID = 'demo-doctornect-promoted-rules';
  const PROVIDER_UID = 'provider_auth_uid_1';
  let testEnv;

  describe('firestore.rules: promotedAds & razorpayPayments security rules', () => {
    before(async () => {
      testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: {
          rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
        },
      });

      // Seed provider user profile
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection('users').doc(PROVIDER_UID).set({
          role: 'doctor',
          profileId: 'doc_123',
          mobile: '7666892394',
        });
      });
    });

    after(async () => {
      if (testEnv) await testEnv.cleanup();
    });

    test('Dart actual create payload (promoted_ads_service.dart:145-168) is allowed', async () => {
      const providerCtx = testEnv.authenticatedContext(PROVIDER_UID);
      const adId = 'ad_dart_create_valid';

      // Exact field structure from lib/core/services/promoted_ads_service.dart:145-168
      const dartPayload = {
        adId: adId,
        providerType: 'doctor',
        providerId: PROVIDER_UID,
        title: 'Dr Special Consultation',
        description: 'Best care provided',
        imageUrl: 'https://example.com/banner.jpg',
        imageKey: `promoted_ads/${PROVIDER_UID}/${adId}/banner.jpg`,
        imageStorage: 's3',
        ctaLabel: 'Book Now',
        durationHours: 24,
        amountPaid: 300,
        targetCity: 'Mumbai',
        targetCities: ['Mumbai', 'Pune'],
        paymentStatus: 'pending',
        status: 'draft',
        createdAt: new Date(),
      };

      await assertSucceeds(
        providerCtx.firestore().collection('promotedAds').doc(adId).set(dartPayload)
      );
    });

    test('Owner creating an ad with forbidden keys (razorpayOrderId, razorpayPaymentId, startTime, endTime) is rejected', async () => {
      const providerCtx = testEnv.authenticatedContext(PROVIDER_UID);
      
      for (const forbiddenKey of ['razorpayOrderId', 'razorpayPaymentId', 'startTime', 'endTime']) {
        const adId = `ad_forbidden_create_${forbiddenKey}`;
        await assertFails(
          providerCtx.firestore().collection('promotedAds').doc(adId).set({
            adId: adId,
            providerType: 'doctor',
            providerId: PROVIDER_UID,
            title: 'Ad Title',
            description: 'Ad Description',
            imageUrl: 'https://example.com/banner.jpg',
            imageKey: `promoted_ads/${PROVIDER_UID}/${adId}/banner.jpg`,
            imageStorage: 's3',
            ctaLabel: 'Book',
            durationHours: 24,
            amountPaid: 300,
            paymentStatus: 'pending',
            status: 'draft',
            [forbiddenKey]: forbiddenKey.includes('Time') ? new Date() : 'fake_value',
          })
        );
      }
    });

    test('Owner changing durationHours, razorpayOrderId, razorpayPaymentId, amountPaid, startTime, endTime, paymentStatus on update is rejected', async () => {
      const providerCtx = testEnv.authenticatedContext(PROVIDER_UID);
      const adId = 'ad_test_field_tampering';

      // Create initial valid draft
      await assertSucceeds(
        providerCtx.firestore().collection('promotedAds').doc(adId).set({
          adId: adId,
          providerType: 'doctor',
          providerId: PROVIDER_UID,
          title: 'Ad Title',
          description: 'Ad Description',
          imageUrl: 'https://example.com/banner.jpg',
          imageKey: `promoted_ads/${PROVIDER_UID}/${adId}/banner.jpg`,
          imageStorage: 's3',
          ctaLabel: 'Book',
          durationHours: 24,
          amountPaid: 300,
          paymentStatus: 'pending',
          status: 'draft',
          createdAt: new Date(),
        })
      );

      // Attempt forbidden updates
      const forbiddenUpdates = [
        { durationHours: 168 },
        { razorpayOrderId: 'order_hacked_999' },
        { razorpayPaymentId: 'pay_hacked_999' },
        { amountPaid: 100 },
        { startTime: new Date() },
        { endTime: new Date() },
        { paymentStatus: 'verified' },
      ];

      for (const updateObj of forbiddenUpdates) {
        await assertFails(
          providerCtx.firestore().collection('promotedAds').doc(adId).update(updateObj)
        );
      }
    });

    test('Owner setting status to active directly on update is rejected', async () => {
      const providerCtx = testEnv.authenticatedContext(PROVIDER_UID);
      const adId = 'ad_test_status_active_tamper';

      await assertSucceeds(
        providerCtx.firestore().collection('promotedAds').doc(adId).set({
          adId: adId,
          providerType: 'doctor',
          providerId: PROVIDER_UID,
          title: 'Ad Title',
          description: 'Ad Description',
          imageUrl: 'https://example.com/banner.jpg',
          imageKey: `promoted_ads/${PROVIDER_UID}/${adId}/banner.jpg`,
          imageStorage: 's3',
          ctaLabel: 'Book',
          durationHours: 24,
          amountPaid: 300,
          paymentStatus: 'pending',
          status: 'draft',
          createdAt: new Date(),
        })
      );

      await assertFails(
        providerCtx.firestore().collection('promotedAds').doc(adId).update({
          status: 'active',
        })
      );
    });

    test('Client read and write on razorpayPayments ledger collection is completely forbidden', async () => {
      const providerCtx = testEnv.authenticatedContext(PROVIDER_UID);
      const ledgerId = 'pay_test_ledger_access';

      await assertFails(
        providerCtx.firestore().collection('razorpayPayments').doc(ledgerId).set({
          adId: 'ad_123',
          orderId: 'order_123',
        })
      );

      await assertFails(
        providerCtx.firestore().collection('razorpayPayments').doc(ledgerId).get()
      );

      await assertFails(
        providerCtx.firestore().collection('razorpayPayments').doc(ledgerId).delete()
      );
    });
  });
}

// ----------------------------------------------------------------------------
// PART 2: REAL FUNCTION CALL TESTS (verifyRazorpayPayment & createRazorpayOrder)
// Calls the real exported functions from ../promoted_ads.
// Stubs: firebase-admin Firestore (in-memory mock store) & Razorpay HTTP API.
// ----------------------------------------------------------------------------

// Mock abuse rate limiter so unit tests don't depend on abuse_rate_limits
require.cache[require.resolve('../abuse_rate_limit')] = {
  exports: {
    enforceAbuseLimit: async () => {},
  },
};

// Set test environment secrets
const TEST_KEY_ID = 'rzp_test_key_abc123';
const TEST_KEY_SECRET = 'rzp_test_secret_xyz789';
process.env.RAZORPAY_KEY_ID = TEST_KEY_ID;
process.env.RAZORPAY_KEY_SECRET = TEST_KEY_SECRET;

// In-memory Firestore mock store
let mockFirestoreStore = new Map();
let mockFirestoreWrites = [];

function createMockFirestore() {
  function getDocRef(collectionName, docId) {
    const docPath = `${collectionName}/${docId}`;
    return {
      id: docId,
      path: docPath,
      get: async () => {
        const val = mockFirestoreStore.get(docPath);
        return {
          exists: val !== undefined,
          id: docId,
          data: () => (val !== undefined ? JSON.parse(JSON.stringify(val)) : undefined),
        };
      },
      update: async (updates) => {
        mockFirestoreWrites.push({ type: 'update', docPath, updates });
        if (!mockFirestoreStore.has(docPath)) {
          throw new Error(`Document not found: ${docPath}`);
        }
        mockFirestoreStore.set(docPath, { ...mockFirestoreStore.get(docPath), ...updates });
      },
      set: async (data) => {
        mockFirestoreWrites.push({ type: 'set', docPath, data });
        mockFirestoreStore.set(docPath, JSON.parse(JSON.stringify(data)));
      },
    };
  }

  return {
    collection: (name) => ({
      doc: (id) => getDocRef(name, id),
    }),
    runTransaction: async (updateFunction) => {
      const stagedWrites = [];
      const tx = {
        get: async (docRef) => {
          const val = mockFirestoreStore.get(docRef.path);
          return {
            exists: val !== undefined,
            id: docRef.id,
            data: () => (val !== undefined ? JSON.parse(JSON.stringify(val)) : undefined),
          };
        },
        set: (docRef, data) => {
          stagedWrites.push({ type: 'set', docPath: docRef.path, data: JSON.parse(JSON.stringify(data)) });
        },
        update: (docRef, updates) => {
          stagedWrites.push({ type: 'update', docPath: docRef.path, updates: JSON.parse(JSON.stringify(updates)) });
        },
      };

      await updateFunction(tx);

      // On successful execution without throw, commit staged writes
      for (const op of stagedWrites) {
        mockFirestoreWrites.push(op);
        if (op.type === 'set') {
          mockFirestoreStore.set(op.docPath, op.data);
        } else if (op.type === 'update') {
          const current = mockFirestoreStore.get(op.docPath) || {};
          mockFirestoreStore.set(op.docPath, { ...current, ...op.updates });
        }
      }
    },
  };
}

// Inject mock Firestore into firebase-admin/firestore
const firestoreModule = require('firebase-admin/firestore');
firestoreModule.getFirestore = createMockFirestore;

// HTTP stub for Razorpay API calls
let mockRazorpayResponses = {};

const originalHttpsRequest = https.request;
https.request = (options, callback) => {
  const req = new EventEmitter();
  let postDataChunks = '';
  req.write = (chunk) => {
    if (chunk) postDataChunks += chunk;
  };
  req.end = () => {
    process.nextTick(() => {
      const method = options.method || 'GET';
      const exactKey = `${method} ${options.path}`;
      let mockConfig = mockRazorpayResponses[exactKey];

      if (!mockConfig) {
        const matchedKey = Object.keys(mockRazorpayResponses).find((k) => {
          if (k.includes(' ')) {
            const [m, p] = k.split(' ');
            return m === method && options.path.includes(p);
          }
          return options.path.includes(k);
        });
        mockConfig = matchedKey ? mockRazorpayResponses[matchedKey] : { statusCode: 404, body: { error: 'Not Found' } };
      }

      const res = new EventEmitter();
      res.statusCode = mockConfig.statusCode || 200;
      callback(res);
      const resBody = typeof mockConfig.body === 'function' ? mockConfig.body(postDataChunks) : mockConfig.body;
      res.emit('data', JSON.stringify(resBody));
      res.emit('end');
    });
  };
  return req;
};

// Require the REAL functions under test
const { verifyRazorpayPayment, createRazorpayOrder, AD_PRICING_TABLE } = require('../promoted_ads');

// Helper to compute valid Razorpay signature
function computeRazorpaySignature(orderId, paymentId, secret = TEST_KEY_SECRET) {
  return crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');
}

describe('verifyRazorpayPayment: real function unit tests', () => {
  const UID = 'provider_test_123';
  const AD_ID = 'ad_promoted_1001';
  const ORDER_ID = 'order_test_9001';
  const PAYMENT_ID = 'pay_test_8001';

  beforeEach(() => {
    mockFirestoreStore.clear();
    mockFirestoreWrites = [];
    mockRazorpayResponses = {};
  });

  after(() => {
    https.request = originalHttpsRequest;
  });

  test('1. wrong ownership: rejects caller who does not own ad', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: 'different_provider',
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: {
          adId: AD_ID,
          orderId: ORDER_ID,
          paymentId: PAYMENT_ID,
          signature: computeRazorpaySignature(ORDER_ID, PAYMENT_ID),
        },
      }),
      (err) => err.code === 'permission-denied' && err.message.includes('do not own')
    );
  });

  test('2. orderId mismatch: rejects request when orderId does not match ad doc', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: 'order_registered_different',
    });

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: {
          adId: AD_ID,
          orderId: ORDER_ID,
          paymentId: PAYMENT_ID,
          signature: computeRazorpaySignature(ORDER_ID, PAYMENT_ID),
        },
      }),
      (err) => err.code === 'invalid-argument' && err.message.includes('Order does not match')
    );
  });

  test('3. bad signature: fails closed and asserts NO writes to Firestore', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    const badSignature = '0000000000000000000000000000000000000000000000000000000000000000';

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: {
          adId: AD_ID,
          orderId: ORDER_ID,
          paymentId: PAYMENT_ID,
          signature: badSignature,
        },
      }),
      (err) => err.code === 'invalid-argument' && err.message.includes('signature verification failed')
    );

    // Verify zero writes were performed
    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('4. payment not captured: rejects if Razorpay payment is authorized but not captured', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: {
        id: PAYMENT_ID,
        status: 'authorized', // Not captured
        order_id: ORDER_ID,
        currency: 'INR',
        amount: 30000,
      },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' },
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'failed-precondition' && err.message.includes('Payment not captured')
    );

    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('5. notes.adId mismatch: rejects if Razorpay order notes belongs to another ad', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 30000, currency: 'INR' },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: 'different_stolen_ad', providerUid: UID, durationHours: '24' },
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'failed-precondition' && err.message.includes('Order notes mismatch')
    );

    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('6. amount mismatch: rejects if paid amount does not match pricing table', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 10000, currency: 'INR' }, // Paid 100 INR instead of 300 INR
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' }, // 24h = 300 INR
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'failed-precondition' && err.message.includes('amount or duration mismatch')
    );

    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('7. duration taken from notes: activates using notes even if row durationHours was tampered', async () => {
    // Ad row in Firestore has tampered durationHours: 168 (7 days)
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
      durationHours: 168,
      amountPaid: 1500,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    // Notes specifies 24 hours, payment is 30000 paise (300 INR)
    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 30000, currency: 'INR' },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' },
      },
    };

    const result = await verifyRazorpayPayment.run({
      auth: { uid: UID },
      data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
    });

    assert.equal(result.success, true);
    assert.equal(result.idempotent, false);

    // Verify Firestore updates took durationHours and amountPaid from notes/pricing table
    const updatedAd = mockFirestoreStore.get(`promotedAds/${AD_ID}`);
    assert.equal(updatedAd.status, 'active');
    assert.equal(updatedAd.paymentStatus, 'verified');
    assert.equal(updatedAd.durationHours, 24);
    assert.equal(updatedAd.amountPaid, 300);
    assert.equal(updatedAd.razorpayPaymentId, PAYMENT_ID);

    // Verify ledger doc created
    const ledger = mockFirestoreStore.get(`razorpayPayments/${PAYMENT_ID}`);
    assert.ok(ledger);
    assert.equal(ledger.adId, AD_ID);
    assert.equal(ledger.paymentId, PAYMENT_ID);
  });

  test('8. replay of used paymentId on another ad is rejected', async () => {
    // Ledger doc already exists for AD_ID
    mockFirestoreStore.set(`razorpayPayments/${PAYMENT_ID}`, {
      adId: AD_ID,
      orderId: ORDER_ID,
      providerUid: UID,
      paymentId: PAYMENT_ID,
    });

    const otherAdId = 'ad_promoted_2002';
    const otherOrderId = 'order_test_9002';
    mockFirestoreStore.set(`promotedAds/${otherAdId}`, {
      adId: otherAdId,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: otherOrderId,
    });

    const signature = computeRazorpaySignature(otherOrderId, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: otherOrderId, amount: 30000, currency: 'INR' },
    };
    mockRazorpayResponses[`/v1/orders/${otherOrderId}`] = {
      statusCode: 200,
      body: {
        id: otherOrderId,
        notes: { adId: otherAdId, providerUid: UID, durationHours: '24' },
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: otherAdId, orderId: otherOrderId, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'already-exists' && err.message.includes('already been used')
    );
  });

  test('9. replay on an expired ad is rejected', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'expired', // Expired ad
      razorpayOrderId: ORDER_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 30000, currency: 'INR' },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' },
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'failed-precondition' && err.message.includes('not in pending_payment state')
    );
  });

  test('10. idempotent retry on an active ad succeeds without re-activation', async () => {
    // Ad already active
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'active',
      razorpayOrderId: ORDER_ID,
      razorpayPaymentId: PAYMENT_ID,
      durationHours: 24,
      amountPaid: 300,
    });

    // Ledger doc already exists for same ad and payment
    mockFirestoreStore.set(`razorpayPayments/${PAYMENT_ID}`, {
      adId: AD_ID,
      orderId: ORDER_ID,
      providerUid: UID,
      paymentId: PAYMENT_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 30000, currency: 'INR' },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' },
      },
    };

    const result = await verifyRazorpayPayment.run({
      auth: { uid: UID },
      data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
    });

    assert.equal(result.success, true);
    assert.equal(result.idempotent, true);
    assert.ok(result.message.includes('idempotent'));
  });

  test('11. verifyRazorpayPayment: currency mismatch (not INR) is rejected', async () => {
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      razorpayOrderId: ORDER_ID,
    });

    const signature = computeRazorpaySignature(ORDER_ID, PAYMENT_ID);

    mockRazorpayResponses[`/v1/payments/${PAYMENT_ID}`] = {
      statusCode: 200,
      body: { id: PAYMENT_ID, status: 'captured', order_id: ORDER_ID, amount: 30000, currency: 'USD' },
    };
    mockRazorpayResponses[`/v1/orders/${ORDER_ID}`] = {
      statusCode: 200,
      body: {
        id: ORDER_ID,
        notes: { adId: AD_ID, providerUid: UID, durationHours: '24' },
      },
    };

    await assert.rejects(
      verifyRazorpayPayment.run({
        auth: { uid: UID },
        data: { adId: AD_ID, orderId: ORDER_ID, paymentId: PAYMENT_ID, signature },
      }),
      (err) => err.code === 'failed-precondition' && err.message.includes('currency must be INR')
    );

    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('12. createRazorpayOrder: reuses existing order if status is pending_payment and durationHours matches', async () => {
    const existingOrderId = 'order_existing_reuse_123';
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      durationHours: 24,
      amountPaid: 300,
      razorpayOrderId: existingOrderId,
    });

    mockRazorpayResponses[`GET /v1/orders/${existingOrderId}`] = {
      statusCode: 200,
      body: {
        id: existingOrderId,
        amount: 30000,
        currency: 'INR',
        notes: {
          adId: AD_ID,
          providerUid: UID,
          durationHours: '24',
        },
      },
    };

    let postOrderCalled = false;
    mockRazorpayResponses[`POST /v1/orders`] = {
      statusCode: 200,
      body: () => {
        postOrderCalled = true;
        return { id: 'order_unexpected_new' };
      },
    };

    const result = await createRazorpayOrder.run({
      auth: { uid: UID },
      data: { adId: AD_ID, durationHours: 24 },
    });

    assert.equal(result.orderId, existingOrderId);
    assert.equal(result.amount, 300);
    assert.equal(result.currency, 'INR');
    assert.equal(postOrderCalled, false);
    // Assert no extra update was written
    assert.equal(mockFirestoreWrites.length, 0);
  });

  test('13. createRazorpayOrder: creates new order when durationHours differs on pending ad', async () => {
    const existingOrderId = 'order_old_24h';
    mockFirestoreStore.set(`promotedAds/${AD_ID}`, {
      adId: AD_ID,
      providerId: UID,
      status: 'pending_payment',
      durationHours: 24,
      amountPaid: 300,
      razorpayOrderId: existingOrderId,
    });

    const newOrderId = 'order_new_72h';
    let postOrderCalled = false;
    mockRazorpayResponses[`POST /v1/orders`] = {
      statusCode: 200,
      body: () => {
        postOrderCalled = true;
        return {
          id: newOrderId,
          amount: 75000,
          currency: 'INR',
          notes: {
            adId: AD_ID,
            providerUid: UID,
            durationHours: '72',
          },
        };
      },
    };

    const result = await createRazorpayOrder.run({
      auth: { uid: UID },
      data: { adId: AD_ID, durationHours: 72 },
    });

    assert.equal(result.orderId, newOrderId);
    assert.equal(result.amount, 750);
    assert.equal(result.currency, 'INR');
    assert.equal(postOrderCalled, true);

    const updatedAd = mockFirestoreStore.get(`promotedAds/${AD_ID}`);
    assert.equal(updatedAd.durationHours, 72);
    assert.equal(updatedAd.amountPaid, 750);
    assert.equal(updatedAd.razorpayOrderId, newOrderId);
  });
});
