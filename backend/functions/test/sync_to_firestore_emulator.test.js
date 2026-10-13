'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

// Dynamically import the ES module under test
async function loadEdgeFunction() {
  const edgeModule = await import('../../supabase/functions/sync-to-firestore/index.ts');
  return edgeModule.handleSyncToFirestore;
}

test('Real Firestore Emulator: PATCH of existing doc succeeds and updates fields with precondition', async () => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    // If running outside emulator test script, skip
    console.log('Skipping real emulator test: FIRESTORE_EMULATOR_HOST not set');
    return;
  }

  const projectId = 'demo-doctornect-test';
  const aptId = 'apt-real-doc-1';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/appointments/${aptId}`;

  // 1. Setup: Create an existing appointment doc in the emulator with admin token (Bearer owner)
  const setupRes = await fetch(`${baseUrl}?updateMask.fieldPaths=doctorStatus&updateMask.fieldPaths=patientStatus`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer owner',
    },
    body: JSON.stringify({
      fields: {
        doctorStatus: { stringValue: 'pendingRequest' },
        patientStatus: { stringValue: 'confirmed' },
      },
    }),
  });
  assert.equal(setupRes.status, 200, 'Setup of initial appointment doc in emulator must succeed');

  // 2. Call Edge Function with real defaultFirestoreWriter against the emulator
  const handleSyncToFirestore = await loadEdgeFunction();

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'emulator-test-secret',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: aptId,
        doctor_status: 'confirmed',
        patient_status: 'confirmed',
      },
      old_record: {
        appointment_id: aptId,
        doctor_status: 'pendingRequest',
        patient_status: 'confirmed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'emulator-test-secret',
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(body.appointmentId, aptId);
  assert.equal(body.syncedBy, 'supabase_bridge');

  // 3. Verify in the real emulator that the document was updated
  const getRes = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(getRes.status, 200);
  const doc = await getRes.json();
  assert.equal(doc.fields.doctorStatus.stringValue, 'confirmed');
  assert.equal(doc.fields.syncedBy.stringValue, 'supabase_bridge');
});

test('Real Firestore Emulator: PATCH of missing doc returns 404, triggers skip and creates no document', async () => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    console.log('Skipping real emulator test: FIRESTORE_EMULATOR_HOST not set');
    return;
  }

  const projectId = 'demo-doctornect-test';
  const missingAptId = 'apt-real-missing-doc-9999';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/appointments/${missingAptId}`;

  // Ensure document does NOT exist initially
  const initialCheck = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(initialCheck.status, 404, 'Document must not exist before test');

  // Call Edge Function with real defaultFirestoreWriter against the emulator
  const handleSyncToFirestore = await loadEdgeFunction();

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'emulator-test-secret',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: missingAptId,
        patient_status: 'cancelled',
        cancellation_reason: 'Patient changed mind',
        cancelled_by: 'patient',
      },
      old_record: {
        appointment_id: missingAptId,
        patient_status: 'confirmed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'emulator-test-secret',
  });

  assert.equal(res.status, 200, 'Edge function must return 200 to halt webhook retries on 404');
  const body = await res.json();
  assert.equal(body.skipped, 'not_found');
  assert.equal(body.reason, 'firestore_doc_missing');
  assert.ok(body.appointmentIdHash);

  // Verify in the real emulator that currentDocument.exists=true prevented creation of an orphaned doc
  const finalCheck = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(finalCheck.status, 404, 'Missing document must NOT be created by PATCH when precondition is set');

  // Verify that durable dead letter was created in Firestore syncDeadLetters collection
  const deadLettersRes = await fetch(`http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/syncDeadLetters`, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(deadLettersRes.status, 200);
  const deadLettersList = await deadLettersRes.json();
  const matchingDl = (deadLettersList.documents || []).find((d) =>
    d.fields.entityId?.stringValue === missingAptId
  );
  assert.ok(matchingDl, 'Must find dead letter in syncDeadLetters collection');
  assert.equal(matchingDl.fields.reason?.stringValue, 'firestore_doc_missing');
  assert.equal(matchingDl.fields.direction?.stringValue, 'supabase_to_firestore');
  assert.equal(matchingDl.fields.entityType?.stringValue, 'appointments');
  // Confirm NO patient free text stored in dead letter
  const changedFieldValues = (matchingDl.fields.changedFields?.arrayValue?.values || []).map((v) => v.stringValue);
  assert.ok(changedFieldValues.includes('cancellationReason') || changedFieldValues.includes('wasCancelled'));
  assert.ok(!changedFieldValues.includes('Patient changed mind'), 'Must not store patient-entered text');
});

