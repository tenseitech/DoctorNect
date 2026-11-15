'use strict';

/**
 * Production cutover: legacy handlers must throw (and log runtime_firestore_blocked)
 * before any Firestore I/O when APP_ENV=production and FIRESTORE_FORBIDDEN=1.
 * Does not inherit shell RUNTIME_DOCUMENT_DB_FORBIDDEN (stripped in setup_env for default suite).
 */

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const blockedLogs = [];

function installProductionFirestoreGuardEnv() {
  process.env.APP_ENV = 'production';
  process.env.FIRESTORE_FORBIDDEN = '1';
  delete process.env.RUNTIME_DOCUMENT_DB_FORBIDDEN;
}

function stubRuntimeFirestoreLogger() {
  blockedLogs.length = 0;
  const { setRuntimeFirestoreBlockedTap } = require('../firestore_forbidden_guard');
  setRuntimeFirestoreBlockedTap((caller) => {
    blockedLogs.push({
      caller,
      appEnv: process.env.APP_ENV || null,
      firestoreForbidden: String(process.env.FIRESTORE_FORBIDDEN || '').trim() || null,
    });
  });
  return () => {
    setRuntimeFirestoreBlockedTap(null);
  };
}

function expectBlocked(caller) {
  assert.ok(blockedLogs.length >= 1, `expected runtime_firestore_blocked log for ${caller}`);
  assert.ok(
    blockedLogs.some((m) => m && m.caller === caller),
    `log must name caller ${caller}, got ${JSON.stringify(blockedLogs)}`,
  );
}

describe('production legacy Firestore entrypoints (APP_ENV=production, FIRESTORE_FORBIDDEN=1)', () => {
  let restoreLogger;

  beforeEach(() => {
    installProductionFirestoreGuardEnv();
    restoreLogger = stubRuntimeFirestoreLogger();
  });

  afterEach(() => {
    if (restoreLogger) restoreLogger();
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  });

  it('legacy db() + getFirestore() throws before I/O', () => {
    const { getLegacyFirestoreDb } = require('../legacy_db');
    assert.equal(getLegacyFirestoreDb(), null);
    const { getFirestore } = require('firebase-admin/firestore');
    assert.throws(() => getFirestore(), (err) => err.code === 'FIRESTORE_FORBIDDEN');
    expectBlocked('getFirestore()');
  });

  it('bookAppointmentHandler throws before doctor_slots collection access', async () => {
    const { bookAppointmentHandler } = require('../appointment_slots');
    const { HttpsError } = require('firebase-functions/v2/https');
    await assert.rejects(
      () => bookAppointmentHandler({ doctorId: 'doc_1', dateTime: Date.now() }, { uid: 'pat_1' }, null),
      (err) => err.code === 'FIRESTORE_FORBIDDEN',
    );
    expectBlocked('bookAppointmentHandler');
  });

  it('consumeOtpChallengeAtomically legacy Firestore branch throws before challenge ref', async () => {
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    const { consumeOtpChallengeAtomically } = require('../registration_otp');
    await assert.rejects(
      () => consumeOtpChallengeAtomically(
        { collection: () => { throw new Error('Firestore I/O must not run'); } },
        {
          challengeKey: 'k1',
          otp: '123456',
          mobileDigits: '9876543210',
          role: 'patient',
          isDemoAccount: false,
        },
      ),
      (err) => err.code === 'FIRESTORE_FORBIDDEN',
    );
    expectBlocked('consumeOtpChallengeAtomically');
  });

  it('razorpayWebhookHandler legacy path throws when Firestore db is null', async () => {
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    process.env.RAZORPAY_WEBHOOK_SECRET = 'webhook_test_secret_hex_32chars!!';
    const { razorpayWebhookHandler } = require('../promoted_ads');
    const raw = JSON.stringify({
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: 'pay_guard_test',
            order_id: 'order_guard_test',
            amount: 30000,
            currency: 'INR',
            notes: { adId: 'ad_guard', providerUid: 'prov_guard', durationHours: '24' },
          },
        },
        order: {
          entity: {
            id: 'order_guard_test',
            amount: 30000,
            currency: 'INR',
            notes: { adId: 'ad_guard', providerUid: 'prov_guard', durationHours: '24' },
          },
        },
      },
    });
    const sig = require('crypto')
      .createHmac('sha256', process.env.RAZORPAY_WEBHOOK_SECRET)
      .update(Buffer.from(raw, 'utf8'))
      .digest('hex');
    const res = {
      statusCode: 0,
      status(code) {
        this.statusCode = code;
        return this;
      },
      json() {},
      send() {},
    };
    const req = {
      method: 'POST',
      headers: { 'x-razorpay-signature': sig },
      rawBody: Buffer.from(raw, 'utf8'),
      body: JSON.parse(raw),
    };

    await assert.rejects(
      () => razorpayWebhookHandler(req, res, null),
      (err) => err.code === 'FIRESTORE_FORBIDDEN',
    );
    expectBlocked('razorpayWebhookHandler');
  });

  it('completeAmbulanceMobileOtpLogin throws before ambulances query', async () => {
    const { completeAmbulanceMobileOtpLogin } = require('../registration_otp');
    const { HttpsError } = require('firebase-functions/v2/https');
    await assert.rejects(
      () => completeAmbulanceMobileOtpLogin(
        null,
        { mobile: '9876543210', sessionId: 'sess_1' },
        { uid: 'amb_uid_1' },
      ),
      (err) => err.code === 'FIRESTORE_FORBIDDEN',
    );
    expectBlocked('completeAmbulanceMobileOtpLogin');
  });
});