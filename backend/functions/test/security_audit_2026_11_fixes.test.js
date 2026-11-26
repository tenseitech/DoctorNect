'use strict';

/**
 * Regression tests for the 2026-11-24 security audit fixes:
 *  - client IP is taken from the rightmost X-Forwarded-For hop (rate-limit bypass)
 *  - confirmS3Upload authorizes before touching S3 and checks magic bytes (IDOR delete)
 *  - Razorpay order/verify run on Postgres with server-side pricing + ownership (payments)
 *  - Payment activation is a compare-and-set (no double activation)
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('https');
const { EventEmitter } = require('events');

const { clientIpFromRawRequest, clientIpFromRequest } = require('../abuse_rate_limit');

test('client IP uses the rightmost X-Forwarded-For hop, not the spoofable leftmost', () => {
  const raw = { headers: { 'x-forwarded-for': '1.2.3.4, 203.0.113.9' }, ip: '10.0.0.1' };
  assert.equal(clientIpFromRawRequest(raw), '203.0.113.9');
  assert.equal(clientIpFromRequest({ rawRequest: raw }), '203.0.113.9');
  assert.equal(clientIpFromRawRequest({ headers: {}, ip: '198.51.100.7' }), '198.51.100.7');
  assert.equal(clientIpFromRawRequest(null), 'unknown');
});

// ---------------------------------------------------------------------------
// S3 confirm upload
// ---------------------------------------------------------------------------
const { _test: s3 } = require('../s3_storage');

const { createPgFromLegacySeed } = require('./helpers/legacy_seed_to_pg');
const legacyDb = (initial = {}) => createPgFromLegacySeed(initial);

function s3ClientRecorder({ head, body } = {}) {
  const calls = [];
  return {
    calls,
    async send(cmd) {
      const name = cmd?.constructor?.name;
      calls.push(name);
      if (name === 'HeadObjectCommand') return head || { ContentType: 'application/pdf', ContentLength: 2048 };
      if (name === 'GetObjectCommand') return body ? { Body: body } : {};
      return {};
    },
  };
}

function withLegacy(fn) {
  return async () => {
    const prev = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    try {
      await fn();
    } finally {
      if (prev === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
      else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = prev;
    }
  };
}

test('confirmS3Upload: unknown prefix (prescriptions/) is denied and S3 is never touched', withLegacy(async () => {
  const client = s3ClientRecorder();
  s3.setS3ClientForTesting(client);
  const db = legacyDb({ users: { attacker: { role: 'doctor', profileId: 'd_1' } } });
  await assert.rejects(
    s3.confirmS3UploadHandler(
      { objectKey: 'prescriptions/p_victim/rx_1/file.pdf', purpose: 'patient_profile' },
      { uid: 'attacker' },
      db,
    ),
    (err) => err.code === 'permission-denied',
  );
  assert.deepEqual(client.calls, [], 'no HEAD/DELETE may run before authorization');
}));

test('confirmS3Upload: purpose/prefix mismatch is denied (no image-limit deletion trick)', withLegacy(async () => {
  const client = s3ClientRecorder();
  s3.setS3ClientForTesting(client);
  const db = legacyDb({ users: { p_1: { role: 'patient', profileId: 'p_1' } } });
  await assert.rejects(
    s3.confirmS3UploadHandler(
      { objectKey: 'health_records/p_1/rec_1/a.pdf', purpose: 'patient_profile' },
      { uid: 'p_1' },
      db,
    ),
    (err) => err.code === 'permission-denied',
  );
  assert.deepEqual(client.calls, []);
}));

test('confirmS3Upload: lab cannot confirm a report for a booking it does not own', withLegacy(async () => {
  const client = s3ClientRecorder();
  s3.setS3ClientForTesting(client);
  const db = legacyDb({
    users: { lab_evil: { role: 'lab', profileId: 'lab_evil' } },
    lab_bookings: { bk_1: { labId: 'lab_owner' } },
  });
  await assert.rejects(
    s3.confirmS3UploadHandler(
      { objectKey: 'lab_reports/p_1/bk_1/r.pdf', purpose: 'lab_reports' },
      { uid: 'lab_evil' },
      db,
    ),
    (err) => err.code === 'permission-denied',
  );
  assert.deepEqual(client.calls, []);
}));

test('confirmS3Upload: declared PDF whose bytes are not a PDF is rejected and deleted', withLegacy(async () => {
  const client = s3ClientRecorder({
    head: { ContentType: 'application/pdf', ContentLength: 2048 },
    body: Buffer.from('<html><script>x</script>'),
  });
  s3.setS3ClientForTesting(client);
  const db = legacyDb({ users: { p_1: { role: 'patient', profileId: 'p_1' } } });
  await assert.rejects(
    s3.confirmS3UploadHandler(
      { objectKey: 'health_records/p_1/rec_1/a.pdf', purpose: 'health_records' },
      { uid: 'p_1' },
      db,
    ),
    (err) => err.code === 'failed-precondition',
  );
  assert.ok(client.calls.includes('DeleteObjectCommand'));
}));

// ---------------------------------------------------------------------------
// Razorpay (Postgres path)
// ---------------------------------------------------------------------------
const promotedAds = require('../promoted_ads');
const { createPromotedAdsSupabaseMock } = require('./helpers/promoted_ads_supabase_mock');

function mockRazorpayHttp(responder) {
  const original = https.request;
  const sent = [];
  https.request = (options, cb) => {
    const req = new EventEmitter();
    let body = '';
    req.write = (d) => { body += d; };
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.end = () => {
      sent.push({ path: options.path, method: options.method, body: body ? JSON.parse(body) : null });
      const res = new EventEmitter();
      res.statusCode = 200;
      cb(res);
      res.emit('data', JSON.stringify(responder(options, body)));
      res.emit('end');
    };
    return req;
  };
  return { sent, restore: () => { https.request = original; } };
}

function withRazorpayEnv(fn) {
  return async () => {
    const prev = { id: process.env.RAZORPAY_KEY_ID, secret: process.env.RAZORPAY_KEY_SECRET, legacy: process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT };
    process.env.RAZORPAY_KEY_ID = 'rzp_test_unit';
    process.env.RAZORPAY_KEY_SECRET = 'unit_secret';
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    try {
      await fn();
    } finally {
      promotedAds.setSupabaseClientForTesting(null);
      if (prev.id === undefined) delete process.env.RAZORPAY_KEY_ID; else process.env.RAZORPAY_KEY_ID = prev.id;
      if (prev.secret === undefined) delete process.env.RAZORPAY_KEY_SECRET; else process.env.RAZORPAY_KEY_SECRET = prev.secret;
      if (prev.legacy !== undefined) process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = prev.legacy;
    }
  };
}

test('createRazorpayOrder (Postgres): amount comes from server pricing, client amount ignored', withRazorpayEnv(async () => {
  const sb = createPromotedAdsSupabaseMock({
    ads: { ad_1: { ad_id: 'ad_1', provider_id: 'doc_uid', status: 'draft', duration_hours: 24 } },
    users: { doc_uid: { id: 'doc_uid', firebase_uid: 'doc_uid', role: 'doctor', profile_id: 'doc_uid' } },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  const http = mockRazorpayHttp(() => ({ id: 'order_new_1', amount: 30000, currency: 'INR' }));
  try {
    const res = await promotedAds.createRazorpayOrder.run({
      auth: { uid: 'doc_uid' },
      app: { appId: 'x' },
      data: { adId: 'ad_1', durationHours: 24, amount: 1 },
    });
    assert.equal(res.orderId, 'order_new_1');
    assert.equal(res.amount, 300);
    const post = http.sent.find((s) => s.method === 'POST');
    assert.equal(post.body.amount, 30000);
    assert.equal(post.body.notes.providerUid, 'doc_uid');
    assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
    assert.equal(sb.orders.get('order_new_1').amount_paise, 30000);
  } finally {
    http.restore();
  }
}));

test('createRazorpayOrder (Postgres): non-owner and patient are rejected', withRazorpayEnv(async () => {
  const sb = createPromotedAdsSupabaseMock({
    ads: { ad_1: { ad_id: 'ad_1', provider_id: 'owner_uid', status: 'draft' } },
    users: {
      other_uid: { id: 'other_uid', firebase_uid: 'other_uid', role: 'doctor', profile_id: 'other_uid' },
      pat_uid: { id: 'pat_uid', firebase_uid: 'pat_uid', role: 'patient', profile_id: 'owner_uid' },
    },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  const http = mockRazorpayHttp(() => ({ id: 'order_x', amount: 30000, currency: 'INR' }));
  try {
    await assert.rejects(
      promotedAds.createRazorpayOrder.run({ auth: { uid: 'other_uid' }, app: { appId: 'x' }, data: { adId: 'ad_1', durationHours: 24 } }),
      (err) => err.code === 'permission-denied',
    );
    await assert.rejects(
      promotedAds.createRazorpayOrder.run({ auth: { uid: 'pat_uid' }, app: { appId: 'x' }, data: { adId: 'ad_1', durationHours: 24 } }),
      (err) => err.code === 'permission-denied',
    );
    assert.equal(http.sent.length, 0, 'no Razorpay order may be created for unauthorized callers');
  } finally {
    http.restore();
  }
}));

test('activatePromotedAdPayment (Postgres): concurrent second activation is idempotent, not double', withRazorpayEnv(async () => {
  const sb = createPromotedAdsSupabaseMock({
    ads: { ad_1: { ad_id: 'ad_1', provider_id: 'doc_uid', status: 'pending_payment', razorpay_order_id: 'order_unit_00001' } },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  const args = {
    adId: 'ad_1', orderId: 'order_unit_00001', paymentId: 'pay_unit_000001', providerUid: 'doc_uid',
    durationHours: 24, amountPaise: 30000, currency: 'INR',
  };
  const first = await promotedAds.activatePromotedAdPayment(null, args);
  assert.equal(first.idempotent, false);
  assert.equal(sb.ads.get('ad_1').status, 'pending_approval');
  const second = await promotedAds.activatePromotedAdPayment(null, args);
  assert.equal(second.idempotent, true);
}));

test('activatePromotedAdPayment (Postgres): tampered amount is rejected', withRazorpayEnv(async () => {
  const sb = createPromotedAdsSupabaseMock({
    ads: { ad_1: { ad_id: 'ad_1', provider_id: 'doc_uid', status: 'pending_payment', razorpay_order_id: 'order_unit_00001' } },
  });
  promotedAds.setSupabaseClientForTesting(sb);
  await assert.rejects(
    promotedAds.activatePromotedAdPayment(null, {
      adId: 'ad_1', orderId: 'order_unit_00001', paymentId: 'pay_unit_000001', providerUid: 'doc_uid',
      durationHours: 720, amountPaise: 100, currency: 'INR',
    }),
    (err) => err.code === 'failed-precondition',
  );
  assert.equal(sb.ads.get('ad_1').status, 'pending_payment');
}));

test('getS3UploadUrl: no client flow may obtain an upload URL under prescriptions/', withLegacy(async () => {
  const client = s3ClientRecorder();
  s3.setS3ClientForTesting(client);
  const db = legacyDb({ users: { doc_1: { role: 'doctor', profileId: 'd_1' } } });
  for (const purpose of ['prescriptions', 'prescription', 'prescription_pdf']) {
    await assert.rejects(
      s3.getS3UploadUrlHandler(
        { purpose, parentId: 'p_1', fileName: 'rx.pdf', contentType: 'application/pdf', sizeBytes: 1000 },
        { uid: 'doc_1' },
        db,
      ),
      (err) => ['invalid-argument', 'permission-denied'].includes(err.code),
      purpose,
    );
  }
  assert.deepEqual(client.calls, []);
}));
