'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { dbRequestTimeoutMs, fetchWithTimeout, setDbRequestTimeoutForTesting } = require('../src/db/client');

test('database requests time out instead of hanging (gateway outage)', async () => {
  const hung = http.createServer(() => { /* never answers */ });
  await new Promise((r) => hung.listen(0, '127.0.0.1', r));
  setDbRequestTimeoutForTesting(1000);
  const t0 = Date.now();
  try {
    await assert.rejects(() => fetchWithTimeout(`http://127.0.0.1:${hung.address().port}/rest/v1/users`), /abort|timeout/i);
    assert.ok(Date.now() - t0 < 5000, 'timed out promptly');
  } finally {
    setDbRequestTimeoutForTesting(null);
    hung.closeAllConnections();
    await new Promise((r) => hung.close(r));
  }
});

test('default database timeout is 15 s (below the 60 s function limit)', () => {
  assert.equal(dbRequestTimeoutMs(), 15000);
});

test('the shared client is built with the timeout fetch', () => {
  const src = require('fs').readFileSync(require('path').join(__dirname, '../src/db/client.js'), 'utf8');
  assert.match(src, /fetch: fetchWithTimeout/);
});
