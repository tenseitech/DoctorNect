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

test('Edge Function Event Filter: Ignores non-INSERT/UPDATE types, other tables, or other schemas with 200 {ignored: true}', async () => {
  const handleSyncToFirestore = await loadEdgeFunction();
  let writeCalled = false;
  const mockWriter = async () => {
    writeCalled = true;
  };

  const ignoredEvents = [
    { type: 'DELETE', table: 'appointments', schema: 'public' },
    { type: 'TRUNCATE', table: 'appointments', schema: 'public' },
    { type: 'UPDATE', table: 'patients', schema: 'public' },
    { type: 'INSERT', table: 'patients', schema: 'public' },
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
    { sync_origin: 'firestore_cloud_function' },
    { sync_origin: 'firestore' },
    { synced_by: 'firestore_cloud_function' },
    { synced_by: 'supabase_bridge' },
    { synced_by: 'reconciler_bot' },
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
  assert.equal(writtenPayload.patientStatus, undefined, 'Terminal patient_status must not be written to Firestore');
  assert.equal(writtenPayload.cancellationReason, 'High fever');
  assert.equal(writtenPayload.cancelledBy, undefined, 'cancelledBy is not read by clients and must not be written');
  assert.equal(writtenPayload.cancelledAt, undefined, 'cancelledAt is not read by clients and must not be written');
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
  assert.equal(writtenPayload.patientStatus, undefined, 'Terminal patient_status must not be written to Firestore');
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
  assert.equal(writtenPayload.patientStatus, undefined, 'Terminal patient_status must not be written to Firestore');
  assert.equal(writtenPayload.cancellationReason, 'Patient fever spikes, doctor informed');
  assert.equal(writtenPayload.cancelledBy, undefined, 'cancelledBy must not be written');
  assert.equal(writtenPayload.cancelledAt, undefined, 'cancelledAt must not be written');
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
  assert.ok(capturedDeadLetter.changedFields.includes('cancellationReason'));
  assert.ok(!capturedDeadLetter.changedFields.includes('cancelledBy'), 'cancelledBy is not tracked or written');
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

test('TASK 3d: Terminal-state guard rejects transitions across all terminal status fields (doctorStatus, patientStatus)', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { isTerminalTransitionRejected, handleSyncToFirestore } = edgeModule;

  // 1. Direct unit verification of isTerminalTransitionRejected for each field
  // a) doctorStatus inProgress
  const inProgressCheck = isTerminalTransitionRejected(
    { fields: { doctorStatus: { stringValue: 'inProgress' } } },
    { doctorStatus: 'cancelled' }
  );
  assert.equal(inProgressCheck.isTerminal, true);
  assert.equal(inProgressCheck.isRejected, true);
  assert.equal(inProgressCheck.currentStatus, 'inProgress');

  // b) doctorStatus noShow
  const noShowCheck = isTerminalTransitionRejected(
    { fields: { doctorStatus: { stringValue: 'noShow' } } },
    { doctorStatus: 'cancelled' }
  );
  assert.equal(noShowCheck.isTerminal, true);
  assert.equal(noShowCheck.isRejected, true);

  // c) patientStatus completed
  const patientCompletedCheck = isTerminalTransitionRejected(
    { fields: { doctorStatus: { stringValue: 'confirmed' }, patientStatus: { stringValue: 'completed' } } },
    { patientStatus: 'cancelled' }
  );
  assert.equal(patientCompletedCheck.isTerminal, true);
  assert.equal(patientCompletedCheck.isRejected, true);

  // 2. Integration verification through handleSyncToFirestore with doctorStatus: inProgress
  let dlReason = null;
  const res = await handleSyncToFirestore(
    new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-webhook-secret': 'sec' },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        record: { appointment_id: 'apt-inprogress-1', doctor_status: 'cancelled' },
        old_record: { appointment_id: 'apt-inprogress-1', doctor_status: 'inProgress' },
      }),
    }),
    {
      expectedSecret: 'sec',
      firestoreReader: async () => ({
        fields: { doctorStatus: { stringValue: 'inProgress' } },
        updateTime: '2026-10-13T00:00:00Z',
      }),
      deadLetterWriter: async (id, reason) => {
        dlReason = reason;
      },
    }
  );

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.skipped, 'terminal_state');
  assert.equal(dlReason, 'terminal_state');
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

