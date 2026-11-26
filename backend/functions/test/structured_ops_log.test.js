'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { emitSyncDlqEvent } = require('../src/observability/structured_ops_log');

describe('structured_ops_log (OPS-01)', () => {
  it('emitSyncDlqEvent omits raw payload PHI fields', () => {
    const chunks = [];
    const origErr = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk) => {
      chunks.push(String(chunk));
      return true;
    };
    try {
      emitSyncDlqEvent({
        direction: 'firestore_to_supabase',
        entityType: 'appointments',
        entityId: 'appt-1',
        retryCount: 3,
        errorMessage: 'Bearer secret-token failure',
      });
      const line = chunks.join('').trim();
      const log = JSON.parse(line);
      assert.strictEqual(log.event, 'cross_role_sync_dlq');
      assert.strictEqual(log.service, 'doctornect-functions');
      assert.doesNotMatch(JSON.stringify(log.detail), /secret-token/);
    } finally {
      process.stderr.write = origErr;
    }
  });
});