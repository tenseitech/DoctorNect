'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createGatewayServer } = require('../../services/api-gateway/src/server');
const { probePath } = require('../ops/synthetic_gateway_probe');

describe('synthetic_gateway_probe (Audit 7 activation)', () => {
  let mockPostgrestServer;
  let gatewayInstance;
  let gatewayServer;
  let baseUrl;

  before(async () => {
    mockPostgrestServer = http.createServer((_req, res) => {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end('{}');
    });
    await new Promise((resolve) => mockPostgrestServer.listen(0, '127.0.0.1', resolve));
    const mockPort = mockPostgrestServer.address().port;
    gatewayInstance = createGatewayServer({
      postgrestUrl: `http://127.0.0.1:${mockPort}`,
      rateLimitRedisUrl: '',
      firebaseRevocationCheck: false,
      requireFirebaseRevocationCheck: false,
    });
    gatewayServer = gatewayInstance.server;
    await new Promise((resolve) => gatewayServer.listen(0, '127.0.0.1', resolve));
    const port = gatewayServer.address().port;
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    gatewayInstance.rateLimiter.dispose();
    if (gatewayInstance.anonRateLimiter) gatewayInstance.anonRateLimiter.dispose();
    await new Promise((resolve) => gatewayServer.close(resolve));
    await new Promise((resolve) => mockPostgrestServer.close(resolve));
  });

  it('probes /livez and /readyz with latency', async () => {
    const live = await probePath(baseUrl, '/livez', 5000);
    assert.strictEqual(live.ok, true);
    assert.ok(live.latencyMs >= 0);
    const ready = await probePath(baseUrl, '/readyz', 5000);
    assert.strictEqual(ready.ok, true);
    assert.ok(ready.body.dependencies);
  });
});