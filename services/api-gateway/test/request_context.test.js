'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { resolveRequestId, REQUEST_ID_HEADER } = require('../src/request_context');
const { emitAuditLog } = require('../src/security');

describe('request_context (REL-10)', () => {
  it('reuses valid inbound request id', () => {
    const id = resolveRequestId({ headers: { [REQUEST_ID_HEADER]: 'abc-12345678' } });
    assert.equal(id, 'abc-12345678');
  });

  it('mints request id when header missing', () => {
    const id = resolveRequestId({ headers: {} });
    assert.match(id, /^[a-f0-9]{24}$/);
  });

  it('rejects unsafe inbound ids', () => {
    const id = resolveRequestId({ headers: { [REQUEST_ID_HEADER]: 'bad id!' } });
    assert.match(id, /^[a-f0-9]{24}$/);
  });

  it('emitAuditLog includes request_id when provided', () => {
    const chunks = [];
    const origWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (chunk) => {
      chunks.push(String(chunk));
      return true;
    };
    try {
      emitAuditLog({
        method: 'GET',
        path: '/livez',
        status: 200,
        latencyMs: 1.2,
        requestId: 'audit-trace-12345678',
      });
      const line = chunks.join('').trim();
      const log = JSON.parse(line);
      assert.strictEqual(log.request_id, 'audit-trace-12345678');
      assert.strictEqual(log.event, 'api_request');
      assert.strictEqual(log.service, 'doctornect-auth-gateway');
      assert.ok(log.environment);
    } finally {
      process.stdout.write = origWrite;
    }
  });
});