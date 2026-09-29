import * as fs from 'fs';
import * as path from 'path';
import * as net from 'net';
import Redis, { type RedisOptions } from 'ioredis';
import { defineSecret, type SecretParam } from 'firebase-functions/params';

// Firebase Functions v2 secret declarations
export const redisHostSecret: SecretParam = defineSecret('REDIS_HOST');
export const redisPortSecret: SecretParam = defineSecret('REDIS_PORT');
export const redisPasswordSecret: SecretParam = defineSecret('REDIS_PASSWORD');
export const REDIS_SECRETS: SecretParam[] = [redisHostSecret, redisPortSecret, redisPasswordSecret];

export function resolveSecretValue(secretParam: SecretParam, envKey: string, fallback = ''): string {
  if (secretParam && typeof (secretParam as any).value === 'function') {
    try {
      const val = (secretParam as any).value();
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

export function parseRedisEndpoint(rawHost: string, rawPort?: string | number): { host: string; port: number } {
  let host = String(rawHost || '127.0.0.1').trim();
  let port = rawPort ? parseInt(String(rawPort).trim(), 10) : 6379;

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

export function findRedisCaCertificatePath(): string | null {
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

export function readRedisCaCertificate(): Buffer | null {
  const certPath = findRedisCaCertificatePath();
  if (certPath) {
    return fs.readFileSync(certPath);
  }
  if (process.env.REDIS_CA_CERT) {
    return Buffer.from(process.env.REDIS_CA_CERT, 'utf8');
  }
  return null;
}

export function buildRedisOptions(overrides: Record<string, any> = {}): RedisOptions {
  const rawHost = overrides.host || resolveSecretValue(redisHostSecret, 'REDIS_HOST', '127.0.0.1');
  const rawPort = overrides.port || resolveSecretValue(redisPortSecret, 'REDIS_PORT', '6379');
  const { host, port } = parseRedisEndpoint(rawHost, rawPort);

  const password = overrides.password !== undefined
    ? overrides.password
    : resolveSecretValue(redisPasswordSecret, 'REDIS_PASSWORD', '');

  const useTls = overrides.tls !== undefined
    ? Boolean(overrides.tls)
    : String(process.env.REDIS_TLS || 'true').trim().toLowerCase() !== 'false';

  const options: RedisOptions = {
    host,
    port,
    lazyConnect: true,
    maxRetriesPerRequest: overrides.maxRetriesPerRequest !== undefined ? overrides.maxRetriesPerRequest : 3,
    enableReadyCheck: true,
    connectTimeout: 10000,
    retryStrategy(times) {
      if (times > 10) {
        return null;
      }
      return Math.min(times * 200, 2000);
    },
  };

  if (password) {
    options.password = password;
  }

  if (useTls) {
    const caCert = overrides.ca || readRedisCaCertificate();
    const tls: Record<string, any> = {
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

export function createRedisClient(customOptions: Record<string, any> = {}): Redis {
  const options = buildRedisOptions(customOptions);
  const client = new Redis(options);

  client.on('error', (err: any) => {
    if (process.env.NODE_ENV !== 'test') {
      console.error('[Redis Client Error]', err?.message || err);
    }
  });

  return client;
}

let _singletonClient: Redis | null = null;
let _testingClient: Redis | null = null;

export function setRedisClientForTesting(client: Redis | null): void {
  _testingClient = client;
}

export function getRedisClient(options: Record<string, any> = {}): Redis {
  if (_testingClient) {
    return _testingClient;
  }
  if (!_singletonClient || Object.keys(options).length > 0) {
    _singletonClient = createRedisClient(options);
  }
  return _singletonClient;
}

export async function closeRedis(): Promise<void> {
  if (_singletonClient) {
    try {
      await _singletonClient.quit();
    } catch (_) {
      _singletonClient.disconnect();
    }
    _singletonClient = null;
  }
}

export const redis: Redis = new Proxy(Object.create(Redis.prototype), {
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
}) as Redis;

export default redis;
