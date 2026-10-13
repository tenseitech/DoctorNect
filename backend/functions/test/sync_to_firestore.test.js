'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

// Dynamically import the ES module under test
async function loadEdgeFunction() {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  return edgeModule.handleSyncToFirestore;
}

test('Edge Function Auth: Rejects unauthenticated calls when secret is missing or invalid', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  // 1. Missing secret header -> 401
  const reqNoAuth = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: { appointment_id: 'apt-1', doctor_status: 'cancelled' },
    }),
  });
  const resNoAuth = await handleSyncToFirestore(reqNoAuth, {
    expectedSecret: 'super-secret-token',
  });
  assert.equal(resNoAuth.status, 401);
  const bodyNoAuth = await resNoAuth.json();
  assert.equal(bodyNoAuth.error, 'unauthorized');

  // 2. Invalid secret header -> 401
  const reqBadAuth = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'wrong-secret',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: { appointment_id: 'apt-1', doctor_status: 'cancelled' },
    }),
  });
  const resBadAuth = await handleSyncToFirestore(reqBadAuth, {
    expectedSecret: 'super-secret-token',
  });
  assert.equal(resBadAuth.status, 401);

  // 3. No secret configured in environment (fail closed -> 500)
  const reqNoEnv = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'some-secret',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: { appointment_id: 'apt-1' },
    }),
  });
  const resNoEnv = await handleSyncToFirestore(reqNoEnv, {
    expectedSecret: null,
  });
  assert.equal(resNoEnv.status, 500);
  const bodyNoEnv = await resNoEnv.json();
  assert.equal(bodyNoEnv.error, 'server_misconfigured');
});

test('Edge Function Auth: Accepts valid secret via x-webhook-secret or Bearer token', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writtenData = null;

  const mockWriter = async (id, data) => {
    writtenData = { id, data };
  };

  // Valid via x-webhook-secret
  const reqHeader = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'correct-secret-123',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: { appointment_id: 'apt-valid-1', doctor_status: 'cancelled' },
    }),
  });
  const resHeader = await handleSyncToFirestore(reqHeader, {
    expectedSecret: 'correct-secret-123',
    firestoreWriter: mockWriter,
  });
  assert.equal(resHeader.status, 200);
  assert.equal(writtenData.id, 'apt-valid-1');

  // Valid via Authorization Bearer header
  writtenData = null;
  const reqBearer = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer correct-secret-123',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: { appointment_id: 'apt-valid-2', doctor_status: 'confirmed' },
    }),
  });
  const resBearer = await handleSyncToFirestore(reqBearer, {
    expectedSecret: 'correct-secret-123',
    firestoreWriter: mockWriter,
  });
  assert.equal(resBearer.status, 200);
  assert.equal(writtenData.id, 'apt-valid-2');
});

test('Edge Function Event Filter: Ignores non-UPDATE types, other tables, or other schemas with 200 {ignored: true}', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writeCalled = false;
  const mockWriter = async () => {
    writeCalled = true;
  };

  const ignoredEvents = [
    { type: 'INSERT', table: 'appointments', schema: 'public' },
    { type: 'DELETE', table: 'appointments', schema: 'public' },
    { type: 'UPDATE', table: 'patients', schema: 'public' },
    { type: 'UPDATE', table: 'users', schema: 'public' },
    { type: 'UPDATE', table: 'appointments', schema: 'private' },
  ];

  for (const evt of ignoredEvents) {
    writeCalled = false;
    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'secret-filter-test',
      },
      body: JSON.stringify({
        ...evt,
        record: { appointment_id: 'apt-ignore-1', doctor_status: 'cancelled' },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'secret-filter-test',
      firestoreWriter: mockWriter,
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ignored, true);
    assert.equal(writeCalled, false, `Writer should not be called for event ${JSON.stringify(evt)}`);
  }
});

test('Edge Function Loop Prevention: Drops writes originating from Firestore, Reconciler, or Bridge', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writeCalled = false;
  const mockWriter = async () => {
    writeCalled = true;
  };

  const loopOrigins = [
    { sync_origin: 'doctor_firestore' },
    { sync_origin: 'patient_firestore' },
    { sync_origin: 'reconciler_bot' },
    { synced_by: 'firestore_cloud_function' },
    { synced_by: 'supabase_bridge' },
  ];

  for (const originMarker of loopOrigins) {
    writeCalled = false;
    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'secret',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-loop-test',
          doctor_status: 'cancelled',
          ...originMarker,
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'secret',
      firestoreWriter: mockWriter,
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ignored, true);
    assert.match(body.reason, /Loop prevented/);
    assert.equal(writeCalled, false, `Writer should not be called for ${JSON.stringify(originMarker)}`);
  }
});