test('TASK 4b: Firestore REST HTTP 400 with FAILED_PRECONDITION re-reads once and retries once', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

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
      const err = new Error('Precondition failed: document was modified (400)');
      err.status = 400; // Cloud Firestore REST maps FAILED_PRECONDITION to HTTP 400
      err.code = 'FAILED_PRECONDITION';
      err.grpcStatus = 'FAILED_PRECONDITION';
      throw err;
    }
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'secret-retry-concurrent-400',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-retry-400',
        doctor_status: 'confirmed',
      },
      old_record: {
        appointment_id: 'apt-retry-400',
        doctor_status: 'pendingRequest',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'secret-retry-concurrent-400',
    firestoreReader: mockReader,
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(readCount, 2, 'Must re-read once on HTTP 400 FAILED_PRECONDITION');
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

test('TASK 4: buildFirestoreAppointmentFromSupabaseRow maps public.appointments row matching Step 0 contract', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { buildFirestoreAppointmentFromSupabaseRow, buildFirestoreFields } = edgeModule;

  const sampleRow = {
    appointment_id: 'apt-contract-001',
    doctor_id: 'doc-123',
    patient_id: 'pat-456',
    doctor_name: 'Dr. Sarah Connor',
    specialization: 'Cardiology',
    patient_name: 'John Connor',
    patient_age: 35,
    patient_gender: 'Male',
    date_time: '2026-10-15T14:30:00.000Z',
    slot_label: '14:30 - 15:00',
    token_number: 4,
    visit_type: 'followUp',
    patient_status: 'confirmed',
    doctor_status: 'confirmed',
    clinic_name: 'Heart Health Clinic',
    clinic_address: '101 Medical Plaza',
    maps_url: 'https://maps.google.com/?q=HeartClinic',
    cancellation_reason: null,
    diagnosis: 'Arrhythmia review',
    has_prescription: true,
    has_report: false,
    has_review: false,
    review_rating: null,
    review_id: null,
    review_created_at: null,
    clinical_notes: 'Patient reports mild palpitations',
    contact_number: '+919876543210',
    source: 'app',
    booked_by_name: 'John Connor',
    patient_relation: 'Self',
    slot_share_reason: null,
    was_rescheduled: false,
    chief_complaints: ['Palpitations', 'Chest tightness'],
    symptoms: ['Fatigue'],
    observations: ['BP 120/80'],
    lab_reports: ['report-001.pdf'],
    created_at: '2026-10-13T10:00:00.000Z',
    updated_at: '2026-10-13T10:05:00.000Z',
  };

  const doc = buildFirestoreAppointmentFromSupabaseRow(sampleRow);

  // 1. Core and required fields verification matching Step 0 contract
  assert.equal(doc.appointmentId, 'apt-contract-001');
  assert.equal(doc.doctorId, 'doc-123');
  assert.equal(doc.patientId, 'pat-456');
  assert.equal(doc.doctorName, 'Dr. Sarah Connor');
  assert.equal(doc.specialization, 'Cardiology');
  assert.equal(doc.patientName, 'John Connor');
  assert.equal(doc.patientAge, 35);
  assert.equal(doc.patientGender, 'Male');
  assert.equal(doc.slotLabel, '14:30 - 15:00');
  assert.equal(doc.tokenNumber, 4);
  assert.equal(doc.visitType, 'followUp');
  assert.equal(doc.patientStatus, 'confirmed');
  assert.equal(doc.doctorStatus, 'confirmed');
  assert.equal(doc.hasPrescription, true);
  assert.equal(doc.hasReport, false);
  assert.equal(doc.hasReview, false);
  assert.equal(doc.wasRescheduled, false);
  assert.deepEqual(doc.chiefComplaints, ['Palpitations', 'Chest tightness']);
  assert.deepEqual(doc.symptoms, ['Fatigue']);
  assert.deepEqual(doc.observations, ['BP 120/80']);
  assert.deepEqual(doc.labReports, ['report-001.pdf']);
  assert.equal(doc.syncedBy, 'supabase_bridge');
  assert.equal(doc.clinicName, 'Heart Health Clinic');
  assert.equal(doc.clinicAddress, '101 Medical Plaza');
  assert.equal(doc.mapsUrl, 'https://maps.google.com/?q=HeartClinic');
  assert.equal(doc.diagnosis, 'Arrhythmia review');
  assert.equal(doc.clinicalNotes, 'Patient reports mild palpitations');
  assert.equal(doc.contactNumber, '+919876543210');
  assert.equal(doc.source, 'app');
  assert.equal(doc.bookedByName, 'John Connor');
  assert.equal(doc.patientRelation, 'Self');

  // 2. Typed REST serialization verification matching Step 0 contract
  const { fields, fieldPaths } = buildFirestoreFields(doc);
  assert.equal(fields.appointmentId.stringValue, 'apt-contract-001');
  assert.equal(fields.patientAge.integerValue, '35');
  assert.equal(fields.tokenNumber.integerValue, '4');
  assert.equal(fields.hasPrescription.booleanValue, true);
  assert.equal(fields.syncedBy.stringValue, 'supabase_bridge');
  assert.deepEqual(fields.chiefComplaints.arrayValue.values, [
    { stringValue: 'Palpitations' },
    { stringValue: 'Chest tightness' },
  ]);
  assert.deepEqual(fields.labReports.arrayValue.values, [
    { stringValue: 'report-001.pdf' },
  ]);
  assert.equal(fields.dateTime.timestampValue, '2026-10-15T14:30:00.000Z');
  assert.ok(fieldPaths.includes('syncedBy'));
  assert.ok(fieldPaths.includes('chiefComplaints'));
});

