'use strict';

/**
 * Login failure counters (Redis, env-prefixed, TTL = login window).
 * clearFailedLogins is owner-only; the server-side trusted clear is separate.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  recordFailedLogin,
  recordLoginFailure,
  clearFailedLogins,
  resetLoginAttempts,
  clearFailedLoginsTrusted,
  assertLoginAllowed,
} = require('../registration_otp');
const { setRedisClientForTesting } = require('../redis');
const { createMemoryRedis } = require('./helpers/memory_redis');

let redis;
test.beforeEach(() => {
  redis = createMemoryRedis();
  setRedisClientForTesting(redis);
});

const failKeys = (kind) => [...redis.store.keys()].filter((k) => k.includes(`ratelimit:login_fail:login_${kind}_`));
const payload = { identifier: 'user@example.com' };
const options = { clientIp: '203.0.113.10' };
const owner = { uid: 'u1', token: { email: 'user@example.com', email_verified: true } };

test('recordFailedLogin and recordLoginFailure complete without recursion', async () => {
  await assert.doesNotReject(() => recordFailedLogin(null, payload, options));
  await assert.doesNotReject(() => recordLoginFailure(null, payload, options));
});

test('repeated failures increment identifier and IP counters with a TTL', async () => {
  await recordFailedLogin(null, payload, options);
  await recordFailedLogin(null, payload, options);
  await recordLoginFailure(null, payload, options);
  const [idKey] = failKeys('id');
  const [ipKey] = failKeys('ip');
  assert.ok(idKey && ipKey);
  assert.equal(Number(await redis.get(idKey)), 3);
  assert.equal(Number(await redis.get(ipKey)), 3);
  assert.ok((await redis.pttl(idKey)) > 0, 'counter must expire');
  assert.ok(idKey.startsWith('test:'), 'keys are env-namespaced');
});

test('5 failures for one identifier block further attempts', async () => {
  for (let i = 0; i < 5; i++) await recordFailedLogin(null, payload, { clientIp: `198.51.100.${i}` });
  await assert.rejects(() => assertLoginAllowed(null, payload, { clientIp: '198.51.100.99' }), (e) => e.code === 'resource-exhausted');
});

test('clearFailedLogins resets the counter only for the signed-in owner', async () => {
  await recordFailedLogin(null, payload, options);
  const [idKey] = failKeys('id');
  assert.equal(Number(await redis.get(idKey)), 1);

  // Unauthenticated / different account cannot reset someone else's lockout.
  await assert.rejects(() => clearFailedLogins(null, payload), (e) => e.code === 'permission-denied');
  await assert.rejects(
    () => clearFailedLogins(null, payload, { uid: 'u2', token: { email: 'attacker@example.com' } }),
    (e) => e.code === 'permission-denied',
  );
  assert.equal(Number(await redis.get(idKey)), 1);

  await clearFailedLogins(null, payload, owner);
  assert.equal(await redis.get(idKey), null);

  await recordFailedLogin(null, payload, options);
  await resetLoginAttempts(null, payload, owner);
  assert.equal(await redis.get(idKey), null);
});

test('clearFailedLoginsTrusted (server-side) clears after verified credentials', async () => {
  await recordFailedLogin(null, { identifier: 'ambulance:driver1' }, options);
  await clearFailedLoginsTrusted('ambulance:driver1');
  assert.equal(failKeys('id').length === 0 || (await redis.get(failKeys('id')[0])) === null, true);
});

test('Redis down -> login gate fails closed', async () => {
  setRedisClientForTesting({ get: async () => { throw new Error('down'); }, incr: async () => { throw new Error('down'); }, on() { return this; } });
  await assert.rejects(() => assertLoginAllowed(null, payload, options), (e) => e.code === 'unavailable');
});
