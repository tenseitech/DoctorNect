'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const {
  redis,
  getRedisClient,
  createRedisClient,
  buildRedisOptions,
  setRedisClientForTesting,
  closeRedis,
  findRedisCaCertificatePath,
  readRedisCaCertificate,
  parseRedisEndpoint,
  redisHostSecret,
  redisPortSecret,
  redisPasswordSecret,
  REDIS_SECRETS,
} = require('../src/config/redis');

test('Redis module exports required secrets, instances, and utilities', () => {
  assert.ok(redis, 'Expected redis client instance or proxy to be exported');
  assert.equal(typeof getRedisClient, 'function');
  assert.equal(typeof createRedisClient, 'function');
  assert.equal(typeof buildRedisOptions, 'function');
  assert.equal(typeof setRedisClientForTesting, 'function');
  assert.equal(typeof closeRedis, 'function');
  assert.equal(typeof findRedisCaCertificatePath, 'function');
  assert.equal(typeof readRedisCaCertificate, 'function');
  assert.equal(typeof parseRedisEndpoint, 'function');

  assert.ok(redisHostSecret, 'Expected redisHostSecret to be exported');
  assert.ok(redisPortSecret, 'Expected redisPortSecret to be exported');
  assert.ok(redisPasswordSecret, 'Expected redisPasswordSecret to be exported');
  assert.equal(REDIS_SECRETS.length, 3);
  assert.deepEqual(REDIS_SECRETS, [redisHostSecret, redisPortSecret, redisPasswordSecret]);
});

test('parseRedisEndpoint correctly handles standalone host, port, and combined host:port', () => {
  const normal = parseRedisEndpoint('127.0.0.1', 6379);
  assert.equal(normal.host, '127.0.0.1');
  assert.equal(normal.port, 6379);

  const combined = parseRedisEndpoint('effect-throne-satisfied-28321.db.redis.io:12875', '');
  assert.equal(combined.host, 'effect-throne-satisfied-28321.db.redis.io');
  assert.equal(combined.port, 12875);

  const combinedWithExplicitPort = parseRedisEndpoint('effect-throne-satisfied-28321.db.redis.io:12875', '12875');
  assert.equal(combinedWithExplicitPort.host, 'effect-throne-satisfied-28321.db.redis.io');
  assert.equal(combinedWithExplicitPort.port, 12875);

  const defaultFallback = parseRedisEndpoint('', null);
  assert.equal(defaultFallback.host, '127.0.0.1');
  assert.equal(defaultFallback.port, 6379);
});

test('findRedisCaCertificatePath and readRedisCaCertificate find valid CA certificate', () => {
  const certPath = findRedisCaCertificatePath();
  assert.ok(certPath, 'Expected CA certificate path to be found in project');
  assert.ok(fs.existsSync(certPath), `Certificate path ${certPath} should exist`);

  const certData = readRedisCaCertificate();
  assert.ok(Buffer.isBuffer(certData), 'Expected certificate content as Buffer');
  assert.ok(certData.length > 0, 'Certificate Buffer should not be empty');
  const certStr = certData.toString('utf8');
  assert.ok(certStr.includes('-----BEGIN CERTIFICATE-----'), 'Certificate must contain PEM header');
});

test('buildRedisOptions sets TLS configuration with CA cert and rejectUnauthorized', () => {
  const options = buildRedisOptions({
    host: 'memorystore.test.internal',
    port: 6379,
    password: 'test-secret-password',
    tls: true,
  });

  assert.equal(options.host, 'memorystore.test.internal');
  assert.equal(options.port, 6379);
  assert.equal(options.password, 'test-secret-password');
  assert.equal(options.lazyConnect, true);
  assert.equal(options.maxRetriesPerRequest, 1);
  assert.ok(options.tls, 'TLS options should be present');
  assert.equal(options.tls.rejectUnauthorized, true);
  assert.equal(options.tls.servername, 'memorystore.test.internal');
  assert.ok(Array.isArray(options.tls.ca), 'TLS ca should be an array');
});

test('setRedisClientForTesting intercepts redis commands for isolated unit tests', async () => {
  const mockCalls = [];
  const mockClient = {
    async get(key) {
      mockCalls.push({ method: 'get', key });
      return 'mock-value-123';
    },
    async set(key, value, ...rest) {
      mockCalls.push({ method: 'set', key, value, rest });
      return 'OK';
    },
    status: 'ready',
    on() {},
  };

  setRedisClientForTesting(mockClient);

  try {
    const activeClient = getRedisClient();
    assert.equal(activeClient, mockClient);

    const setResult = await redis.set('otp:test:mobile', '999999', 'EX', 60);
    assert.equal(setResult, 'OK');

    const getResult = await redis.get('otp:test:mobile');
    assert.equal(getResult, 'mock-value-123');

    assert.equal(mockCalls.length, 2);
    assert.equal(mockCalls[0].method, 'set');
    assert.equal(mockCalls[0].key, 'otp:test:mobile');
    assert.equal(mockCalls[1].method, 'get');
    assert.equal(mockCalls[1].key, 'otp:test:mobile');
  } finally {
    setRedisClientForTesting(null);
  }
});

test('functions/redis.js root export matches functions/src/config/redis.js', () => {
  const rootModule = require('../redis');
  assert.equal(rootModule.redis, redis);
  assert.equal(rootModule.getRedisClient, getRedisClient);
  assert.equal(rootModule.redisHostSecret, redisHostSecret);
});
