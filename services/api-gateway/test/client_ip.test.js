'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clientIpFromForwardedFor, trustedProxyHops } = require('../src/client_ip');

test('gateway client IP: 1, 2 and 3 trusted hops', () => {
  assert.equal(clientIpFromForwardedFor('6.6.6.6, 203.0.113.9', '10.0.0.1', 1), '203.0.113.9');
  assert.equal(clientIpFromForwardedFor('6.6.6.6, 203.0.113.9, 130.176.0.1', '10.0.0.1', 2), '203.0.113.9');
  assert.equal(clientIpFromForwardedFor('6.6.6.6, 203.0.113.9, 130.176.0.1, 10.1.2.3', '10.0.0.1', 3), '203.0.113.9');
});

test('gateway client IP: spoofed prefix cannot change the result', () => {
  const real = '203.0.113.9';
  for (const spoof of ['1.1.1.1', '1.1.1.1, 2.2.2.2', 'evil, 3.3.3.3']) {
    assert.equal(clientIpFromForwardedFor(`${spoof}, ${real}`, '10.0.0.1', 1), real);
  }
});

test('gateway client IP: fallback and env bounds', () => {
  assert.equal(clientIpFromForwardedFor(undefined, '10.0.0.1', 1), '10.0.0.1');
  assert.equal(clientIpFromForwardedFor('not-an-ip', '10.0.0.1', 1), '10.0.0.1');
  assert.equal(trustedProxyHops({}), 1);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: '3' }), 3);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: '-1' }), 1);
});
