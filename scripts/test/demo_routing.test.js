'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveDataPlane,
  isDemoFirebaseUid,
  isDemoPhoneDigits,
  assertClientRoutingHintIgnored,
  redisKeyNamespace,
} = require('../lib/demo_routing');

const env0 = { ...process.env };

beforeEach(() => {
  process.env = { ...env0 };
  process.env.DEMO_REAL_ROUTING_ENABLED = '1';
  process.env.DEMO_FIREBASE_UID_ALLOWLIST = 'uid_demo_1,uid_demo_2';
  process.env.REVIEW_PATIENT_PHONES = '9999900001';
});

afterEach(() => {
  process.env = env0;
});

test('demo uid -> supabase plane in production only when routing enabled', () => {
  assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: 'uid_demo_1' }), 'supabase');
  assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: 'real_user_x' }), 'rds');
  assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: null }), 'rds');
  assert.equal(resolveDataPlane({ appEnv: 'staging', firebaseUid: 'uid_demo_1' }), 'staging');
});

test('routing off in production keeps RDS for demo uid', () => {
  process.env.DEMO_REAL_ROUTING_ENABLED = '0';
  assert.equal(resolveDataPlane({ appEnv: 'production', firebaseUid: 'uid_demo_1' }), 'rds');
});

test('client headers cannot influence routing', () => {
  const bad = assertClientRoutingHintIgnored({ 'x-demo': 'true', 'x-data-plane': 'supabase' });
  assert.equal(bad.ok, false);
  const ok = assertClientRoutingHintIgnored({ authorization: 'Bearer abc' });
  assert.equal(ok.ok, true);
});

test('reviewer phone allowlist only', () => {
  assert.equal(isDemoPhoneDigits('9999900001'), true);
  assert.equal(isDemoPhoneDigits('9000000000'), false);
});

test('redis namespace prefixes', () => {
  assert.equal(redisKeyNamespace({ appEnv: 'production', firebaseUid: 'uid_demo_1' }), 'demo:');
  assert.equal(redisKeyNamespace({ appEnv: 'production', firebaseUid: 'real_x' }), 'real:');
});

test('demo_user prefix uid is demo only when DEMO_UID_PREFIX_ROUTING=1', () => {
  delete process.env.DEMO_UID_PREFIX_ROUTING;
  assert.equal(isDemoFirebaseUid('demo_user_9999900002'), false);
  process.env.DEMO_UID_PREFIX_ROUTING = '1';
  assert.equal(isDemoFirebaseUid('demo_user_9999900002'), true);
  assert.equal(isDemoFirebaseUid('CTVzgkpdnjUs0uDDr5rWdVV3iWF2'), false);
});