test('TASK 3c: Token-only update is ignored with 200 { ignored: "no_status_change" }', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writeCalled = false;
  const mockWriter = async () => {
    writeCalled = true;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-token-1',
        token_number: 10,
        patient_status: 'confirmed',
        doctor_status: 'confirmed',
      },
      old_record: {
        appointment_id: 'apt-token-1',
        token_number: 9,
        patient_status: 'confirmed',
        doctor_status: 'confirmed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ignored, 'no_status_change');
  assert.equal(writeCalled, false, 'Writer must NOT be called for token-only updates');
});

test('TASK 3c: Status change written to Firestore with only changed fields', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writtenId = null;
  let writtenPayload = null;

  const mockWriter = async (id, data) => {
    writtenId = id;
    writtenPayload = data;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-status-change-1',
        doctor_status: 'confirmed',
        patient_status: 'confirmed',
        token_number: 12,
      },
      old_record: {
        appointment_id: 'apt-status-change-1',
        doctor_status: 'pendingRequest',
        patient_status: 'confirmed',
        token_number: 12,
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const resBody = await res.json();
  assert.equal(resBody.success, true);
  assert.equal(writtenId, 'apt-status-change-1');
  assert.equal(writtenPayload.doctorStatus, 'confirmed');
  assert.equal(writtenPayload.syncedBy, 'supabase_bridge');
  assert.ok(writtenPayload.updatedAt instanceof Date);

  // Unchanged fields must NOT be included in written payload
  assert.equal(writtenPayload.patientStatus, undefined, 'Unchanged patientStatus must not be written');
  assert.equal(writtenPayload.cancellationReason, undefined);
  assert.equal(writtenPayload.token_number, undefined);
});

test('TASK 3c: Cancellation writes only cancellation fields and adjusts updateMask', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writtenId = null;
  let writtenPayload = null;

  const mockWriter = async (id, data) => {
    writtenId = id;
    writtenPayload = data;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-cancel-fields-1',
        patient_status: 'cancelled',
        cancellation_reason: 'High fever',
        cancelled_by: 'patient',
        cancelled_at: '2026-10-13T10:00:00.000Z',
        doctor_status: 'confirmed', // unchanged
        token_number: 5,
      },
      old_record: {
        appointment_id: 'apt-cancel-fields-1',
        patient_status: 'confirmed',
        cancellation_reason: null,
        cancelled_by: null,
        cancelled_at: null,
        doctor_status: 'confirmed', // unchanged
        token_number: 5,
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  assert.equal(writtenId, 'apt-cancel-fields-1');
  assert.equal(writtenPayload.patientStatus, 'cancelled');
  assert.equal(writtenPayload.cancellationReason, 'High fever');
  assert.equal(writtenPayload.cancelledBy, 'patient');
  assert.ok(writtenPayload.cancelledAt instanceof Date);
  assert.equal(writtenPayload.doctorStatus, undefined, 'Unchanged doctorStatus must not be in payload');
});

test('TASK 3c: Missing old_record uses safe fallback (propagates defined status fields, skips when none)', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writtenPayload = null;

  const mockWriter = async (id, data) => {
    writtenPayload = data;
  };

  // Case 1: old_record missing but record has cancellation fields -> writes defined fields safely
  const reqWithStatus = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-safe-fallback-1',
        patient_status: 'cancelled',
        cancellation_reason: 'Emergency hospital visit',
      },
      // old_record deliberately omitted
    }),
  });

  const resWithStatus = await handleSyncToFirestore(reqWithStatus, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter,
  });

  assert.equal(resWithStatus.status, 200);
  assert.equal(writtenPayload.patientStatus, 'cancelled');
  assert.equal(writtenPayload.cancellationReason, 'Emergency hospital visit');

  // Case 2: old_record missing and record has NO status/cancellation fields -> ignored as no_status_change
  let writeCalled2 = false;
  const mockWriter2 = async () => {
    writeCalled2 = true;
  };

  const reqWithoutStatus = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-safe-fallback-2',
        token_number: 44,
      },
    }),
  });

  const resWithoutStatus = await handleSyncToFirestore(reqWithoutStatus, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter2,
  });

  assert.equal(resWithoutStatus.status, 200);
  const bodyWithoutStatus = await resWithoutStatus.json();
  assert.equal(bodyWithoutStatus.ignored, 'no_status_change');
  assert.equal(writeCalled2, false);
});