test('Real Firestore Emulator: Terminal document update is skipped and records syncDeadLetters dead letter', async () => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    console.log('Skipping real emulator test: FIRESTORE_EMULATOR_HOST not set');
    return;
  }

  const projectId = 'demo-doctornect-test';
  const terminalAptId = 'apt-real-terminal-completed-1';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/appointments/${terminalAptId}`;

  // 1. Setup: Create an existing appointment doc in terminal state ('completed')
  const setupRes = await fetch(`${baseUrl}?updateMask.fieldPaths=doctorStatus&updateMask.fieldPaths=patientStatus`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer owner',
    },
    body: JSON.stringify({
      fields: {
        doctorStatus: { stringValue: 'completed' },
        patientStatus: { stringValue: 'completed' },
      },
    }),
  });
  assert.equal(setupRes.status, 200, 'Setup of completed appointment in emulator must succeed');

  // 2. Call Edge Function with incoming cancellation attempt
  const handleSyncToFirestore = await loadEdgeFunction();

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'emulator-test-secret',
    },
    body: JSON.stringify({
      type: 'UPDATE',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: terminalAptId,
        doctor_status: 'cancelled',
        cancellation_reason: 'Doctor emergency attempt after completion',
      },
      old_record: {
        appointment_id: terminalAptId,
        doctor_status: 'completed',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'emulator-test-secret',
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.skipped, 'terminal_state');
  assert.equal(body.reason, 'terminal_state');
  assert.equal(body.currentStatus, 'completed');

  // 3. Verify in emulator that document status was NOT modified
  const getRes = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(getRes.status, 200);
  const doc = await getRes.json();
  assert.equal(doc.fields.doctorStatus.stringValue, 'completed', 'Terminal state must not be overwritten');

  // 4. Verify durable dead letter created in syncDeadLetters
  const deadLettersRes = await fetch(`http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/syncDeadLetters`, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(deadLettersRes.status, 200);
  const deadLettersList = await deadLettersRes.json();
  const matchingDl = (deadLettersList.documents || []).find((d) =>
    d.fields.entityId?.stringValue === terminalAptId
  );
  assert.ok(matchingDl, 'Must find dead letter in syncDeadLetters collection for terminal-state skip');
  assert.equal(matchingDl.fields.reason?.stringValue, 'terminal_state');
  assert.equal(matchingDl.fields.direction?.stringValue, 'supabase_to_firestore');
  assert.equal(matchingDl.fields.entityType?.stringValue, 'appointments');

  const changedFieldValues = (matchingDl.fields.changedFields?.arrayValue?.values || []).map((v) => v.stringValue);
  assert.ok(changedFieldValues.includes('doctorStatus'));
  assert.ok(changedFieldValues.includes('cancellationReason'));
  assert.ok(!changedFieldValues.includes('Doctor emergency attempt after completion'), 'Must not store patient-entered text');
});

test('Real Firestore Emulator: INSERT creates appointment doc when absent and writes Step 0 fields', async () => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    console.log('Skipping real emulator test: FIRESTORE_EMULATOR_HOST not set');
    return;
  }

  const projectId = 'demo-doctornect-test';
  const newAptId = 'apt-emu-insert-new-001';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/appointments/${newAptId}`;

  // Ensure document does not exist prior to test
  await fetch(baseUrl, {
    method: 'DELETE',
    headers: { 'Authorization': 'Bearer owner' },
  });

  const handleSyncToFirestore = await loadEdgeFunction();

  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'emulator-test-secret',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: newAptId,
        doctor_id: 'doc-emu-1',
        patient_id: 'pat-emu-1',
        doctor_name: 'Dr. Jane Roe',
        specialization: 'Neurology',
        patient_name: 'Patient Smith',
        patient_age: 45,
        patient_gender: 'Female',
        date_time: '2026-10-20T11:00:00Z',
        slot_label: '11:00 - 11:30',
        token_number: 3,
        visit_type: 'newVisit',
        patient_status: 'confirmed',
        doctor_status: 'pendingRequest',
        chief_complaints: ['Headache', 'Dizziness'],
        symptoms: ['Migraine'],
        observations: ['Normal reflexes'],
        sync_origin: 'patient_supabase',
      },
    }),
  });

  const res = await handleSyncToFirestore(req, {
    expectedSecret: 'emulator-test-secret',
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.success, true);
  assert.equal(body.action, 'created');
  assert.equal(body.appointmentId, newAptId);
  assert.equal(body.syncedBy, 'supabase_bridge');

  // Verify document in emulator
  const getRes = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(getRes.status, 200);
  const doc = await getRes.json();
  assert.equal(doc.fields.appointmentId.stringValue, newAptId);
  assert.equal(doc.fields.doctorName.stringValue, 'Dr. Jane Roe');
  assert.equal(doc.fields.patientAge.integerValue, '45');
  assert.equal(doc.fields.syncedBy.stringValue, 'supabase_bridge');
  assert.deepEqual(doc.fields.chiefComplaints.arrayValue.values, [
    { stringValue: 'Headache' },
    { stringValue: 'Dizziness' },
  ]);
});

