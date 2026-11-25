'use strict';

/**
 * OTP send policy on the Redis-only path. Replaces otp_retry_fallback.test.js, whose subject
 * (MSG91 "retry" of an existing Firestore otp_challenges doc, and "never touch Redis when the
 * mirror is off") no longer exists: challenges live only in Redis and Redis is mandatory.
 *
 * Covered here:
 *  - resend cooldown (60s) blocks a second SMS; after the cooldown a NEW code replaces the old one
 *  - an undelivered SMS removes the challenge so the user is not stuck behind the cooldown
 *  - login / forgot-password use their own DLT template (otpType forwarded to MSG91)
 *  - challenge TTL <= 5 minutes, key env-prefixed + HMAC (no raw number in the key)
 *  - production without an HMAC secret fails closed without leaking secrets
 *  - legacy unsalted hash only behind ALLOW_LEGACY_UNSALTED_OTP_HASH
 *  - verify-path Redis read is bounded by a timeout
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('https');
const { EventEmitter } = require('events');

process.env.MSG91_AUTH_KEY = 'mock_auth_key_123';
process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'tpl_registration';
process.env.MSG91_TEMPLATE_ID_LOGIN = 'tpl_login';
process.env.MSG91_TEMPLATE_ID_PASSWORD_RESET = 'tpl_reset';
process.env.MSG91_TEMPLATE_ID = 'tpl_shared';
process.env.MSG91_SENDER_ID = 'DRNECT';
delete process.env.OTP_TEST_MODE;
delete process.env.MSG91_PROXY_URL;

const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');
const { setDatabaseClientForTesting } = require('../src/db/client');
const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
const {
  sendUserRegistrationOtp,
  consumeOtpChallengeAtomically,
  legacyHashOtp,
  hashOtp,
  verifyChallengeOtpHash,
  otpRedisKey,
} = require('../registration_otp');

let redis;
let smsCalls;
let smsStatus;
const originalRequest = https.request;

function stubMsg91() {
  https.request = (options, cb) => {
    const req = new EventEmitter();
    let body = '';
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = (d) => { body += d; };
    req.end = () => {
      let parsed = {};
      try { parsed = JSON.parse(body || '{}'); } catch (_) {}
      smsCalls.push({ host: options.hostname, path: options.path, body: parsed });
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = smsStatus;
        cb(res);
        res.emit('data', JSON.stringify(smsStatus === 200 ? { type: 'success', message: 'req-1' } : { type: 'error', message: 'fail' }));
        res.emit('end');
      });
    };
    return req;
  };
}

test.beforeEach(() => {
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
  smsCalls = [];
  smsStatus = 200;
  stubMsg91();
});

test.afterEach(() => {
  https.request = originalRequest;
});

const PHONE = '9876543210';
const challenge = async (role = 'patient') => JSON.parse((await redis.get(otpRedisKey(role, PHONE))) || 'null');

test('resend within the cooldown is blocked; exactly one SMS sent', async () => {
  const first = await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.1' });
  assert.equal(first.ok, true);
  assert.equal(first.expiresInSeconds, 300);
  await assert.rejects(
    () => sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.1' }),
    (err) => err.code === 'resource-exhausted' && /wait a minute/i.test(err.message),
  );
  assert.equal(smsCalls.length, 1);
});

test('after the cooldown a new code replaces the previous challenge', async () => {
  await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.2' });
  const before = await challenge();
  // Age the stored challenge past the 60s cooldown.
  const aged = { ...before, sentAt: Date.now() - 61_000 };
  for (const k of [otpRedisKey(null, PHONE), otpRedisKey('patient', PHONE)]) await redis.set(k, JSON.stringify(aged), 'EX', 300);
  await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.2' });
  const after = await challenge();
  assert.notEqual(after.otpHash, before.otpHash, 'a fresh code is issued');
  assert.equal(smsCalls.length, 2);
});

test('challenge key is env-prefixed and HMAC-derived, TTL <= 5 minutes', async () => {
  await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.3' });
  const key = otpRedisKey('patient', PHONE);
  assert.ok(key.startsWith('test:otp:challenge:'));
  assert.equal(key.includes(PHONE), false, 'raw number never appears in the key');
  const ttl = await redis.pttl(key);
  assert.ok(ttl > 0 && ttl <= 300_000);
  const stored = await challenge();
  assert.equal(stored.otpHash.length, 64);
  assert.equal(JSON.stringify(stored).includes(smsCalls[0].body.otp), false, 'plain OTP never stored');
});

test('an undelivered SMS removes the challenge (no cooldown lock-in)', async () => {
  smsStatus = 500;
  await assert.rejects(() => sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.4' }));
  assert.equal(await challenge(), null);
  smsStatus = 200;
  const retry = await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'registration' }, { clientIp: '203.0.113.4' });
  assert.equal(retry.ok, true, 'user can request again immediately');
});

test('login and forgot-password use their own DLT templates', async () => {
  setDatabaseClientForTesting(createMemoryPostgrest({ users: [{ id: 'u_login', role: 'patient', mobile: PHONE, profile_id: 'p1' }] }));
  try {
    await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'login' }, { clientIp: '203.0.113.5' });
    for (const k of [otpRedisKey(null, PHONE), otpRedisKey('patient', PHONE)]) await redis.del(k);
    await sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient', otpType: 'forgot_password' }, { clientIp: '203.0.113.6' });
    const templates = smsCalls.map((c) => c.body.template_id || new URLSearchParams(String(c.path).split('?')[1]).get('template_id'));
    assert.deepEqual(templates, ['tpl_login', 'tpl_reset']);
  } finally {
    setDatabaseClientForTesting(createMemoryPostgrest());
  }
});

test('hashOtp in production project fails closed without an HMAC secret and leaks nothing', async () => {
  const saved = { p: process.env.GCLOUD_PROJECT, k: process.env.MSG91_AUTH_KEY, a: process.env.AUTH_KEY, e: process.env.FUNCTIONS_EMULATOR, h: process.env.OTP_HMAC_SECRET };
  process.env.GCLOUD_PROJECT = 'medibond-45fad';
  delete process.env.MSG91_AUTH_KEY;
  delete process.env.AUTH_KEY;
  delete process.env.FUNCTIONS_EMULATOR;
  delete process.env.OTP_HMAC_SECRET;
  const logs = [];
  const origError = console.error;
  console.error = (...args) => { logs.push(args.join(' ')); };
  try {
    assert.throws(() => hashOtp('123456', { role: 'patient', digits: PHONE, purpose: 'create' }), (e) => e.code === 'internal');
    assert.throws(() => hashOtp('123456', { role: 'patient', digits: PHONE, purpose: 'verify' }), (e) => e.code === 'internal');
    await assert.rejects(() => sendUserRegistrationOtp(null, { mobile: PHONE, role: 'patient' }, { clientIp: '203.0.113.7' }));
    assert.equal(smsCalls.length, 0, 'no SMS without a hash secret');
    assert.ok(logs.some((l) => l.includes('otp_hash_secret_missing')));
    for (const l of logs) assert.equal(l.includes(saved.k || 'NOT_PRESENT'), false);
  } finally {
    console.error = origError;
    process.env.GCLOUD_PROJECT = saved.p;
    process.env.MSG91_AUTH_KEY = saved.k;
    if (saved.a !== undefined) process.env.AUTH_KEY = saved.a;
    if (saved.e !== undefined) process.env.FUNCTIONS_EMULATOR = saved.e;
    if (saved.h !== undefined) process.env.OTP_HMAC_SECRET = saved.h;
  }
});

test('legacy unsalted hash only verifies behind ALLOW_LEGACY_UNSALTED_OTP_HASH; OTP_HMAC_SECRET wins over MSG91 key', () => {
  const saved = { h: process.env.OTP_HMAC_SECRET, f: process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH };
  try {
    process.env.OTP_HMAC_SECRET = 'dedicated';
    const a = hashOtp('654321', { role: 'patient', digits: PHONE, purpose: 'create' });
    delete process.env.OTP_HMAC_SECRET;
    const b = hashOtp('654321', { role: 'patient', digits: PHONE, purpose: 'create' });
    assert.notEqual(a, b);
    delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
    assert.equal(verifyChallengeOtpHash('123456', legacyHashOtp('123456'), 'patient', PHONE), false);
    process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = 'true';
    assert.equal(verifyChallengeOtpHash('123456', legacyHashOtp('123456'), 'patient', PHONE), true);
  } finally {
    if (saved.h === undefined) delete process.env.OTP_HMAC_SECRET; else process.env.OTP_HMAC_SECRET = saved.h;
    if (saved.f === undefined) delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH; else process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH = saved.f;
  }
});

test('verify-path Redis read is bounded by the 1500ms timeout (fails closed)', async () => {
  setRedisClientForTesting({ get: () => new Promise(() => {}), del: async () => 1, set: async () => 'OK', on() { return this; } });
  const t0 = Date.now();
  await assert.rejects(
    () => consumeOtpChallengeAtomically(null, { otp: '654321', mobileDigits: PHONE, role: 'patient' }),
    (err) => err.code === 'unavailable',
  );
  assert.ok(Date.now() - t0 < 4000);
});