test('Edge Function Execution: Writes appointment status changes and cancellations to Firestore', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writtenId = null;
  let writtenPayload = null;

  const mockWriter = async (id, data) => {
    writtenId = id;
    writtenPayload = data;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-xyz',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-cancel-999',
        doctor_status: 'cancelled',
        patient_status: 'cancelled',
        cancellation_reason: 'Patient fever spikes, doctor informed',
        cancelled_by: 'patient',
        cancelled_at: '2026-10-13T10:00:00.000Z',
        updated_at: '2026-10-13T10:00:00.000Z',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-xyz',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const resBody = await res.json();
  assert.equal(resBody.success, true);
  assert.equal(resBody.appointmentId, 'apt-cancel-999');
  assert.equal(resBody.syncedBy, 'supabase_bridge');

  // Verify written payload contains status/cancellation fields only
  assert.equal(writtenId, 'apt-cancel-999');
  assert.equal(writtenPayload.syncedBy, 'supabase_bridge');
  assert.equal(writtenPayload.doctorStatus, 'cancelled');
  assert.equal(writtenPayload.patientStatus, 'cancelled');
  assert.equal(writtenPayload.cancellationReason, 'Patient fever spikes, doctor informed');
  assert.equal(writtenPayload.cancelledBy, 'patient');
  assert.ok(writtenPayload.cancelledAt instanceof Date);
  assert.ok(writtenPayload.updatedAt instanceof Date);
});

test('Edge Function Failure: Returns non-2xx status on Firestore write error so Supabase retries', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  const failingWriter = async () => {
    throw new Error('Firestore connection timeout: UNAVAILABLE');
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-retry-test',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-fail-1',
        doctor_status: 'cancelled',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-retry-test',
    firestoreWriter: failingWriter,
  });

  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.error, 'internal_error');
  assert.equal(body.retriable, true);
  assert.match(body.message, /Firestore connection timeout/);
});

test('TASK 3d: 404 from Firestore emits structured warning and writes Firestore dead letter without free text', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  let capturedDeadLetter = null;
  const mockDeadLetterWriter = async (id, reason, changedFields, ms) => {
    capturedDeadLetter = { id, reason, changedFields, ms };
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-404-test',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-missing-doc-12345',
        patient_status: 'cancelled',
        cancellation_reason: 'Doctor absent',
        cancelled_by: 'patient',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-404-test',
    firestoreReader: async (id) => {
      const err = new Error(`Firestore REST read failed (404): document appointments/${id} not found`);
      err.status = 404;
      err.code = 'NOT_FOUND';
      throw err;
    },
    deadLetterWriter: mockDeadLetterWriter,
  });

  assert.equal(res.status, 200, 'Precondition 404 must return 200 to halt retries');
  const body = await res.json();
  assert.equal(body.skipped, 'not_found');
  assert.equal(body.reason, 'firestore_doc_missing');
  assert.ok(body.appointmentIdHash, 'Must include appointmentIdHash');
  assert.match(body.appointmentIdHash, /^[a-f0-9]{16}$/);

  // Assert dead letter content: field NAMES only, NO free text
  assert.ok(capturedDeadLetter, 'Dead letter writer must be called');
  assert.equal(capturedDeadLetter.id, 'apt-missing-doc-12345');
  assert.equal(capturedDeadLetter.reason, 'firestore_doc_missing');
  assert.ok(Array.isArray(capturedDeadLetter.changedFields));
  assert.ok(capturedDeadLetter.changedFields.includes('patientStatus'));
  assert.ok(capturedDeadLetter.changedFields.includes('cancellationReason'));
  assert.ok(!capturedDeadLetter.changedFields.includes('Doctor absent'), 'Must not store patient-entered text');
});

