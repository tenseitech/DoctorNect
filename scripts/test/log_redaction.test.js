'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  redactString,
  redactObject,
  operationalLogEnvelope,
} = require('../lib/log_redaction');

describe('log_redaction (OPS-02)', () => {
  it('redacts Bearer tokens and JWT-shaped strings', () => {
    const raw = 'Auth Bearer abc.def.ghi and eyJhbGciOiJIUzI1NiJ9.a.b';
    const out = redactString(raw);
    assert.doesNotMatch(out, /abc\.def\.ghi/);
    assert.doesNotMatch(out, /eyJhbGci/);
  });

  it('redacts sensitive object keys', () => {
    const out = redactObject({
      appointment_id: 'a1',
      password: 'secret',
      otp: '123456',
      nested: { access_token: 'tok', ok: true },
    });
    assert.strictEqual(out.password, '[REDACTED]');
    assert.strictEqual(out.otp, '[REDACTED]');
    assert.strictEqual(out.nested.access_token, '[REDACTED]');
    assert.strictEqual(out.appointment_id, 'a1');
  });

  it('redacts phone-like patterns and truncates long strings', () => {
    const long = 'x'.repeat(5000);
    const out = redactString(`call +1-555-123-4567 ${long}`);
    assert.doesNotMatch(out, /555-123-4567/);
    assert.ok(out.includes('[TRUNCATED]'));
  });

  it('operationalLogEnvelope includes service and environment', () => {
    const entry = operationalLogEnvelope({
      service: 'doctornect-gateway',
      event: 'test_event',
      severity: 'INFO',
      requestId: 'req-12345678',
    });
    assert.strictEqual(entry.service, 'doctornect-gateway');
    assert.ok(entry.environment);
    assert.strictEqual(entry.request_id, 'req-12345678');
    assert.strictEqual(entry.event, 'test_event');
  });
});