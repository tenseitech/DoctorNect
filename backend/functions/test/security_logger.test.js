'use strict';

const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { logAuthAttempt, logUnusualTraffic } = require('../security_logger');
const { setSupabaseClientForTesting } = require('../caller_identity');

describe('security_logger service', () => {
  afterEach(() => {
    setSupabaseClientForTesting(null);
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    delete process.env.FIRESTORE_FORBIDDEN;
  });

  it('persists security event to Postgres security_events when cutover flag is ON', async () => {
    delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    let insertedRow = null;

    const mockSupabase = {
      from: (table) => {
        assert.equal(table, 'security_events');
        return {
          insert: async (row) => {
            insertedRow = row;
            return { error: null };
          },
        };
      },
    };

    setSupabaseClientForTesting(mockSupabase);

    const mockRequest = {
      auth: { uid: 'sec_test_user', token: { email: 'test@example.com' } },
      rawRequest: { ip: '192.168.1.100' },
      app: { appId: 'com.doctornect.app' },
    };

    const payload = logAuthAttempt(mockRequest, {
      outcome: 'failure',
      method: 'mobile_otp',
      identifier: '9876543210',
      reason: 'invalid_otp',
    });

    assert.equal(payload.severity, 'WARNING');
    assert.equal(payload.category, 'auth');
    assert.equal(payload.action, 'auth.failure');

    // Allow async persistSecurityEvent microtask to run
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.ok(insertedRow, 'Should have inserted into security_events in Postgres');
    assert.equal(insertedRow.severity, 'WARNING');
    assert.equal(insertedRow.category, 'auth');
    assert.equal(insertedRow.action, 'auth.failure');
    assert.equal(insertedRow.uid, 'sec_test_user');
    assert.equal(insertedRow.app_check_present, true);
    assert.equal(insertedRow.method, 'mobile_otp');
  });
});