test('TASK 3d: Terminal document is skipped, writes dead letter, and returns 200 { skipped: "terminal_state" }', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  let capturedDeadLetter = null;
  let writeCalled = false;

  const mockReader = async (id) => ({
    name: `projects/p/databases/(default)/documents/appointments/${id}`,
    updateTime: '2026-10-13T10:00:00.000Z',
    fields: {
      doctorStatus: { stringValue: 'completed' },
      patientStatus: { stringValue: 'completed' },
    },
  });

  const mockWriter = async () => {
    writeCalled = true;
  };

  const mockDeadLetterWriter = async (id, reason, changedFields, ms) => {
    capturedDeadLetter = { id, reason, changedFields, ms };
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-term-test',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-terminal-1',
        doctor_status: 'cancelled',
        cancellation_reason: 'Trying to cancel completed visit',
      },
      old_record: {
        appointment_id: 'apt-terminal-1',
        doctor_status: 'completed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-term-test',
    firestoreReader: mockReader,
    firestoreWriter: mockWriter,
    deadLetterWriter: mockDeadLetterWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.skipped, 'terminal_state');
  assert.equal(body.reason, 'terminal_state');
  assert.equal(body.currentStatus, 'completed');
  assert.equal(writeCalled, false, 'Terminal document must not be overwritten');

  // Verify dead letter recorded with field names only and NO free text
  assert.ok(capturedDeadLetter, 'Dead letter must be recorded for terminal-state skip');
  assert.equal(capturedDeadLetter.id, 'apt-terminal-1');
  assert.equal(capturedDeadLetter.reason, 'terminal_state');
  assert.deepEqual(capturedDeadLetter.changedFields.sort(), ['cancellationReason', 'doctorStatus'].sort());
  assert.ok(!capturedDeadLetter.changedFields.includes('Trying to cancel completed visit'));
});

test('TASK 3d: Non-terminal document is updated with precondition updateTime', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  let passedUpdateTime = null;
  let writtenData = null;

  const mockReader = async (id) => ({
    name: `projects/p/databases/(default)/documents/appointments/${id}`,
    updateTime: '2026-10-13T12:00:00.123456Z',
    fields: {
      doctorStatus: { stringValue: 'pendingRequest' },
    },
  });

  const mockWriter = async (id, data, updateTime) => {
    writtenData = data;
    passedUpdateTime = updateTime;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-nonterm-test',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-nonterm-1',
        doctor_status: 'confirmed',
      },
      old_record: {
        appointment_id: 'apt-nonterm-1',
        doctor_status: 'pendingRequest',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-nonterm-test',
    firestoreReader: mockReader,
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(passedUpdateTime, '2026-10-13T12:00:00.123456Z');
  assert.equal(writtenData.doctorStatus, 'confirmed');
});

test('TASK 3d: Concurrent modification (409/412) re-reads once and retries once', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  let readCount = 0;
  let writeAttempts = [];

  const mockReader = async (id) => {
    readCount++;
    return {
      name: `projects/p/databases/(default)/documents/appointments/${id}`,
      updateTime: readCount === 1 ? 'v1-time' : 'v2-time',
      fields: {
        doctorStatus: { stringValue: 'pendingRequest' },
      },
    };
  };

  const mockWriter = async (id, data, updateTime) => {
    writeAttempts.push(updateTime);
    if (writeAttempts.length === 1) {
      const err = new Error('Precondition failed: document was modified (412)');
      err.status = 412;
      err.code = 'FAILED_PRECONDITION';
      throw err;
    }
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-retry-concurrent',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-retry-1',
        doctor_status: 'confirmed',
      },
      old_record: {
        appointment_id: 'apt-retry-1',
        doctor_status: 'pendingRequest',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-retry-concurrent',
    firestoreReader: mockReader,
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(readCount, 2, 'Must re-read once on precondition failure');
  assert.deepEqual(writeAttempts, ['v1-time', 'v2-time'], 'Must retry write once with updated updateTime');
});

test('TASK 3d: Concurrent modification retry failure returns non-2xx so Supabase retries', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();

  let readCount = 0;
  let writeCount = 0;

  const mockReader = async (id) => {
    readCount++;
    return {
      name: `projects/p/databases/(default)/documents/appointments/${id}`,
      updateTime: `v${readCount}-time`,
      fields: { doctorStatus: { stringValue: 'pendingRequest' } },
    };
  };

  const persistentFailingWriter = async () => {
    writeCount++;
    const err = new Error('Precondition failed (412)');
    err.status = 412;
    err.code = 'FAILED_PRECONDITION';
    throw err;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-fail-twice',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-retry-fail-1',
        doctor_status: 'confirmed',
      },
      old_record: {
        appointment_id: 'apt-retry-fail-1',
        doctor_status: 'pendingRequest',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-fail-twice',
    firestoreReader: mockReader,
    firestoreWriter: persistentFailingWriter,
  });

  assert.equal(res.status, 500);
  assert.equal(writeCount, 2, 'Must attempt write at most twice (initial + 1 retry)');
  const body = await res.json();
  assert.equal(body.error, 'internal_error');
  assert.equal(body.retriable, true);
});