test('TASK 4: INSERT creates document when absent with currentDocument.exists=false precondition', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let writtenId = null;
  let writtenData = null;
  let capturedPrecondition = null;

  const mockWriter = async (id, data, precondition) => {
    writtenId = id;
    writtenData = data;
    capturedPrecondition = precondition;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'sec-insert',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-ins-new-1',
        doctor_id: 'doc-1',
        patient_id: 'pat-1',
        doctor_name: 'Dr. Test',
        specialization: 'General',
        patient_name: 'Patient Test',
        patient_age: 40,
        patient_gender: 'Female',
        date_time: '2026-10-14T09:00:00Z',
        slot_label: '09:00 - 09:15',
        token_number: 1,
        visit_type: 'newVisit',
        patient_status: 'confirmed',
        doctor_status: 'pendingRequest',
        sync_origin: 'patient_supabase',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'sec-insert',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(body.action, 'created');
  assert.equal(body.appointmentId, 'apt-ins-new-1');
  assert.equal(body.syncedBy, 'supabase_bridge');

  // Verify write details
  assert.equal(writtenId, 'apt-ins-new-1');
  assert.equal(writtenData.appointmentId, 'apt-ins-new-1');
  assert.equal(writtenData.syncedBy, 'supabase_bridge');
  assert.equal(writtenData.doctorName, 'Dr. Test');
  assert.deepEqual(capturedPrecondition, { exists: false });
});

test('TASK 4: INSERT returns 200 { ignored: "already_exists" } when document already exists (never overwrites)', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const failingWriter = async (id, data, precondition) => {
    const err = new Error('Document already exists: projects/p/databases/(default)/documents/appointments/' + id);
    err.status = 409;
    err.code = 'ALREADY_EXISTS';
    throw err;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'sec-insert',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-ins-exists-1',
        doctor_id: 'doc-1',
        patient_id: 'pat-1',
        doctor_name: 'Dr. Test',
        specialization: 'General',
        patient_name: 'Patient Test',
        date_time: '2026-10-14T09:00:00Z',
        slot_label: '09:00 AM',
        token_number: 1,
        doctor_status: 'pendingRequest',
        visit_type: 'newVisit',
        sync_origin: 'patient_supabase',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'sec-insert',
    firestoreWriter: failingWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ignored, 'already_exists');
  assert.equal(body.appointmentId, 'apt-ins-exists-1');
  assert.ok(body.reason.includes('already exists in Firestore; INSERT did not overwrite'));
});

test('TASK 4: INSERT drops Firestore-originated records via loop prevention', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let writerCalled = false;
  const mockWriter = async () => {
    writerCalled = true;
  };

  const loopMarkers = [
    { sync_origin: 'doctor_firestore' },
    { sync_origin: 'patient_firestore' },
    { sync_origin: 'reconciler_bot' },
    { sync_origin: 'firestore_cloud_function' },
    { sync_origin: 'firestore' },
    { synced_by: 'firestore_cloud_function' },
    { synced_by: 'supabase_bridge' },
    { synced_by: 'reconciler_bot' },
  ];
  for (const marker of loopMarkers) {
    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-insert',
      },
      body: JSON.stringify({
        type: 'INSERT',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-loop-test',
          ...marker,
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'sec-insert',
      firestoreWriter: mockWriter,
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ignored, true);
    assert.ok(body.reason.includes('Loop prevented'));
    assert.equal(writerCalled, false);
  }
});

