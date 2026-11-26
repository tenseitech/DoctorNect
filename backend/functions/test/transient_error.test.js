'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  isTransientSyncError,
  computeBackoffMs,
} = require('../src/reliability/transient_error');

describe('transient_error (REL-02)', () => {
  it('classifies network and timeout errors as transient', () => {
    assert.equal(isTransientSyncError({ code: 'ECONNRESET' }), true);
    assert.equal(isTransientSyncError({ message: 'Request timeout' }), true);
    assert.equal(isTransientSyncError({ status: 503 }), true);
  });

  it('does not classify validation errors as transient', () => {
    assert.equal(isTransientSyncError({ status: 400 }), false);
    assert.equal(isTransientSyncError({ status: 401 }), false);
    assert.equal(isTransientSyncError({ status: 403 }), false);
    assert.equal(isTransientSyncError({ message: 'invalid input' }), false);
  });

  it('computes bounded backoff with jitter headroom', () => {
    const d1 = computeBackoffMs(1, { baseDelayMs: 100, maxDelayMs: 1000 });
    const d3 = computeBackoffMs(3, { baseDelayMs: 100, maxDelayMs: 1000 });
    assert.ok(d1 >= 100 && d1 <= 130);
    assert.ok(d3 >= 400 && d3 <= 520);
    assert.ok(d3 > d1);
  });
});