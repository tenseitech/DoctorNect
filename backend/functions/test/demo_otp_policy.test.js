'use strict';

/**
 * Demo / reviewer OTP policy (lib/demo_accounts.js + reviewer_otp_config.js) and the unified
 * phone step (otpType 'auth') through the real send/verify code paths.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('https');
const { EventEmitter } = require('events');
const { initializeApp, getApps } = require('firebase-admin/app');
if (!getApps().length) initializeApp({ projectId: 'demo-otp-policy-test' });
const { getAuth } = require('firebase-admin/auth');

delete process.env.ALLOW_LEGACY_UNSALTED_OTP_HASH;
delete process.env.OTP_TEST_MODE;
process.env.MSG91_AUTH_KEY = 'unit-test-hmac-key';
process.env.MSG91_TEMPLATE_ID = 'unit-test-template';
process.env.MSG91_TEMPLATE_ID_LOGIN = 'unit-test-template';
process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'unit-test-template';

const {
  DEMO_ACCOUNTS,
  canonicalMobileDigits,
  demoAccountByMobile,
  containsDemoMobile,
} = require('../lib/demo_accounts');
const { demoOtpPolicy, isReviewerPhone } = require('../reviewer_otp_config');
const otp = require('../registration_otp');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');
const { setDatabaseClientForTesting } = require('../src/db/client');
const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
const { resolveLoginLookupPlane } = require('../src/db/login_lookup');

const FUTURE = '2099-01-01T00:00:00Z';
const ENV_KEYS = ['REVIEWER_OTP_ENABLED', 'REVIEW_FIXED_OTP', 'REVIEW_ACCESS_UNTIL', 'APP_ENV',
  'DEMO_PHONE_NUMBERS', 'DEMO_FIXED_OTP', 'REVIEW_PATIENT_PHONES', 'REVIEW_TEST_NUMBERS'];
let savedEnv;
let sms;
let restoreHttps;
let redis;
let db;
let auth;
let restoreAuth;

function enableDemo(fixed = '000000') {
  process.env.REVIEWER_OTP_ENABLED = 'true';
  process.env.REVIEW_FIXED_OTP = fixed;
  process.env.REVIEW_ACCESS_UNTIL = FUTURE;
}

function stubSms() {
  const original = https.request;
  https.request = (options, callback) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = () => {};
    req.end = () => {
      const q = String(options.path || '').split('?')[1] || '';
      const params = new URLSearchParams(q);
      sms.push({ mobile: params.get('mobile'), code: params.get('otp') });
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = 200;
        callback(res);
        res.emit('data', JSON.stringify({ type: 'success' }));
        res.emit('end');
      });
    };
    return req;
  };
  return () => { https.request = original; };
}

const demoUsers = DEMO_ACCOUNTS.map((a) => ({ id: a.uid, firebase_uid: a.uid, role: a.role, mobile: `+91${a.digits}`, profile_id: a.profileId }));

test.beforeEach(() => {
  savedEnv = Object.fromEntries(ENV_KEYS.map((k) => [k, process.env[k]]));
  for (const k of ENV_KEYS) delete process.env[k];
  sms = [];
  restoreHttps = stubSms();
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
  otp.setReviewerRedisClientForTesting(createMemoryRedis());
  db = createMemoryPostgrest({
    users: [...demoUsers, { id: 'real_uid_1', firebase_uid: 'real_uid_1', role: 'lab', mobile: '9876500001', profile_id: 'lab_9' }],
  });
  setDatabaseClientForTesting(db);
  auth = getAuth();
  const orig = { c: auth.createCustomToken, s: auth.setCustomUserClaims };
  auth.createCustomToken = async (uid) => `token-for-${uid}`;
  auth.setCustomUserClaims = async () => {};
  restoreAuth = () => { auth.createCustomToken = orig.c; auth.setCustomUserClaims = orig.s; };
});

test.afterEach(() => {
  restoreHttps();
  restoreAuth();
  setDatabaseClientForTesting(createMemoryPostgrest());
  setRedisClientForTesting(createMemoryRedis());
  otp.setReviewerRedisClientForTesting(null);
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
});

const send = (mobile, extra = {}) => otp.sendUserRegistrationOtp(null, { mobile, otpType: 'auth', ...extra }, { clientIp: '10.0.0.1' });
const verify = (mobile, code, extra = {}) => otp.verifyUserRegistrationOtp(null, { mobile, otp: code, otpType: 'auth', ...extra }, null, { clientIp: '10.0.0.1' });

test('allowlist: exactly five numbers, one per role, in the agreed order', () => {
  assert.deepEqual(DEMO_ACCOUNTS.map((a) => [a.digits, a.role]), [
    ['9999900001', 'doctor'], ['9999900002', 'patient'], ['9999900003', 'medicalStore'],
    ['9999900004', 'lab'], ['9999900005', 'ambulance'],
  ]);
  assert.equal(new Set(DEMO_ACCOUNTS.map((a) => a.role)).size, 5);
});

test('canonical mobile: same number in different spellings, look-alikes rejected', () => {
  for (const ok of ['9999900001', '+919999900001', '919999900001', '+91 99999 00001', ' 99999-00001 ']) {
    assert.equal(canonicalMobileDigits(ok), '9999900001', ok);
    assert.equal(demoAccountByMobile(ok).role, 'doctor', ok);
  }
  for (const bad of ['09999900001', '009999900001', '199999900001', '99999000010', '999990000',
    '9999900001x', '+19999900001', '+9109999900001', '９９９９９００００１', null, undefined, {}, ['9999900001']]) {
    assert.equal(demoAccountByMobile(bad), null, String(bad));
  }
  assert.equal(demoAccountByMobile('9999900006'), null);
  assert.equal(containsDemoMobile('call +91 99999 00004 now'), true);
  assert.equal(containsDemoMobile('9876543210'), false);
});

test('policy: enabled flag, 6-digit secret and future expiry are all required', () => {
  assert.equal(demoOtpPolicy().reason, 'disabled');
  process.env.REVIEWER_OTP_ENABLED = 'true';
  assert.equal(demoOtpPolicy().reason, 'missing_fixed_otp');
  process.env.REVIEW_FIXED_OTP = '00000';
  assert.equal(demoOtpPolicy().reason, 'invalid_fixed_otp');
  process.env.REVIEW_FIXED_OTP = '000000';
  assert.equal(demoOtpPolicy().reason, 'missing_access_until');
  process.env.REVIEW_ACCESS_UNTIL = 'soon';
  assert.equal(demoOtpPolicy().reason, 'invalid_access_until');
  process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z';
  assert.equal(demoOtpPolicy().reason, 'expired');
  process.env.REVIEW_ACCESS_UNTIL = FUTURE;
  assert.equal(demoOtpPolicy().active, true);
});

test('env lists (REVIEW_*_PHONES, REVIEW_TEST_NUMBERS, DEMO_PHONE_NUMBERS) cannot add bypass numbers', () => {
  enableDemo();
  process.env.REVIEW_PATIENT_PHONES = '9876543210';
  process.env.REVIEW_TEST_NUMBERS = '9876543210';
  process.env.DEMO_PHONE_NUMBERS = '9876543210';
  process.env.DEMO_FIXED_OTP = '000000';
  assert.equal(isReviewerPhone('9876543210', 'patient'), false);
  assert.equal(otp.shouldSkipMsg91ForPhone('9876543210', 'patient'), false);
  assert.equal(otp.isStagingDemoPhone('9876543210'), false);
});

test('demo send: no SMS, fixed code from the secret, role taken from the allowlist', async () => {
  enableDemo('000000');
  const res = await send('9999900001', { role: 'patient' });
  assert.deepEqual(res, { ok: true, expiresInSeconds: res.expiresInSeconds });
  assert.equal(sms.length, 0, 'no SMS for demo numbers');
  const challenge = JSON.parse(await redis.get(otp.otpRedisKey('doctor', '9999900001')));
  assert.equal(challenge.role, 'doctor', 'client role "patient" ignored');
  assert.equal(challenge.otpHash, otp.hashOtp('000000', { role: 'doctor', digits: '9999900001', purpose: 'create' }));
});

test('000000 never works for a real number, even while the demo policy is active', async () => {
  enableDemo('000000');
  await send('9876500002');
  assert.equal(sms.length, 1, 'real number gets a real SMS');
  assert.notEqual(sms[0].code, '000000');
  await assert.rejects(verify('9876500002', '000000'), { code: 'permission-denied' });
  const ok = await verify('9876500002', sms[0].code);
  assert.equal(ok.exists, false);
});

test('look-alike numbers never get the bypass (rejected as invalid before any OTP)', async () => {
  enableDemo('000000');
  for (const m of ['09999900001', '199999900001', '99999000010']) {
    await assert.rejects(send(m), { code: 'invalid-argument' }, m);
    await assert.rejects(verify(m, '000000'), { code: 'invalid-argument' }, m);
  }
  assert.equal(sms.length, 0);
});

test('pre-verification responses are identical for existing, unknown and demo numbers', async () => {
  enableDemo('000000');
  const existing = await send('9876500001');
  const unknown = await send('9876500003');
  const demo = await send('9999900004');
  assert.deepEqual(existing, unknown);
  assert.deepEqual(existing, demo);
  for (const t of ['login', 'registration']) {
    assert.deepEqual(await send(`98765111${t === 'login' ? '01' : '02'}`, { otpType: t }), existing);
  }
  assert.equal(db.calls.filter((c) => c.table === 'users').length, 0, 'no account lookup before OTP verification');
});

test('demo policy off: no SMS and no OTP for demo numbers', async () => {
  await assert.rejects(send('9999900002'), { code: 'failed-precondition' });
  process.env.REVIEWER_OTP_ENABLED = 'true';
  process.env.REVIEW_FIXED_OTP = '000000';
  process.env.REVIEW_ACCESS_UNTIL = '2020-01-01T00:00:00Z';
  await assert.rejects(send('9999900002'), { code: 'failed-precondition' });
  assert.equal(sms.length, 0);
});

test('all five demo numbers sign in through the unified step with their allowlisted role and UID', async () => {
  enableDemo('000000');
  for (const a of DEMO_ACCOUNTS) {
    await send(a.digits, { role: 'patient' });
    const res = await verify(a.digits, '000000', { role: 'patient' });
    assert.equal(res.exists, true, a.digits);
    assert.equal(res.role, a.role, a.digits);
    assert.equal(res.uid, a.uid, a.digits);
    assert.equal(res.customToken, `token-for-${a.uid}`);
  }
  assert.equal(sms.length, 0);
});

test('demo numbers never register: send/verify registration refused, missing demo account fails closed', async () => {
  enableDemo('000000');
  await assert.rejects(send('9999900002', { otpType: 'registration' }), { code: 'permission-denied' });
  await assert.rejects(verify('9999900002', '000000', { otpType: 'registration' }), { code: 'permission-denied' });
  setDatabaseClientForTesting(createMemoryPostgrest({ users: [] }));
  await send('9999900003');
  await assert.rejects(verify('9999900003', '000000'), { code: 'failed-precondition' });
});

test('demo row that does not match the allowlist (wrong role/uid) is refused', async () => {
  enableDemo('000000');
  setDatabaseClientForTesting(createMemoryPostgrest({
    users: [{ id: 'someone_else', role: 'patient', mobile: '9999900001', profile_id: 'x' }],
  }));
  await send('9999900001');
  await assert.rejects(verify('9999900001', '000000'), { code: 'failed-precondition' });
});

test('per-number lockout: 5 failures lock the demo number, even the right code is refused', async () => {
  enableDemo('000000');
  for (let i = 0; i < 5; i++) await otp.recordDemoOtpFailure('9999900005');
  await assert.rejects(otp.assertDemoNotLockedOut('9999900005'), { code: 'resource-exhausted' });
  await send('9999900005');
  await assert.rejects(verify('9999900005', '000000'), { code: 'resource-exhausted' });
  await otp.assertDemoNotLockedOut('9999900004');
});

test('wrong demo code counts towards the lockout', async () => {
  enableDemo('000000');
  await send('9999900004');
  await assert.rejects(verify('9999900004', '123456'), { code: 'permission-denied' });
  const failKey = [...redis.store.keys()].find((k) => k.includes('demo_otp_fail'));
  assert.ok(failKey, 'failure counter stored');
  assert.equal(await redis.get(failKey), '1');
  for (let i = 0; i < 4; i++) await otp.recordDemoOtpFailure('9999900004');
  await assert.rejects(otp.assertDemoNotLockedOut('9999900004'), { code: 'resource-exhausted' });
});

test('unified step: unknown real number gets a role-less registration session, existing one logs in', async () => {
  await send('9876500003');
  const created = await verify('9876500003', sms[0].code);
  assert.equal(created.exists, false);
  assert.ok(created.sessionId);
  const stored = JSON.parse(await redis.get(otp.otpSessionRedisKey(created.sessionId)));
  assert.equal(stored.role, 'auth');

  await send('9876500001');
  const login = await verify('9876500001', sms[1].code, { role: 'patient' });
  assert.equal(login.exists, true);
  assert.equal(login.role, 'lab', 'role comes from the account, not the client');
  assert.equal(login.customToken, 'token-for-real_uid_1');
});

test('lookup plane is decided by the allowlist only (production)', () => {
  process.env.APP_ENV = 'production';
  for (const a of DEMO_ACCOUNTS) {
    assert.equal(resolveLoginLookupPlane(a.digits, 'patient'), 'supabase');
    assert.equal(resolveLoginLookupPlane(a.digits, null), 'supabase', 'even with the OTP bypass off');
  }
  assert.equal(resolveLoginLookupPlane('9876543210', 'doctor'), 'rds');
  assert.equal(resolveLoginLookupPlane('09999900001', 'doctor'), 'rds');
});