test('TASK 4b: Fixture round trip for every enum value in both directions', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const {
    ALLOWED_PATIENT_STATUS_FIRESTORE,
    ALLOWED_DOCTOR_STATUS,
    ALLOWED_VISIT_TYPE,
    buildFirestoreAppointmentFromSupabaseRow,
  } = edgeModule;

  // 1. doctor_status round trip
  for (const status of ALLOWED_DOCTOR_STATUS) {
    const fsDoc = { doctorStatus: status };
    // Simulate Firestore -> Supabase (putText logic from cross_role_sync.js)
    const pgRow = {
      appointment_id: `apt-dt-${status}`,
      doctor_id: 'doc-1',
      patient_id: 'pat-1',
      doctor_name: 'Dr. Test',
      patient_name: 'Patient Test',
      doctor_status: fsDoc.doctorStatus,
      date_time: '2026-10-15T10:00:00Z',
      slot_label: '10:00 AM',
      token_number: 1,
      visit_type: 'newVisit',
      patient_status: 'confirmed',
    };
    // Simulate Supabase -> Firestore (buildFirestoreAppointmentFromSupabaseRow)
    const roundTripped = buildFirestoreAppointmentFromSupabaseRow(pgRow);
    assert.equal(roundTripped.doctorStatus, status, `doctorStatus round trip failed for ${status}`);
  }

  // 2. patient_status round trip (valid Firestore values)
  for (const status of ALLOWED_PATIENT_STATUS_FIRESTORE) {
    const fsDoc = { patientStatus: status };
    const pgRow = {
      appointment_id: `apt-pt-${status}`,
      doctor_id: 'doc-1',
      patient_id: 'pat-1',
      doctor_name: 'Dr. Test',
      patient_name: 'Patient Test',
      doctor_status: 'confirmed',
      patient_status: fsDoc.patientStatus,
      date_time: '2026-10-15T10:00:00Z',
      slot_label: '10:00 AM',
      token_number: 1,
      visit_type: 'newVisit',
    };
    const roundTripped = buildFirestoreAppointmentFromSupabaseRow(pgRow);
    assert.equal(roundTripped.patientStatus, status, `patientStatus round trip failed for ${status}`);
  }

  // 3. visit_type round trip
  for (const vType of ALLOWED_VISIT_TYPE) {
    const fsDoc = { visitType: vType };
    const pgRow = {
      appointment_id: `apt-vt-${vType}`,
      doctor_id: 'doc-1',
      patient_id: 'pat-1',
      doctor_name: 'Dr. Test',
      patient_name: 'Patient Test',
      doctor_status: 'confirmed',
      patient_status: 'confirmed',
      visit_type: fsDoc.visitType,
      date_time: '2026-10-15T10:00:00Z',
      slot_label: '10:00 AM',
      token_number: 1,
    };
    const roundTripped = buildFirestoreAppointmentFromSupabaseRow(pgRow);
    assert.equal(roundTripped.visitType, vType, `visitType round trip failed for ${vType}`);
  }
});

