'use strict';

/**
 * Multi-gateway-instance rate limiting with ephemeral local Redis (SEC-08 integration).
 */
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const { createGatewayServer } = require('../src/server');
const { JwksClient } = require('../src/jwks');
const { base64UrlEncode } = require('../src/jwt_minter');
const {
  startRedisIntegrationServer,
  stopRedisIntegrationServer,
} = require('./helpers/redis_integration_server');

const autoRedis = String(process.env.REDIS_INTEGRATION_AUTO || '1').trim() !== '0';

describe('Gateway Redis multi-instance (SEC-08 integration)', { skip: !autoRedis ? 'REDIS_INTEGRATION_AUTO=0' : false }, () => {
  let redisUrl;
  let mockPostgrestServer;
  let mockPostgrestPort;
  let gatewayA;
  let gatewayB;
  let portA;
  let portB;
  let testPrivateKey;
  let testPublicKey;
  const testKid = 'redis-multi-kid';
  const testProjectId = 'medibond-45fad';

  function makeToken(sub) {
    const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
    const payload = {
      iss: `https://securetoken.google.com/${testProjectId}`,
      aud: testProjectId,
      sub,
      app_role: 'patient',
      exp: Math.floor(Date.now() / 1000) + 3600,
      iat: Math.floor(Date.now() / 1000) - 10,
    };
    const h = base64UrlEncode(JSON.stringify(header));
    const p = base64UrlEncode(JSON.stringify(payload));
    const input = `${h}.${p}`;
    const sig = base64UrlEncode(crypto.sign('RSA-SHA256', Buffer.from(input), testPrivateKey));
    return `${input}.${sig}`;
  }

  function request(port, path, headers = {}) {
    return new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '127.0.0.1',
        port,
        path,
        method: 'GET',
        headers,
      }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          let json = null;
          try {
            json = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          } catch (_) {}
          resolve({ statusCode: res.statusCode, json });
        });
      });
      req.on('error', reject);
      req.end();
    });
  }

  before(async () => {
    redisUrl = process.env.REDIS_INTEGRATION_URL || (await startRedisIntegrationServer());

    const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    testPrivateKey = keyPair.privateKey;
    testPublicKey = keyPair.publicKey;
    const mockJwks = new JwksClient();
    mockJwks.setMockKeys(new Map([[testKid, testPublicKey]]));

    mockPostgrestServer = http.createServer((_req, res) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('[]');
    });
    await new Promise((resolve) => mockPostgrestServer.listen(0, '127.0.0.1', resolve));
    mockPostgrestPort = mockPostgrestServer.address().port;

    const baseCfg = {
      postgrestUrl: `http://127.0.0.1:${mockPostgrestPort}`,
      postgrestJwtSecret: 'test-postgrest-jwt-secret-min32chars',
      firebaseProjectId: testProjectId,
      jwksClient: mockJwks,
      firebaseRevocationCheck: false,
      requireFirebaseRevocationCheck: false,
      rateLimitRedisUrl: redisUrl,
      rateLimitMaxRequests: 3,
      rateLimitWindowMs: 60_000,
    };

    gatewayA = createGatewayServer(baseCfg);
    gatewayB = createGatewayServer(baseCfg);
    await new Promise((resolve) => gatewayA.server.listen(0, '127.0.0.1', resolve));
    await new Promise((resolve) => gatewayB.server.listen(0, '127.0.0.1', resolve));
    portA = gatewayA.server.address().port;
    portB = gatewayB.server.address().port;
  });

  after(async () => {
    if (gatewayA?.server) await new Promise((r) => gatewayA.server.close(r));
    if (gatewayB?.server) await new Promise((r) => gatewayB.server.close(r));
    gatewayA?.rateLimiter?.dispose?.();
    gatewayB?.rateLimiter?.dispose?.();
    if (mockPostgrestServer) await new Promise((r) => mockPostgrestServer.close(r));
    if (!process.env.REDIS_INTEGRATION_URL) {
      await stopRedisIntegrationServer();
    }
  });

  it('shares UID rate limit across two gateway instances (429 on combined traffic)', async () => {
    const token = makeToken('redis_shared_uid_test');
    const auth = { authorization: `Bearer ${token}` };

    for (let i = 0; i < 3; i++) {
      const port = i % 2 === 0 ? portA : portB;
      const res = await request(port, '/rest/v1/appointments', auth);
      assert.equal(res.statusCode, 200, `request ${i + 1}`);
    }

    const res4 = await request(portB, '/rest/v1/appointments', auth);
    assert.equal(res4.statusCode, 429);
    assert.equal(res4.json.error, 'Too Many Requests');
  });

  it('returns 429 when Redis errors (fail-closed on limiter)', async () => {
    const limiter = gatewayA.rateLimiter;
    const origIncr = limiter.redis.incr.bind(limiter.redis);
    limiter.redis.incr = async () => {
      throw new Error('simulated redis down');
    };
  const token = makeToken('redis_fail_closed_uid');
    const res = await request(portA, '/rest/v1/appointments', { authorization: `Bearer ${token}` });
    limiter.redis.incr = origIncr;
    assert.equal(res.statusCode, 429);
  });
});