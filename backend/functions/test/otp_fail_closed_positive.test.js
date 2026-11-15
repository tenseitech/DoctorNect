'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('https');
const { EventEmitter } = require('events');

const { sendUserRegistrationOtp, enforceSendOtpRateLimits } = require('../registration_otp');
const {
  enableOtpRedisTestEnv,
  disableOtpRedisTestEnv,
  EMPTY_LEGACY_DB,
} = require('./helpers/otp_test_redis');

function stubSms() {
  const original = https.request;
  https.request = (options, callback) => {
    const req = new EventEmitter();
    req.setTimeout = () => {};
    req.destroy = () => {};
    req.write = () => {};
    req.end = () => {
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
  return () => {
    https.request = original;
  };
}

test('OTP send succeeds when Redis is healthy (not fail-closed for normal users)', async () => {
  enableOtpRedisTestEnv();
  process.env.MSG91_TEMPLATE_ID_REGISTRATION = 'unit-test-template';
  process.env.MSG91_TEMPLATE_ID = 'unit-test-template';
  process.env.MSG91_SENDER_ID = 'DRNECT';
  const restoreSms = stubSms();
  try {
    const mobile = '9876501234';
    const role = 'patient';
    await enforceSendOtpRateLimits(EMPTY_LEGACY_DB, { clientIp: '10.1.2.3', role, digits: mobile });
    const res = await sendUserRegistrationOtp(EMPTY_LEGACY_DB, {
      mobile,
      role,
      otpType: 'registration',
    }, { clientIp: '10.1.2.3' });
    assert.equal(res.ok, true);
  } finally {
    restoreSms();
    disableOtpRedisTestEnv();
  }
});