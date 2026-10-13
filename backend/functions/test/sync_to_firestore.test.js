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