test('Real Firestore Emulator: INSERT returns 200 { ignored: "already_exists" } and does not overwrite existing doc', async () => {
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    console.log('Skipping real emulator test: FIRESTORE_EMULATOR_HOST not set');
    return;
  }

  const projectId = 'demo-doctornect-test';
  const existingAptId = 'apt-emu-insert-already-exists-002';
  const baseUrl = `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents/appointments/${existingAptId}`;

  // 1. Pre-create document in emulator
  const setupRes = await fetch(`${baseUrl}?updateMask.fieldPaths=doctorName&updateMask.fieldPaths=patientStatus`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer owner',
    },
    body: JSON.stringify({
      fields: {
        doctorName: { stringValue: 'Original Doctor' },
        patientStatus: { stringValue: 'pending' },
      },
    }),
  });
  assert.equal(setupRes.status, 200);

  const handleSyncToFirestore = await loadEdgeFunction();

  // 2. Attempt INSERT of existing appointment
  const req = new Request('https://edge.supabase.com/sync-to-firestore', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-webhook-secret': 'emulator-test-secret',
    },
    body: JSON.stringify({
      type: 'INSERT',
      table: 'appointments',
      schema: 'public',
      record: {
        appointment_id: existingAptId,
        doctor_id: 'doc-emu-2',
        patient_id: 'pat-emu-2',
        doctor_name: 'Overwriting Doctor Attempt',
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
    expectedSecret: 'emulator-test-secret',
  });

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ignored, 'already_exists');
  assert.equal(body.appointmentId, existingAptId);
  assert.ok(body.reason.includes('already exists in Firestore; INSERT did not overwrite'));

  // 3. Verify original document was NOT overwritten
  const getRes = await fetch(baseUrl, {
    headers: { 'Authorization': 'Bearer owner' },
  });
  assert.equal(getRes.status, 200);
  const doc = await getRes.json();
  assert.equal(doc.fields.doctorName.stringValue, 'Original Doctor', 'Must preserve original doc untouched');
  assert.equal(doc.fields.patientStatus.stringValue, 'pending');
});