test('Typed Firestore REST Shape: Formats cancellation fields and updateMask strictly', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { buildFirestoreFields } = edgeModule;

  const cancellationData = {
    syncedBy: 'supabase_bridge',
    doctorStatus: 'cancelled',
    patientStatus: 'cancelled',
    cancellationReason: 'Patient fever spikes, doctor informed',
    cancelledBy: 'patient',
    cancelledAt: new Date('2026-10-13T10:00:00.000Z'),
    updatedAt: new Date('2026-10-13T10:00:00.000Z'),
  };

  const { fields, fieldPaths } = buildFirestoreFields(cancellationData);

  // Exact typed Firestore REST representation
  assert.deepEqual(fields, {
    syncedBy: { stringValue: 'supabase_bridge' },
    doctorStatus: { stringValue: 'cancelled' },
    patientStatus: { stringValue: 'cancelled' },
    cancellationReason: { stringValue: 'Patient fever spikes, doctor informed' },
    cancelledBy: { stringValue: 'patient' },
    cancelledAt: { timestampValue: '2026-10-13T10:00:00.000Z' },
    updatedAt: { timestampValue: '2026-10-13T10:00:00.000Z' },
  });

  assert.deepEqual(fieldPaths, [
    'syncedBy',
    'doctorStatus',
    'patientStatus',
    'cancellationReason',
    'cancelledBy',
    'cancelledAt',
    'updatedAt',
  ]);

  const maskQuery = fieldPaths.map((p) => `updateMask.fieldPaths=${encodeURIComponent(p)}`).join('&');
  assert.equal(
    maskQuery,
    'updateMask.fieldPaths=syncedBy&updateMask.fieldPaths=doctorStatus&updateMask.fieldPaths=patientStatus&updateMask.fieldPaths=cancellationReason&updateMask.fieldPaths=cancelledBy&updateMask.fieldPaths=cancelledAt&updateMask.fieldPaths=updatedAt'
  );
});

test('Service Account Auth: Generates throwaway RSA keypair and verifies RS256 JWT signature and claims', async () => {
  const crypto = require('node:crypto');
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { createServiceAccountJwt } = edgeModule;

  // 1. Generate throwaway 2048-bit RSA keypair in-memory (no hardcoded keys)
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });

  const testEmail = 'sync-service@doctornect-staging.iam.gserviceaccount.com';

  // 2. Sign JWT using Edge Function's own signing code
  const jwt = await createServiceAccountJwt(testEmail, privateKey);
  assert.ok(typeof jwt === 'string' && jwt.length > 50);

  const parts = jwt.split('.');
  assert.equal(parts.length, 3, 'JWT must have 3 parts: header.claims.signature');
  const [headerB64, claimsB64, sigB64] = parts;

  // 3. Verify decoded claims
  const header = JSON.parse(Buffer.from(headerB64, 'base64url').toString('utf8'));
  assert.equal(header.alg, 'RS256');
  assert.equal(header.typ, 'JWT');

  const claims = JSON.parse(Buffer.from(claimsB64, 'base64url').toString('utf8'));
  assert.equal(claims.iss, testEmail);
  assert.equal(claims.sub, testEmail);
  assert.equal(claims.aud, 'https://oauth2.googleapis.com/token');
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/datastore');
  assert.ok(typeof claims.iat === 'number');
  assert.equal(claims.exp, claims.iat + 3600);

  // 4. Verify cryptographic signature using standard RS256 verifier with the public key
  const signingInput = `${headerB64}.${claimsB64}`;
  const verifier = crypto.createVerify('RSA-SHA256');
  verifier.update(signingInput);
  const isSignatureValid = verifier.verify(publicKey, Buffer.from(sigB64, 'base64url'));
  assert.equal(isSignatureValid, true, 'Cryptographic RS256 signature must be verified by public key');
});

