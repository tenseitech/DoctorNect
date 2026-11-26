'use strict';

/**
 * completeAmbulanceMobileOtpLogin binds the caller's Firebase uid to the ambulance row only after a
 * valid, single-use Redis OTP session for the same mobile. Postgres-only (ambulances.auth_uid).
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { completeAmbulanceMobileOtpLogin, otpSessionRedisKey } = require('../registration_otp');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');
const { setDatabaseClientForTesting } = require('../src/db/client');
const { createMemoryPostgrest } = require('./helpers/memory_postgrest');

const validMobile = '9876543210';
const driverUid = 'driver-auth-uid-456';
const ambId = 'amb-reg-1001';

let redis;
let pg;

async function setup({ ambulance = {}, session = {}, noSession = false } = {}) {
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
  pg = createMemoryPostgrest({
    ambulances: [{
      ambulance_id: ambId,
      phone: '+919876543210',
      username: 'city_ambulance',
      service_name: 'City Ambulance Care',
      auth_uid: '',
      ...ambulance,
    }],
  });
  setDatabaseClientForTesting(pg);
  const sessionId = crypto.randomBytes(16).toString('hex');
  if (!noSession) {
    await redis.set(otpSessionRedisKey(sessionId), JSON.stringify({
      role: 'ambulance',
      mobileDigits: validMobile,
      mobileVerified: true,
      consumed: false,
      expiresAt: new Date(Date.now() + 300000).toISOString(),
      ...session,
    }), 'EX', 900);
  }
  return sessionId;
}

const ambRow = () => pg.rows('ambulances').find((r) => r.ambulance_id === ambId);
const ambWrites = () => pg.calls.filter((c) => c.table === 'ambulances' && c.mode !== 'select');
const call = (sessionId, auth = { uid: driverUid }, mobile = validMobile) =>
  completeAmbulanceMobileOtpLogin(null, { mobile, sessionId }, auth);

test.after(() => {
  setDatabaseClientForTesting(createMemoryPostgrest());
  setRedisClientForTesting(createMemoryRedis());
});

test('(a) valid session sets auth_uid on the ambulance row', async () => {
  const sid = await setup();
  const result = await call(sid);
  assert.equal(result.ok, true);
  assert.equal(result.driverId, ambId);
  assert.equal(ambRow().auth_uid, driverUid);
  assert.equal(ambWrites().length, 1);
  assert.equal(ambWrites()[0].payload.auth_uid, driverUid);
});

test('(b) same uid is a no-op: no write to the ambulance row', async () => {
  const sid = await setup({ ambulance: { auth_uid: driverUid } });
  const result = await call(sid);
  assert.equal(result.ok, true);
  assert.equal(ambWrites().length, 0);
});

test('(c) stale auth_uid is replaced by the new caller uid', async () => {
  const sid = await setup({ ambulance: { auth_uid: 'old-stale-device-uid' } });
  await call(sid);
  assert.equal(ambRow().auth_uid, driverUid);
  assert.equal(ambWrites().length, 1);
});

test('(d) missing / expired / wrong-role / wrong-mobile / replayed session writes nothing', async () => {
  const expectReject = async (sid, code, mobile) => {
    await assert.rejects(() => call(sid, undefined, mobile), (err) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, code);
      return true;
    });
    assert.equal(ambRow().auth_uid, '');
    assert.equal(ambWrites().length, 0);
  };
  await expectReject(await setup({ noSession: true }), 'failed-precondition');
  await expectReject(await setup({ session: { expiresAt: new Date(Date.now() - 60000).toISOString() } }), 'deadline-exceeded');
  await expectReject(await setup({ session: { role: 'patient' } }), 'failed-precondition');
  await expectReject(await setup({ session: { mobileDigits: '9111111111' } }), 'permission-denied');

  // Replay: a consumed session cannot bind a second device.
  const sid = await setup();
  await call(sid);
  await assert.rejects(() => call(sid, { uid: 'attacker-uid' }), (err) => err.code === 'failed-precondition');
  assert.equal(ambRow().auth_uid, driverUid);
});

test('(e) unauthenticated caller is rejected before any session is consumed', async () => {
  const sid = await setup();
  await assert.rejects(() => call(sid, null), (err) => err.code === 'unauthenticated');
  assert.equal(ambWrites().length, 0);
  assert.ok(await redis.get(otpSessionRedisKey(sid)), 'session left intact');
});

test('(f) row whose phone differs from the verified mobile is rejected (defense in depth)', async () => {
  const sid = await setup();
  // Simulate a lookup that returns a row with a different phone (e.g. data drift).
  const realFrom = pg.from.bind(pg);
  pg.from = (t) => {
    const b = realFrom(t);
    if (t !== 'ambulances') return b;
    const origIn = b.in.bind(b);
    b.in = () => origIn('ambulance_id', [ambId]);
    return b;
  };
  pg.rows('ambulances')[0].phone = '+919999999999';
  await assert.rejects(() => call(sid), (err) => err.code === 'permission-denied');
  assert.equal(ambWrites().length, 0);
});

test('(g) no ambulance registered for the number -> not-found, no write', async () => {
  const sid = await setup({ ambulance: { phone: '+919000000000' } });
  await assert.rejects(() => call(sid), (err) => err.code === 'not-found');
  assert.equal(ambWrites().length, 0);
});
