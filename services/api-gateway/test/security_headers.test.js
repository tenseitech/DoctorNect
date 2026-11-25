'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createGatewayServer } = require('../src/server');

describe('API security headers (SEC-13)', () => {
  let server;
  let port;

  before(async () => {
    const gw = createGatewayServer({
      firebaseRevocationCheck: false,
      requireFirebaseRevocationCheck: false,
      corsAllowedOrigins: ['http://127.0.0.1'],
    });
    server = gw.server;
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    port = server.address().port;
  });

  after(async () => {
    if (server) await new Promise((resolve) => server.close(resolve));
  });

  it('includes baseline security headers on JSON error responses', async () => {
    const res = await new Promise((resolve, reject) => {
      const req = http.request({
        hostname: '127.0.0.1',
        port,
        path: '/rest/v1/doctors',
        method: 'GET',
      }, resolve);
      req.on('error', reject);
      req.end();
    });

    assert.equal(res.headers['x-content-type-options'], 'nosniff');
    assert.equal(res.headers['x-frame-options'], 'DENY');
    assert.equal(res.headers['referrer-policy'], 'no-referrer');
    assert.equal(res.headers['cache-control'], 'no-store');
    res.resume();
  });
});