test('Config: Base URL and token URL overridable by environment variables', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { getFirestoreBaseUrl, getOAuthTokenUrl } = edgeModule;

  const originalBase = process.env.FIRESTORE_BASE_URL;
  const originalEmu = process.env.FIRESTORE_EMULATOR_HOST;
  const originalToken = process.env.GOOGLE_OAUTH_TOKEN_URL;

  try {
    // 1. Defaults
    delete process.env.FIRESTORE_BASE_URL;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.GOOGLE_OAUTH_TOKEN_URL;
    assert.equal(getFirestoreBaseUrl(), 'https://firestore.googleapis.com/v1');
    assert.equal(getOAuthTokenUrl(), 'https://oauth2.googleapis.com/token');

    // 2. Base URL override
    process.env.FIRESTORE_BASE_URL = 'http://localhost:8080/v1';
    assert.equal(getFirestoreBaseUrl(), 'http://localhost:8080/v1');

    // 3. Emulator host override
    delete process.env.FIRESTORE_BASE_URL;
    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
    assert.equal(getFirestoreBaseUrl(), 'http://127.0.0.1:8085/v1');

    // 4. Token URL override
    process.env.GOOGLE_OAUTH_TOKEN_URL = 'http://localhost:9090/token';
    assert.equal(getOAuthTokenUrl(), 'http://localhost:9090/token');
  } finally {
    if (originalBase) process.env.FIRESTORE_BASE_URL = originalBase;
    else delete process.env.FIRESTORE_BASE_URL;
    if (originalEmu) process.env.FIRESTORE_EMULATOR_HOST = originalEmu;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
    if (originalToken) process.env.GOOGLE_OAUTH_TOKEN_URL = originalToken;
    else delete process.env.GOOGLE_OAUTH_TOKEN_URL;
  }
});

test('Emulator Protocol: Verified against local HTTP server simulating Firestore REST API', async () => {
  const http = require('node:http');
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let receivedUrl = '';
  let receivedMethod = '';
  let receivedBody = '';
  let responseStatus = 200;

  // Spin up lightweight local mock server simulating Firestore emulator
  const server = http.createServer((req, res) => {
    receivedUrl = req.url;
    receivedMethod = req.method;
    let chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      receivedBody = Buffer.concat(chunks).toString('utf8');
      if (responseStatus === 404) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { code: 404, message: 'Document not found' } }));
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ name: 'projects/p/databases/(default)/documents/appointments/apt-emu-1' }));
      }
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;

  const originalBase = process.env.FIRESTORE_BASE_URL;
  process.env.FIRESTORE_BASE_URL = `http://127.0.0.1:${port}/v1`;

  try {
    // 1. Success case through emulator URL
    responseStatus = 200;
    const reqOk = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'test-secret',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-emu-1',
          doctor_status: 'cancelled',
          cancellation_reason: 'Doctor emergency',
        },
      }),
    });

    // Provide a writer that calls the mock emulator URL with currentDocument.exists=true
    const emulatorWriter = async (aptId, fields) => {
      const url = `${process.env.FIRESTORE_BASE_URL}/projects/test-proj/databases/(default)/documents/appointments/${aptId}?currentDocument.exists=true`;
      const res = await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields }),
      });
      if (!res.ok) {
        const err = new Error(`Emulator failed (${res.status})`);
        err.status = res.status;
        err.code = res.status === 404 ? 'NOT_FOUND' : 'INTERNAL';
        throw err;
      }
    };

    const resOk = await handleSyncToFirestore(reqOk, {
      expectedSecret: 'test-secret',
      firestoreWriter: emulatorWriter,
    });

    assert.equal(resOk.status, 200);
    assert.equal(receivedMethod, 'PATCH');
    assert.ok(receivedUrl.includes('currentDocument.exists=true'));
    assert.ok(receivedUrl.includes('apt-emu-1'));

    // 2. Precondition 404 through emulator URL
    responseStatus = 404;
    const reqNotFound = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'test-secret',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-emu-missing',
          doctor_status: 'cancelled',
        },
      }),
    });

    const resNotFound = await handleSyncToFirestore(reqNotFound, {
      expectedSecret: 'test-secret',
      firestoreWriter: emulatorWriter,
    });

    assert.equal(resNotFound.status, 200);
    const notFoundBody = await resNotFound.json();
    assert.equal(notFoundBody.skipped, 'not_found');
    assert.ok(notFoundBody.appointmentIdHash);
  } finally {
    if (originalBase) process.env.FIRESTORE_BASE_URL = originalBase;
    else delete process.env.FIRESTORE_BASE_URL;
    server.close();
  }
});