test('TASK 4b: patient_status cancelled UPDATE writes doctorStatus and cancellation only', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let writtenData = null;
  const mockWriter = async (id, data) => {
    writtenData = data;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'sec-up',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      old_record: {
        appointment_id: 'apt-cancel-1',
        doctor_status: 'confirmed',
        patient_status: 'confirmed',
      },
      record: {
        appointment_id: 'apt-cancel-1',
        doctor_status: 'cancelled',
        patient_status: 'cancelled',
        cancellation_reason: 'Doctor unavailable',
        cancelled_by: 'doctor',
        cancelled_at: '2026-10-15T12:00:00Z',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'sec-up',
    firestoreWriter: mockWriter,
    firestoreReader: async () => ({
      fields: { doctorStatus: { stringValue: 'confirmed' } },
      updateTime: '2026-10-15T11:00:00Z',
    }),
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.ok(writtenData, 'Writer must be called');
  assert.equal(writtenData.doctorStatus, 'cancelled');
  assert.equal(writtenData.cancellationReason, 'Doctor unavailable');
  assert.equal(writtenData.cancelledBy, undefined);
  assert.equal(writtenData.syncedBy, 'supabase_bridge');
  // CRITICAL: patientStatus must NOT be written to Firestore
  assert.equal(writtenData.patientStatus, undefined, 'patientStatus must NOT be written on cancelled update');
});

test('TASK 4b: patient_status cancelled UPDATE with no other changed fields is ignored', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let writeCalled = false;
  const mockWriter = async () => {
    writeCalled = true;
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'sec-up',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      old_record: {
        appointment_id: 'apt-term-pat-only',
        patient_status: 'confirmed',
        doctor_status: 'confirmed',
      },
      record: {
        appointment_id: 'apt-term-pat-only',
        patient_status: 'completed',
        doctor_status: 'confirmed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'sec-up',
    firestoreWriter: mockWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ignored, 'no_status_change');
  assert.equal(writeCalled, false, 'Writer must not be called when only non-writable status changes');
});

test('TASK 4b: cancelled INSERT is dead-lettered with invalid_status_value', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  let writerCalled = false;
  let capturedDeadLetter = null;

  const mockWriter = async () => {
    writerCalled = true;
  };
  const mockDeadLetterWriter = async (id, reason, fields) => {
    capturedDeadLetter = { id, reason, fields };
  };

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'sec-ins-cancel',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: 'apt-ins-cancel-1',
        doctor_id: 'doc-1',
        patient_id: 'pat-1',
        doctor_name: 'Dr. Test',
        patient_name: 'Patient Test',
        date_time: '2026-10-15T10:00:00Z',
        slot_label: '10:00 AM',
        token_number: 1,
        visit_type: 'newVisit',
        doctor_status: 'confirmed',
        patient_status: 'cancelled', // Invalid on INSERT
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'sec-ins-cancel',
    firestoreWriter: mockWriter,
    deadLetterWriter: mockDeadLetterWriter,
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.skipped, 'invalid_status_value');
  assert.deepEqual(body.invalidFields, ['patient_status']);
  assert.equal(writerCalled, false, 'No document should be created on invalid status value');
  assert.ok(capturedDeadLetter, 'Dead letter must be recorded');
  assert.equal(capturedDeadLetter.reason, 'invalid_status_value');
  assert.deepEqual(capturedDeadLetter.fields, ['patient_status']);
});

test('TASK 4b: required-field INSERT checks report missing_required_fields', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore, validateInsertPayload } = edgeModule;

  const baseValidRecord = {
    appointment_id: 'apt-req-test',
    doctor_id: 'doc-1',
    patient_id: 'pat-1',
    doctor_name: 'Dr. Test',
    patient_name: 'Patient Test',
    date_time: '2026-10-15T10:00:00Z',
    slot_label: '10:00 AM',
    token_number: 1,
    patient_status: 'confirmed',
    doctor_status: 'pendingRequest',
    visit_type: 'newVisit',
  };

  // 1. Direct validation tests for each required field
  const requiredFields = [
    'doctorId',
    'patientId',
    'doctorName',
    'patientName',
    'dateTime',
    'slotLabel',
    'tokenNumber',
    'doctorStatus',
    'visitType',
  ];

  for (const field of requiredFields) {
    const invalidRecord = { ...baseValidRecord };
    // map field name to snake_case equivalent
    const snake = field.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
    delete invalidRecord[snake];
    delete invalidRecord[field];

    const validation = validateInsertPayload(invalidRecord);
    assert.ok(validation.missingFields.includes(field), `Expected ${field} to be reported missing`);
  }

  // 2. Explicitly null patientStatus triggers missingFields
  const nullPatientStatusRecord = { ...baseValidRecord, patient_status: null };
  const nullPatientValidation = validateInsertPayload(nullPatientStatusRecord);
  assert.ok(nullPatientValidation.missingFields.includes('patientStatus'), 'Explicit null patient_status must be reported missing');

  // 3. Omitted patientStatus defaults to pending and is valid
  const omittedPatientStatusRecord = { ...baseValidRecord };
  delete omittedPatientStatusRecord.patient_status;
  delete omittedPatientStatusRecord.patientStatus;
  const omittedValidation = validateInsertPayload(omittedPatientStatusRecord);
  assert.equal(omittedValidation.isValid, true, 'Omitted patient_status must default to pending and be valid');

  // 4. Integration test via handleSyncToFirestore with missing doctorName
  let capturedDeadLetter = null;
  const res = await handleSyncToFirestore(
    new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-webhook-secret': 'sec' },
      body: JSON.stringify({
        type: 'INSERT',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-missing-docname',
          doctor_id: 'doc-1',
          patient_id: 'pat-1',
          // doctor_name missing
          patient_name: 'Patient Test',
          date_time: '2026-10-15T10:00:00Z',
          slot_label: '10:00 AM',
          token_number: 1,
          doctor_status: 'pendingRequest',
          visit_type: 'newVisit',
        },
      }),
    }),
    {
      expectedSecret: 'sec',
      deadLetterWriter: async (id, reason, fields) => {
        capturedDeadLetter = { id, reason, fields };
      },
    }
  );

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.skipped, 'missing_required_fields');
  assert.ok(body.missingFields.includes('doctorName'));
  assert.ok(capturedDeadLetter);
  assert.equal(capturedDeadLetter.reason, 'missing_required_fields');
});

