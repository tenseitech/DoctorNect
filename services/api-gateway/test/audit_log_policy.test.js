'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  shouldEmitGatewayAuditLog,
  resolveSuccessSampleRate,
} = require('../src/audit_log_policy');

describe('audit_log_policy (OPS cost)', () => {
  const prev = process.env.GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE;

  afterEach(() => {
    if (prev === undefined) delete process.env.GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE;
    else process.env.GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE = prev;
  });

  it('always logs 4xx/5xx', () => {
    assert.strictEqual(shouldEmitGatewayAuditLog({ statusCode: 500, method: 'GET', path: '/x' }), true);
    assert.strictEqual(shouldEmitGatewayAuditLog({ statusCode: 401, method: 'GET', path: '/x' }), true);
  });

  it('never logs OPTIONS success', () => {
    assert.strictEqual(shouldEmitGatewayAuditLog({ statusCode: 204, method: 'OPTIONS', path: '/x' }), false);
  });

  it('always logs health probes', () => {
    assert.strictEqual(shouldEmitGatewayAuditLog({ statusCode: 200, method: 'GET', path: '/readyz' }), true);
  });

  it('respects sample rate env', () => {
    process.env.GATEWAY_AUDIT_SUCCESS_SAMPLE_RATE = '0';
    assert.strictEqual(resolveSuccessSampleRate(), 0);
    assert.strictEqual(shouldEmitGatewayAuditLog({ statusCode: 200, method: 'GET', path: '/rest/v1/foo' }), false);
  });
});