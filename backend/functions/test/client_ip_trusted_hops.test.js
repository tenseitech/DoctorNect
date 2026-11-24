'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clientIpFromForwardedFor, clientIpFromRawRequest, trustedProxyHops } = require('../src/net/client_ip');
const { clientIpFromRequest } = require('../abuse_rate_limit');

test('1 trusted hop: rightmost entry is the client (proxy-appended)', () => {
  assert.equal(clientIpFromForwardedFor('203.0.113.9', '10.0.0.1', 1), '203.0.113.9');
  assert.equal(clientIpFromForwardedFor('198.51.100.1, 203.0.113.9', '10.0.0.1', 1), '203.0.113.9');
});

test('2 trusted hops: second entry from the right', () => {
  assert.equal(clientIpFromForwardedFor('203.0.113.9, 35.191.0.1', '10.0.0.1', 2), '203.0.113.9');
  assert.equal(clientIpFromForwardedFor('6.6.6.6, 203.0.113.9, 35.191.0.1', '10.0.0.1', 2), '203.0.113.9');
});

test('3 trusted hops: third entry from the right', () => {
  assert.equal(
    clientIpFromForwardedFor('6.6.6.6, 203.0.113.9, 130.176.0.1, 35.191.0.1', '10.0.0.1', 3),
    '203.0.113.9',
  );
});

test('spoofed leftmost values never win', () => {
  // Attacker sends X-Forwarded-For: 1.1.1.1, 2.2.2.2 ; GFE appends the real address.
  const xff = '1.1.1.1, 2.2.2.2, 203.0.113.9';
  assert.equal(clientIpFromForwardedFor(xff, '10.0.0.1', 1), '203.0.113.9');
  // Rotating the spoofed prefix does not change the bucket key.
  assert.equal(clientIpFromForwardedFor('9.9.9.9, 203.0.113.9', '10.0.0.1', 1), '203.0.113.9');
});

test('fewer entries than hops falls back to the leftmost proxy-written entry', () => {
  assert.equal(clientIpFromForwardedFor('203.0.113.9', '10.0.0.1', 3), '203.0.113.9');
});

test('garbage / injected values fall back to the socket address', () => {
  assert.equal(clientIpFromForwardedFor('203.0.113.9, <script>', '10.0.0.1', 1), '10.0.0.1');
  assert.equal(clientIpFromForwardedFor('', '10.0.0.1', 1), '10.0.0.1');
  assert.equal(clientIpFromForwardedFor(undefined, undefined, 1), 'unknown');
});

test('TRUSTED_PROXY_HOPS env parsing defaults to 1 and is bounded', () => {
  assert.equal(trustedProxyHops({}), 1);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: '2' }), 2);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: '0' }), 1);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: 'abc' }), 1);
  assert.equal(trustedProxyHops({ TRUSTED_PROXY_HOPS: '99' }), 1);
});

test('rate-limit IP helper honours TRUSTED_PROXY_HOPS', () => {
  const prev = process.env.TRUSTED_PROXY_HOPS;
  try {
    const raw = { headers: { 'x-forwarded-for': '1.1.1.1, 203.0.113.9, 35.191.0.1' }, ip: '10.0.0.1' };
    process.env.TRUSTED_PROXY_HOPS = '1';
    assert.equal(clientIpFromRequest({ rawRequest: raw }), '35.191.0.1');
    process.env.TRUSTED_PROXY_HOPS = '2';
    assert.equal(clientIpFromRawRequest(raw), '203.0.113.9');
  } finally {
    if (prev === undefined) delete process.env.TRUSTED_PROXY_HOPS;
    else process.env.TRUSTED_PROXY_HOPS = prev;
  }
});
