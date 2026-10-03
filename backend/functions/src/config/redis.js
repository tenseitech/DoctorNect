'use strict';

/**
 * Google Cloud Memorystore (Redis) client initialization with TLS support.
 *
 * Configured for DRNECT-DB cluster with:
 * - Firebase Functions v2 defineSecret integration
 * - Server CA certificate TLS verification (redis_ca.pem / redis-ca.pem)
 * - Safe lazy connection and exponential backoff retry strategy
 * - Exported singleton instance (redis) and factory (getRedisClient)
 * - Testing hooks (setRedisClientForTesting)
 */

const fs = require('fs');
const path = require('path');
const net = require('net');
const Redis = require('ioredis');
const { defineSecret } = require('firebase-functions/params');

// Firebase Functions v2 secret declarations
const redisHostSecret = defineSecret('REDIS_HOST');
const redisPortSecret = defineSecret('REDIS_PORT');
const redisPasswordSecret = defineSecret('REDIS_PASSWORD');
const REDIS_SECRETS = [redisHostSecret, redisPortSecret, redisPasswordSecret];

/**
 * Safely resolves secret parameter value with fallback to process.env.
 * Handles Cloud Functions runtime, local emulator, and testing environments.
 *
 * @param {import('firebase-functions/params').SecretParam} secretParam
 * @param {string} envKey
 * @param {string} [fallback='']
 * @returns {string}
 */
function resolveSecretValue(secretParam, envKey, fallback = '') {
  if (secretParam && typeof secretParam.value === 'function') {
    try {
      const val = secretParam.value();
      if (val !== undefined && val !== null && String(val).trim().length > 0) {
        return String(val).trim();
      }
    } catch (_) {
      // Ignored: Not in Cloud Functions execution context with bound secrets
    }
  }
  const envVal = process.env[envKey];
  if (envVal !== undefined && envVal !== null && String(envVal).trim().length > 0) {
    return String(envVal).trim();
  }
  return fallback;
}

/**
 * Normalizes host and port, handling "hostname:port" formats in REDIS_HOST.
 *
 * @param {string} rawHost
 * @param {string|number} [rawPort]
 * @returns {{ host: string, port: number }}
 */
function parseRedisEndpoint(rawHost, rawPort) {
  let host = String(rawHost || '127.0.0.1').trim();
  let port = rawPort ? parseInt(String(rawPort).trim(), 10) : 6379;

  // Handle "hostname:port" passed inside REDIS_HOST (e.g. effect-throne...redis.io:12875)
  if (host.includes(':') && !host.startsWith('[') && !net.isIPv6(host)) {
    const parts = host.split(':');
    host = parts[0].trim();
    const parsedPort = parseInt(parts[1].trim(), 10);
    if (!isNaN(parsedPort) && (!rawPort || isNaN(port))) {
      port = parsedPort;
    }
  }

  if (isNaN(port) || port <= 0) {
    port = 6379;
  }

  return { host, port };
}

/**
 * Resolves the path to the Redis CA certificate file.
 * Checks REDIS_CA_PATH, current directory, functions directory, and parent folders.
 *
 * @returns {string|null}
 */
function findRedisCaCertificatePath() {
  if (process.env.REDIS_CA_PATH) {
    const customPath = path.resolve(process.env.REDIS_CA_PATH);
    if (fs.existsSync(customPath)) {
      return customPath;
    }
  }

  const candidates = [
    path.join(__dirname, 'redis_ca.pem'),
    path.join(__dirname, 'redis-ca.pem'),
    path.join(__dirname, '..', 'redis_ca.pem'),
    path.join(__dirname, '..', 'redis-ca.pem'),
    path.join(__dirname, '..', '..', 'redis_ca.pem'),
    path.join(__dirname, '..', '..', 'redis-ca.pem'),
    path.join(process.cwd(), 'redis_ca.pem'),
    path.join(process.cwd(), 'redis-ca.pem'),
    path.join(process.cwd(), 'functions', 'redis_ca.pem'),
    path.join(process.cwd(), 'functions', 'redis-ca.pem'),
  ];

  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return p;
    }
  }
  return null;
}

/**
 * Reads the Redis CA certificate as a Buffer or string.
 *
 * @returns {Buffer|null}
 */
function readRedisCaCertificate() {
  const certPath = findRedisCaCertificatePath();
  if (certPath) {
    return fs.readFileSync(certPath);
  }
  if (process.env.REDIS_CA_CERT) {
    return Buffer.from(process.env.REDIS_CA_CERT, 'utf8');
  }
  return null;
}

