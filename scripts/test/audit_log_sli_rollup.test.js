'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { rollupGatewaySli } = require('../lib/audit_log_sli_rollup');

describe('audit_log_sli_rollup (SLI validation)', () => {
  it('computes availability and p95 from audit lines', () => {
    const sample = [
      '{"event":"api_request","status":200,"latency_ms":10}',
      '{"event":"api_request","status":200,"latency_ms":50}',
      '{"event":"api_request","status":500,"latency_ms":100}',
      '{"event":"other","status":200}',
    ].join('\n');
    const r = rollupGatewaySli(sample);
    assert.strictEqual(r.count, 3);
    assert.ok(Math.abs(r.availability - 2 / 3) < 0.001);
    assert.ok(Math.abs(r.error_rate_5xx - 1 / 3) < 0.001);
    assert.strictEqual(r.p95_latency_ms, 100);
  });
});