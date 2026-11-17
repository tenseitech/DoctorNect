'use strict';

/**
 * Real Redis integration (docker: redis:7, host port 6390).
 * Skipped unless REDIS_INTEGRATION_URL is set or default localhost:6390 accepts PING.
 *
 *   docker run -d --name doctornect-otp-redis -p 6390:6379 redis:7
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const https = require('https');
const { EventEmitter } = require('events');

const INTEGRATION_URL = (process.env.REDIS_INTEGRATION_URL || 'redis://127.0.0.1:6390').trim();

let integrationRedisAvailable = false;

async function pingRedis(url) {
  try {
    const net = require('net');
    const parsed = new URL(url.replace(/^redis:\/\//, 'http://'));
    const host = parsed.hostname || '127.0.0.1';
    const port = Number(parsed.port || 6379);
    return await new Promise((resolve) => {
      const socket = net.connect({ host, port });
      const done = (ok) => {
        socket.destroy();
        resolve(ok);
      };
      socket.setTimeout(2000, () => done(false));
      socket.once('connect', () => done(true));
      socket.once('error', () => done(false));
    });
  } catch (_) {
    return false;
  }
}

test.before(async () => {
  integrationRedisAvailable =
    process.env.FORCE_REDIS_INTEGRATION === '1' || (await pingRedis(INTEGRATION_URL));
});

function integrationDescribe(name, fn) {
  test(name, { skip: integrationRedisAvailable ? false : 'Redis integration unavailable (set REDIS_INTEGRATION_URL or start redis:7 on :6390)' }, fn);
}

integrationDescribe('OTP send → verify → cooldown → expiry → lockout (real Redis)', async (t) => {
  const Redis = require('ioredis');
  const client = new Redis(INTEGRATION_URL, { maxRetriesPerRequest: 2 });
  const { setRedisClientForTesting } = require('../redis');
  const {
    sendUserRegistrationOtp,
    consumeOtpChallengeAtomically,
    otpRedisKey,
    otpAttemptsRedisKey,
    hashOtp,
  } = require('../registration_otp');

  const OTP_EXPIRY_MS = 10 * 60 * 1000;
  const RESEND_COOLDOWN_MS = 60 * 1000;
  const OTP_MAX_VERIFY_ATTEMPTS = 5;

  const phone = `9${String(Date.now()).slice(-9)}`;
  const role = 'patient';
  const testId = crypto.randomBytes(4).toString('hex');
  const prevMirror = process.env.OTP_REDIS_MIRROR;
  const prevAuth = process.env.MSG91_AUTH_KEY;
  const prevTpl = process.env.MSG91_TEMPLATE_ID_REGISTRATION;

  process.env.OTP_REDIS_MIRROR = 'on';
  process.env.MSG91_AUTH_KEY = `integration_${testId}`;
  process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'integration_tpl';

  let capturedOtp = null;
  const origHttpsRequest = https.request;
  https.request = (options, cb) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.write = (body) => {
      try {
        const parsed = JSON.parse(String(body));
        const otp = parsed?.OTP || parsed?.otp;
        if (otp) capturedOtp = String(otp);
      } catch (_) {}
    };
    req.end = () => {
      process.nextTick(() => {
        const res = new EventEmitter();
        res.statusCode = 200;
        if (cb) cb(res);
        res.emit('data', JSON.stringify({ message: 'ok', type: 'success' }));
        res.emit('end');
      });
    };
    return req;
  };

  setRedisClientForTesting(client);

  t.after(async () => {
    https.request = origHttpsRequest;
    if (prevMirror === undefined) delete process.env.OTP_REDIS_MIRROR;
    else process.env.OTP_REDIS_MIRROR = prevMirror;
    if (prevAuth === undefined) delete process.env.MSG91_AUTH_KEY;
    else process.env.MSG91_AUTH_KEY = prevAuth;
    if (prevTpl === undefined) delete process.env.MSG91_TEMPLATE_ID_REGISTRATION;
    else process.env.MSG91_TEMPLATE_ID_REGISTRATION = prevTpl;
    setRedisClientForTesting(null);
    const keys = await client.keys(`otp:*${phone}*`);
    const rlKeys = await client.keys(`ratelimit:otp:*`);
    const all = [...new Set([...keys, ...rlKeys.filter((k) => k.includes(phone.slice(-6)))])];
    if (all.length) await client.del(...all);
    try {
      await client.quit();
    } catch (_) {
      client.disconnect();
    }
  });

  const sendOk = await sendUserRegistrationOtp({}, {
    mobile: phone,
    role,
    otpType: 'registration',
  }, { clientIp: `127.0.0.${testId.charCodeAt(0) % 200 + 1}` });
  assert.equal(sendOk.ok, true);
  assert.ok(capturedOtp, 'MSG91 stub must capture OTP code');

  await assert.rejects(
    () => sendUserRegistrationOtp({}, {
      mobile: phone,
      role,
      otpType: 'registration',
    }, { clientIp: `127.0.0.${testId.charCodeAt(0) % 200 + 1}` }),
    (err) => err.code === 'resource-exhausted',
    'immediate resend must hit cooldown',
  );

  const verifyOk = await consumeOtpChallengeAtomically({}, {
    challengeKey: 'integration',
    otp: capturedOtp,
    mobileDigits: phone,
    role,
    isDemoAccount: false,
  });
  assert.equal(verifyOk.consumed, true);

  await assert.rejects(
    () => consumeOtpChallengeAtomically({}, {
      challengeKey: 'integration-2',
      otp: '000000',
      mobileDigits: phone,
      role,
      isDemoAccount: false,
    }),
    (err) => err.code === 'not-found' || err.code === 'failed-precondition',
    'consumed challenge must not verify again',
  );

  await client.set(
    otpRedisKey(role, phone),
    JSON.stringify({
      role,
      mobileDigits: phone,
      otpHash: hashOtp('445566', { role, digits: phone, purpose: 'create' }),
      sentAt: Date.now(),
      expiresAt: Date.now() - 1000,
      attempts: 0,
    }),
    'EX',
    60,
  );

  await assert.rejects(
    () => consumeOtpChallengeAtomically({}, {
      challengeKey: 'expired',
      otp: '445566',
      mobileDigits: phone,
      role,
      isDemoAccount: false,
    }),
    (err) => err.code === 'deadline-exceeded' || err.code === 'failed-precondition',
    'expired challenge must reject verify',
  );

  const lockPhone = `8${String(Date.now()).slice(-9)}`;
  const lockHash = hashOtp('778899', { role, digits: lockPhone, purpose: 'create' });
  const lockAttemptsKey = otpAttemptsRedisKey(lockPhone);
  await client.set(lockAttemptsKey, String(OTP_MAX_VERIFY_ATTEMPTS), 'EX', 900);
  await client.set(
    otpRedisKey(role, lockPhone),
    JSON.stringify({
      role,
      mobileDigits: lockPhone,
      otpHash: lockHash,
      sentAt: Date.now(),
      expiresAt: Date.now() + OTP_EXPIRY_MS,
    }),
    'EX',
    Math.ceil(OTP_EXPIRY_MS / 1000),
  );

  await assert.rejects(
    () => consumeOtpChallengeAtomically({}, {
      challengeKey: 'lockout',
      otp: '778899',
      mobileDigits: lockPhone,
      role,
      isDemoAccount: false,
    }),
    (err) => err.code === 'resource-exhausted',
    'max attempts must lock verification (counter on otp:attempts key, not challenge JSON)',
  );

  const racePhone = `7${String(Date.now()).slice(-9)}`;
  capturedOtp = null;
  await sendUserRegistrationOtp({}, {
    mobile: racePhone,
    role,
    otpType: 'registration',
  }, { clientIp: `127.0.0.${testId.charCodeAt(1) % 200 + 1}` });
  assert.ok(capturedOtp, 'race fixture must capture OTP');

  const parallelGuesses = 20;
  const outcomes = await Promise.allSettled(
    Array.from({ length: parallelGuesses }, (_, i) =>
      consumeOtpChallengeAtomically({}, {
        challengeKey: `race-${i}`,
        otp: String(100000 + i).padStart(6, '0').slice(-6),
        mobileDigits: racePhone,
        role,
        isDemoAccount: false,
      }),
    ),
  );

  const exhausted = outcomes.filter(
    (o) => o.status === 'rejected' && o.reason?.code === 'resource-exhausted',
  ).length;
  const invalid = outcomes.filter(
    (o) => o.status === 'rejected' && o.reason?.code === 'invalid-argument',
  ).length;
  const consumed = outcomes.filter(
    (o) => o.status === 'fulfilled' && o.value?.consumed === true,
  ).length;
  assert.equal(consumed, 0, 'parallel wrong guesses must not consume challenge');
  assert.ok(exhausted >= 1, 'at least one parallel batch must hit lockout');
  assert.equal(exhausted + invalid, parallelGuesses, 'each parallel guess must fail as invalid or exhausted');

  const attemptCount = Number(await client.get(otpAttemptsRedisKey(racePhone)) || '0');
  assert.ok(
    attemptCount <= OTP_MAX_VERIFY_ATTEMPTS,
    `attempt counter must never exceed ${OTP_MAX_VERIFY_ATTEMPTS} (got ${attemptCount})`,
  );

  assert.ok(RESEND_COOLDOWN_MS > 0, 'cooldown constant defined');
});