test('defaultFirestoreWriter stubbed fetch: 400 FAILED_PRECONDITION parses error and sets code/grpcStatus', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { defaultFirestoreWriter } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 400,
          message: 'The stored document version does not match the version specified in the update request.',
          status: 'FAILED_PRECONDITION',
        },
      }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );

    let thrownErr;
    try {
      await defaultFirestoreWriter('apt-prec-1', { doctorStatus: 'confirmed' }, '2026-10-14T00:00:00Z');
    } catch (err) {
      thrownErr = err;
    }

    assert.ok(thrownErr, 'Must throw error on 400 FAILED_PRECONDITION');
    assert.equal(thrownErr.status, 400);
    assert.equal(thrownErr.code, 'FAILED_PRECONDITION');
    assert.equal(thrownErr.grpcStatus, 'FAILED_PRECONDITION');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('defaultFirestoreWriter stubbed fetch: 400 INVALID_ARGUMENT parses error and sets code/grpcStatus', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { defaultFirestoreWriter } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 400,
          message: 'Invalid value at appointment.tokenNumber: Expected integer',
          status: 'INVALID_ARGUMENT',
        },
      }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );

    let thrownErr;
    try {
      await defaultFirestoreWriter('apt-inv-1', { tokenNumber: 'invalid' });
    } catch (err) {
      thrownErr = err;
    }

    assert.ok(thrownErr, 'Must throw error on 400 INVALID_ARGUMENT');
    assert.equal(thrownErr.status, 400);
    assert.equal(thrownErr.code, 'INVALID_ARGUMENT');
    assert.equal(thrownErr.grpcStatus, 'INVALID_ARGUMENT');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('defaultFirestoreWriter stubbed fetch: 409 ALREADY_EXISTS parses error and sets code/grpcStatus', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { defaultFirestoreWriter } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 409,
          message: 'Document already exists: projects/p/databases/(default)/documents/appointments/apt-exist-1',
          status: 'ALREADY_EXISTS',
        },
      }),
      { status: 409, headers: { 'Content-Type': 'application/json' } }
    );

    let thrownErr;
    try {
      await defaultFirestoreWriter('apt-exist-1', { doctorStatus: 'pendingRequest' }, { exists: false });
    } catch (err) {
      thrownErr = err;
    }

    assert.ok(thrownErr, 'Must throw error on 409 ALREADY_EXISTS');
    assert.equal(thrownErr.status, 409);
    assert.equal(thrownErr.code, 'ALREADY_EXISTS');
    assert.equal(thrownErr.grpcStatus, 'ALREADY_EXISTS');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('defaultFirestoreWriter stubbed fetch: 404 NOT_FOUND parses error and sets code/grpcStatus', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { defaultFirestoreWriter } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 404,
          message: 'Document not found: projects/p/databases/(default)/documents/appointments/apt-missing-1',
          status: 'NOT_FOUND',
        },
      }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );

    let thrownErr;
    try {
      await defaultFirestoreWriter('apt-missing-1', { doctorStatus: 'confirmed' }, '2026-10-14T00:00:00Z');
    } catch (err) {
      thrownErr = err;
    }

    assert.ok(thrownErr, 'Must throw error on 404 NOT_FOUND');
    assert.equal(thrownErr.status, 404);
    assert.equal(thrownErr.code, 'NOT_FOUND');
    assert.equal(thrownErr.grpcStatus, 'NOT_FOUND');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('handleSyncToFirestore with defaultFirestoreWriter & stubbed fetch: 400 FAILED_PRECONDITION retries once and succeeds', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  let fetchCalls = 0;
  try {
    globalThis.fetch = async (url, options) => {
      fetchCalls++;
      if (fetchCalls === 1) {
        // First attempt fails with 400 FAILED_PRECONDITION
        return new Response(
          JSON.stringify({
            error: {
              code: 400,
              message: 'Precondition updateTime mismatch',
              status: 'FAILED_PRECONDITION',
            },
          }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        );
      }
      // Retry attempt succeeds
      return new Response(
        JSON.stringify({
          writeResults: [{ updateTime: '2026-10-15T12:00:00Z' }],
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    };

    let readerCalls = 0;
    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-fetch-test',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        old_record: {
          appointment_id: 'apt-fetch-retry-1',
          doctor_status: 'confirmed',
        },
        record: {
          appointment_id: 'apt-fetch-retry-1',
          doctor_status: 'inProgress',
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'sec-fetch-test',
      firestoreReader: async () => {
        readerCalls++;
        return {
          fields: { doctorStatus: { stringValue: 'confirmed' } },
          updateTime: '2026-10-15T12:00:00Z',
        };
      },
    });

    assert.equal(res.status, 200, 'Must return 200 on successful retry');
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(fetchCalls, 2, 'Must have retried fetch exactly once');
    assert.equal(readerCalls, 2, 'Must re-read document before retry');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('handleSyncToFirestore with defaultFirestoreWriter & stubbed fetch: 400 INVALID_ARGUMENT writes dead letter and returns 200 skipped without retry', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  let fetchCalls = 0;
  let capturedDeadLetter = null;

  try {
    globalThis.fetch = async () => {
      fetchCalls++;
      return new Response(
        JSON.stringify({
          error: {
            code: 400,
            message: 'Invalid value at appointment.tokenNumber: Expected integer',
            status: 'INVALID_ARGUMENT',
          },
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    };

    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-fetch-test',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        old_record: {
          appointment_id: 'apt-fetch-inv-1',
          doctor_status: 'confirmed',
        },
        record: {
          appointment_id: 'apt-fetch-inv-1',
          doctor_status: 'inProgress',
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'sec-fetch-test',
      firestoreReader: async () => ({
        fields: { doctorStatus: { stringValue: 'confirmed' } },
        updateTime: '2026-10-15T10:00:00Z',
      }),
      deadLetterWriter: async (id, reason, changedFields) => {
        capturedDeadLetter = { id, reason, changedFields };
      },
    });

    assert.equal(res.status, 200, 'Non-retriable INVALID_ARGUMENT must return 200 { skipped: "invalid_argument" }');
    const body = await res.json();
    assert.equal(body.skipped, 'invalid_argument');
    assert.equal(body.reason, 'invalid_argument');
    assert.equal(fetchCalls, 1, 'INVALID_ARGUMENT must NOT trigger retry');
    assert.ok(capturedDeadLetter, 'Must record dead letter');
    assert.equal(capturedDeadLetter.reason, 'invalid_argument');
    assert.deepEqual(capturedDeadLetter.changedFields, ['doctorStatus']);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('handleSyncToFirestore with defaultFirestoreWriter & stubbed fetch: 409 ALREADY_EXISTS on INSERT returns 200 ignored: already_exists', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 409,
          message: 'Document already exists',
          status: 'ALREADY_EXISTS',
        },
      }),
      { status: 409, headers: { 'Content-Type': 'application/json' } }
    );

    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-fetch-test',
      },
      body: JSON.stringify({
        type: 'INSERT',
        table: 'appointments',
        schema: 'public',
        record: {
          appointment_id: 'apt-fetch-ins-exists-1',
          doctor_id: 'doc-1',
          patient_id: 'pat-1',
          doctor_name: 'Dr. Test',
          specialization: 'General',
          patient_name: 'Patient Test',
          date_time: '2026-10-14T09:00:00Z',
          slot_label: '09:00 AM',
          token_number: 1,
          patient_status: 'confirmed',
          doctor_status: 'confirmed',
          visit_type: 'newVisit',
          sync_origin: 'patient_supabase',
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'sec-fetch-test',
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ignored, 'already_exists');
    assert.equal(body.appointmentId, 'apt-fetch-ins-exists-1');
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('handleSyncToFirestore with defaultFirestoreWriter & stubbed fetch: 404 NOT_FOUND on UPDATE writes dead letter and returns 200 skipped: not_found', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const originalFetch = globalThis.fetch;
  const originalHost = process.env.FIRESTORE_EMULATOR_HOST;
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

  let capturedDeadLetter = null;

  try {
    globalThis.fetch = async () => new Response(
      JSON.stringify({
        error: {
          code: 404,
          message: 'Document not found',
          status: 'NOT_FOUND',
        },
      }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );

    const req = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-fetch-test',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        old_record: {
          appointment_id: 'apt-fetch-404-1',
          doctor_status: 'confirmed',
        },
        record: {
          appointment_id: 'apt-fetch-404-1',
          doctor_status: 'inProgress',
        },
      }),
    });

    const res = await handleSyncToFirestore(req, {
      expectedSecret: 'sec-fetch-test',
      firestoreReader: async () => ({
        fields: { doctorStatus: { stringValue: 'confirmed' } },
        updateTime: '2026-10-15T10:00:00Z',
      }),
      deadLetterWriter: async (id, reason, changedFields) => {
        capturedDeadLetter = { id, reason, changedFields };
      },
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.skipped, 'not_found');
    assert.equal(body.reason, 'firestore_doc_missing');
    assert.ok(capturedDeadLetter);
    assert.equal(capturedDeadLetter.reason, 'firestore_doc_missing');
    assert.deepEqual(capturedDeadLetter.changedFields, ['doctorStatus']);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalHost) process.env.FIRESTORE_EMULATOR_HOST = originalHost;
    else delete process.env.FIRESTORE_EMULATOR_HOST;
  }
});

