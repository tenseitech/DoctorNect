'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createGatewayServer } = require('../src/server');
const { REQUEST_ID_HEADER } = require('../src/request_context');

describe('gateway request correlation (REL-10)', () => {
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

  it('returns valid inbound x-request-id on /livez', async () => {
    const inbound = 'client-req-12345678';
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/livez`, {
      headers: { [REQUEST_ID_HEADER]: inbound },
    });
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.headers.get(REQUEST_ID_HEADER), inbound);
  });

  it('mints x-request-id when inbound value is invalid', async () => {
    const res = await fetch(`http://127.0.0.1:${gatewayPort}/livez`, {
      headers: { [REQUEST_ID_HEADER]: 'not valid!!!' },
    });
    const id = res.headers.get(REQUEST_ID_HEADER);
    assert.ok(id);
    assert.match(id, /^[a-f0-9]{24}$/);
  });

});