/**
 * Constructs the ioredis configuration options object with TLS and retry settings.
 *
 * @param {Record<string, any>} [overrides={}]
 * @returns {import('ioredis').RedisOptions}
 */
function buildRedisOptions(overrides = {}) {
  const rawHost = overrides.host || resolveSecretValue(redisHostSecret, 'REDIS_HOST', '127.0.0.1');
  const rawPort = overrides.port || resolveSecretValue(redisPortSecret, 'REDIS_PORT', '6379');
  const { host, port } = parseRedisEndpoint(rawHost, rawPort);

  const password = overrides.password !== undefined
    ? overrides.password
    : resolveSecretValue(redisPasswordSecret, 'REDIS_PASSWORD', '');

  const useTls = overrides.tls !== undefined
    ? Boolean(overrides.tls)
    : String(process.env.REDIS_TLS || 'true').trim().toLowerCase() !== 'false';

  const options = {
    host,
    port,
    lazyConnect: true,
    maxRetriesPerRequest: overrides.maxRetriesPerRequest !== undefined ? overrides.maxRetriesPerRequest : 3,
    enableReadyCheck: true,
    connectTimeout: 10000,
    retryStrategy(times) {
      if (times > 10) {
        return null; // Stop reconnecting after 10 failed attempts
      }
      return Math.min(times * 200, 2000);
    },
  };

  if (password) {
    options.password = password;
  }

  if (useTls) {
    const caCert = overrides.ca || readRedisCaCertificate();
    const tls = {
      rejectUnauthorized: true,
    };
    if (caCert) {
      tls.ca = [caCert];
    }
    if (!net.isIP(host)) {
      tls.servername = host;
    }
    if (typeof overrides.tls === 'object' && overrides.tls !== null) {
      Object.assign(tls, overrides.tls);
    }
    options.tls = tls;
  }

  const extraOverrides = { ...overrides };
  delete extraOverrides.host;
  delete extraOverrides.port;
  delete extraOverrides.password;
  delete extraOverrides.tls;
  delete extraOverrides.ca;

  return Object.assign(options, extraOverrides);
}

/**
 * Creates and returns a new ioredis instance with preconfigured error event handling.
 *
 * @param {Record<string, any>} [customOptions={}]
 * @returns {import('ioredis').Redis}
 */
function createRedisClient(customOptions = {}) {
  const options = buildRedisOptions(customOptions);
  const client = new Redis(options);

  // Prevent uncaught EventEmitter 'error' from crashing the process
  client.on('error', (err) => {
    if (process.env.NODE_ENV !== 'test') {
      console.error('[Redis Client Error]', err?.message || err);
    }
  });

  return client;
}

let _singletonClient = null;
let _testingClient = null;

/**
 * Inject a mock Redis client for automated unit tests.
 *
 * @param {import('ioredis').Redis|null} client
 */
function setRedisClientForTesting(client) {
  _testingClient = client;
}

/**
 * Retrieves or lazily creates the singleton Redis client instance.
 *
 * @param {Record<string, any>} [options={}]
 * @returns {import('ioredis').Redis}
 */
function getRedisClient(options = {}) {
  if (_testingClient) {
    return _testingClient;
  }
  if (!_singletonClient || Object.keys(options).length > 0) {
    _singletonClient = createRedisClient(options);
  }
  return _singletonClient;
}

/**
 * Gracefully closes the active singleton Redis client connection.
 *
 * @returns {Promise<void>}
 */
async function closeRedis() {
  if (_singletonClient) {
    try {
      await _singletonClient.quit();
    } catch (_) {
      _singletonClient.disconnect();
    }
    _singletonClient = null;
  }
}

/**
 * Exported proxy client allowing direct import:
 * `const { redis } = require('./config/redis');`
 * `await redis.get('key');`
 *
 * Lazily binds to the singleton client without forcing immediate connection on import.
 */
const redis = new Proxy(Object.create(Redis.prototype), {
  get(_, prop) {
    const client = getRedisClient();
    const val = Reflect.get(client, prop, client);
    return typeof val === 'function' ? val.bind(client) : val;
  },
  set(_, prop, value) {
    const client = getRedisClient();
    return Reflect.set(client, prop, value, client);
  },
  has(_, prop) {
    const client = getRedisClient();
    return Reflect.has(client, prop);
  },
});

module.exports = {
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
};
