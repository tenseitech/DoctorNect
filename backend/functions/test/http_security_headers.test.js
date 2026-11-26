'use strict';

/** Every onRequest endpoint sets baseline security headers before responding. */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { withApiSecurityHeaders } = require('../http_endpoint_security');

function fakeRes() {
  const headers = {};
  return { headers, set: (k, v) => { headers[k.toLowerCase()] = v; }, status() { return this; }, json() { return this; }, send() { return this; } };
}

test('wrapper sets nosniff, frame deny, CSP, HSTS, no-store', async () => {
  const res = fakeRes();
  await withApiSecurityHeaders((_req, r) => r.json({}))({ headers: {} }, res);
  assert.equal(res.headers['x-content-type-options'], 'nosniff');
  assert.equal(res.headers['x-frame-options'], 'DENY');
  assert.match(res.headers['content-security-policy'], /default-src 'none'/);
  assert.match(res.headers['strict-transport-security'], /max-age=\d+/);
  assert.equal(res.headers['cache-control'], 'no-store');
  const pub = fakeRes();
  await withApiSecurityHeaders((_req, r) => r.json({}), { cacheable: true })({ headers: {} }, pub);
  assert.equal(pub.headers['cache-control'], undefined);
});

test('all non-admin onRequest endpoints are wrapped', () => {
  for (const f of ['index.js', 'promoted_ads.js']) {
    const src = fs.readFileSync(path.join(__dirname, '..', f), 'utf8');
    const blocks = src.split('onRequest(').slice(1);
    assert.ok(blocks.length > 0);
    for (const b of blocks) {
      assert.match(b.slice(0, 400), /withApiSecurityHeaders\(/, `${f}: onRequest without security headers`);
    }
  }
});