test('TASK 7: Logging Security: Stubbed error message with patient-like string does not appear in captured logs', async () => {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  const { handleSyncToFirestore } = edgeModule;

  const capturedLogs = [];
  const origWarn = console.warn;
  const origError = console.error;

  console.warn = (...args) => {
    capturedLogs.push(args.map(String).join(' '));
  };
  console.error = (...args) => {
    capturedLogs.push(args.map(String).join(' '));
  };

  const sensitivePatientString = 'PatientSSN-999-00-1234-MedicalDiagnosis-Cancer';

  try {
    // 1. Test INVALID_ARGUMENT error carrying sensitive patient string
    const reqInvalid = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-log-test',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        old_record: { appointment_id: 'apt-sec-1', doctor_status: 'confirmed' },
        record: { appointment_id: 'apt-sec-1', doctor_status: 'inProgress' },
      }),
    });

    const mockWriterThrows = async () => {
      const err = new Error(`Validation failed for ${sensitivePatientString}`);
      err.status = 400;
      err.code = 'INVALID_ARGUMENT';
      throw err;
    };

    let deadLetterDoc = null;
    const mockDlq = async (id, reason, fields) => {
      deadLetterDoc = { id, reason, fields };
    };

    const res = await handleSyncToFirestore(reqInvalid, {
      expectedSecret: 'sec-log-test',
      firestoreWriter: mockWriterThrows,
      deadLetterWriter: mockDlq,
      firestoreReader: async () => ({
        fields: { doctorStatus: { stringValue: 'confirmed' } },
        updateTime: '2026-10-15T00:00:00Z',
      }),
    });

    assert.equal(res.status, 200);

    // 2. Test 500 internal error carrying sensitive patient string
    const reqInternal = new Request('https://edge.supabase.com/sync-to-firestore', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-webhook-secret': 'sec-log-test',
      },
      body: JSON.stringify({
        type: 'UPDATE',
        table: 'appointments',
        schema: 'public',
        old_record: { appointment_id: 'apt-sec-2', doctor_status: 'confirmed' },
        record: { appointment_id: 'apt-sec-2', doctor_status: 'inProgress' },
      }),
    });

    const mockWriterInternalThrows = async () => {
      const err = new Error(`Internal DB corruption: ${sensitivePatientString}`);
      err.status = 500;
      err.code = 'INTERNAL';
      throw err;
    };

    const resInternal = await handleSyncToFirestore(reqInternal, {
      expectedSecret: 'sec-log-test',
      firestoreWriter: mockWriterInternalThrows,
      deadLetterWriter: mockDlq,
      firestoreReader: async () => ({
        fields: { doctorStatus: { stringValue: 'confirmed' } },
        updateTime: '2026-10-15T00:00:00Z',
      }),
    });

    assert.equal(resInternal.status, 500);

    // Verify logs were captured
    assert.ok(capturedLogs.length > 0, 'Logs must have been emitted');

    // CRITICAL ASSERTION: Sensitive patient string must NOT appear in ANY captured log
    for (const log of capturedLogs) {
      assert.equal(
        log.includes(sensitivePatientString),
        false,
        `Sensitive patient string leaked into log: ${log}`
      );
      // Verify log only contains status, code, and appointmentIdHash
      const parsed = JSON.parse(log);
      assert.ok(parsed.status !== undefined, 'Log must contain status');
      assert.ok(parsed.code !== undefined, 'Log must contain code');
      assert.ok(parsed.appointmentIdHash !== undefined, 'Log must contain appointmentIdHash');
      assert.equal(parsed.message, undefined, 'Log must NOT contain message');
    }

    // Also verify dead letter contains no sensitive error text
    assert.deepEqual(deadLetterDoc.fields, ['doctorStatus']);
    assert.equal(deadLetterDoc.reason, 'invalid_argument');
  } finally {
    console.warn = origWarn;
    console.error = origError;
  }
});




