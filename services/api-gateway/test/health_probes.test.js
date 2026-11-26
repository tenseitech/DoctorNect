'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createGatewayServer } = require('../src/server');

describe('gateway health probes (DB-04)', () => {
  let mockPostgrestServer;
  let gatewayInstance;
  let gatewayServer;
  let gatewayPort;

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
    gatewayPort = gatewayServer.address().port;
  });

  after(async () => {
    gatewayInstance.rateLimiter.dispose();
    if (gatewayInstance.anonRateLimiter) gatewayInstance.anonRateLimiter.dispose();
    await new Promise((resolve) => gatewayServer.close(resolve));
    await new Promise((resolve) => mockPostgrestServer.close(resolve));
  });

  async function getJson(pathname) {
    const res = await fetch(`http://127.0.0.1:${gatewayPort}${pathname}`);
    const json = await res.json();
    return { statusCode: res.status, json };
  }

  it('serves /livez without dependency failure', async () => {
    const res = await getJson('/livez');
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.json.probe, 'liveness');
    assert.strictEqual(res.json.status, 'ok');
  });

  it('serves /readyz with dependency object and no secrets', async () => {
    const res = await getJson('/readyz');
    assert.ok(res.json.dependencies);
    assert.ok(res.json.dependencies.postgrest);
    assert.strictEqual(res.json.probe, 'readiness');
    const blob = JSON.stringify(res.json);
    assert.doesNotMatch(blob, /password|secret|redis:\/\/.*@/i);
  });

  it('keeps /healthz contract for backward compatibility', async () => {
    const res = await getJson('/healthz');
    assert.ok(['healthy', 'degraded'].includes(res.json.status));
    assert.strictEqual(res.json.service, 'doctornect-auth-gateway');
    assert.ok(res.json.postgrest);
  });
});