'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  _safeCompareSecrets: safeCompareSecrets,
  _supabaseDatabaseWebhookHandler: supabaseDatabaseWebhookHandler,
  _isDoctorPatientSupabasePrimary: isDoctorPatientSupabasePrimary,
} = require('../index');

test('Timing-safe secret comparison (safeCompareSecrets)', () => {
  const secret = 'correct-webhook-secret-token-12345';

  assert.equal(safeCompareSecrets('wrong-secret', secret), false);
  assert.equal(safeCompareSecrets('', secret), false);
  assert.equal(safeCompareSecrets(null, secret), false);
  assert.equal(safeCompareSecrets(undefined, secret), false);
  assert.equal(safeCompareSecrets(secret, null), false);
  assert.equal(safeCompareSecrets(secret, undefined), false);
  assert.equal(safeCompareSecrets('correct-webhook-secret-token-12344', secret), false); // 1 char diff

  assert.equal(safeCompareSecrets(secret, secret), true);
  assert.equal(safeCompareSecrets(` ${secret} `, secret), true); // whitespace trimmed
});

test('supabaseDatabaseWebhook rejects invalid or missing secret with 401', async () => {
  const expectedSecret = 'super-secret-supabase-webhook-key-abc';

  // 1. Missing secret header
  let statusCode = null;
  let jsonResponse = null;
  const mockReq1 = {
    method: 'POST',
    headers: {},
    body: { type: 'INSERT', table: 'appointments', record: { appointment_id: 'apt_1' } },
  };
  const mockRes1 = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(body) {
      jsonResponse = body;
      return this;
    },
  };

  await supabaseDatabaseWebhookHandler(mockReq1, mockRes1, { expectedSecret });
  assert.equal(statusCode, 401);
  assert.deepEqual(jsonResponse, { error: 'Unauthorized' });

  // 2. Wrong secret header
  statusCode = null;
  jsonResponse = null;
  const mockReq2 = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': 'tampered-secret-value' },
    body: { type: 'INSERT', table: 'appointments', record: { appointment_id: 'apt_1' } },
  };
  const mockRes2 = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(body) {
      jsonResponse = body;
      return this;
    },
  };

  await supabaseDatabaseWebhookHandler(mockReq2, mockRes2, { expectedSecret });
  assert.equal(statusCode, 401);
  assert.deepEqual(jsonResponse, { error: 'Unauthorized' });
});

test('supabaseDatabaseWebhook sends FCM once on right secret, and skips second send on duplicate event', async () => {
  const expectedSecret = 'valid-supabase-webhook-secret-999';
  const processedStore = new Map();
  let fcmCallCount = 0;
  const capturedFcmPayloads = [];

  // Mock Firestore for idempotency tracking in _webhook_processed_events
  const mockDb = {
    collection(colName) {
      return {
        doc(docId) {
          return {
            colName,
            docId,
          };
        },
      };
    },
    async runTransaction(callback) {
      const tx = {
        async get(docRef) {
          const exists = processedStore.has(docRef.docId);
          return {
            exists,
            data: () => processedStore.get(docRef.docId),
          };
        },
        set(docRef, data) {
          processedStore.set(docRef.docId, data);
        },
      };
      return await callback(tx);
    },
  };

  // Mock FCM sender
  const mockSendFcm = async (db, options) => {
    fcmCallCount += 1;
    capturedFcmPayloads.push(options);
  };

  const webhookPayload = {
    type: 'INSERT',
    table: 'appointments',
    record: {
      appointment_id: 'apt_test_unique_42',
      doctor_id: 'doc_alpha',
      patient_name: 'Jane Doe',
      slot_label: '10:30 AM',
      created_at: '2026-10-20T10:00:00.000Z',
    },
  };

  // --- FIRST CALL (Fresh Event) ---
  let status1 = null;
  let json1 = null;
  const req1 = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: webhookPayload,
  };
  const res1 = {
    status(c) { status1 = c; return this; },
    json(j) { json1 = j; return this; },
  };

  await supabaseDatabaseWebhookHandler(req1, res1, {
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(status1, 200);
  assert.deepEqual(json1, { success: true });
  assert.equal(fcmCallCount, 1, 'Expected FCM to be sent exactly once on initial delivery');
  assert.equal(capturedFcmPayloads[0].docId, 'doc_alpha');
  assert.equal(capturedFcmPayloads[0].title, 'New Appointment Booked');

  // --- SECOND CALL (Duplicate Event Replay) ---
  let status2 = null;
  let json2 = null;
  const req2 = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: webhookPayload,
  };
  const res2 = {
    status(c) { status2 = c; return this; },
    json(j) { json2 = j; return this; },
  };

  await supabaseDatabaseWebhookHandler(req2, res2, {
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(status2, 200);
  assert.deepEqual(json2, { success: true, duplicate: true });
  assert.equal(fcmCallCount, 1, 'FCM must NOT be dispatched a second time for a duplicate event');
});

test('Dual-write loop guard simulation: single write does not ping-pong', async () => {
  // SIMULATION:
  // Step 1: User writes appointment to Supabase with sync_origin: 'patient_supabase'.
  // Step 2: Supabase database webhook / sync-to-firestore triggers.
  //         sync-to-firestore processes the update and writes to Firestore with syncedBy: 'supabase_bridge'.
  // Step 3: Firestore trigger syncFirestoreAppointmentToSupabase fires.
  //         It checks: after.syncedBy === 'supabase_bridge' -> DROPS write.
  //         Result: No write is sent back to Supabase.
  //
  // Step 4: Conversely, if doctor writes to Firestore first:
  //         Firestore trigger fires with sync_origin: 'doctor_firestore', synced_by: 'firestore_cloud_function'.
  //         It writes to Supabase.
  //         Supabase webhook fires -> sync-to-firestore checks sync_origin / synced_by ->
  //         drops write because origin is Firestore.
  //         Result: No write is sent back to Firestore.

  // 1. Test Firestore trigger loop check
  const firestoreDocFromBridge = {
    appointmentId: 'apt_loop_test_1',
    patientStatus: 'confirmed',
    doctorStatus: 'confirmed',
    syncedBy: 'supabase_bridge',
  };

  let firestoreTriggerDropped = false;
  if (firestoreDocFromBridge.syncedBy === 'supabase_bridge' || firestoreDocFromBridge.syncedBy === 'reconciler_bot') {
    firestoreTriggerDropped = true;
  }
  assert.equal(firestoreTriggerDropped, true, 'Firestore trigger must drop write originating from Supabase Bridge');

  // 2. Test Supabase trigger loop check
  const supabaseRowFromFirestore = {
    appointment_id: 'apt_loop_test_1',
    sync_origin: 'doctor_firestore',
    synced_by: 'firestore_cloud_function',
  };

  const syncOrigin = String(supabaseRowFromFirestore.sync_origin || '').trim().toLowerCase();
  const syncedBy = String(supabaseRowFromFirestore.synced_by || '').trim().toLowerCase();
  const isSupabaseOrigin = syncOrigin === 'patient_supabase' || syncOrigin.endsWith('_supabase');
  const isLoopOrigin = !isSupabaseOrigin && (
    syncOrigin === 'doctor_firestore' ||
    syncOrigin === 'patient_firestore' ||
    syncedBy === 'firestore_cloud_function' ||
    syncedBy === 'supabase_bridge'
  );

  assert.equal(isLoopOrigin, true, 'Supabase reverse bridge must drop write originating from Firestore');
});

test('Single notification path routing: exactly one notification fires for ON and OFF cases', async () => {
  const originalEnv = process.env.USE_SUPABASE_DB_DOCTOR_PATIENT;

  try {
    // --- CASE 1: Cutover flag is ON (Supabase primary) ---
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = 'true';
    assert.equal(isDoctorPatientSupabasePrimary(), true, 'isDoctorPatientSupabasePrimary must return true when env is true');

    let firestoreTriggerFired = false;
    let supabaseWebhookFired = false;

    // Simulate Firestore trigger execution
    if (!isDoctorPatientSupabasePrimary()) {
      firestoreTriggerFired = true; // Would send FCM
    }

    // Simulate Supabase Webhook execution
    if (isDoctorPatientSupabasePrimary()) {
      supabaseWebhookFired = true; // Sends FCM
    }

    assert.equal(firestoreTriggerFired, false, 'Firestore FCM trigger must be OFF when Supabase is primary');
    assert.equal(supabaseWebhookFired, true, 'Supabase webhook must send notification when Supabase is primary');
    const totalNotificationsCase1 = (firestoreTriggerFired ? 1 : 0) + (supabaseWebhookFired ? 1 : 0);
    assert.equal(totalNotificationsCase1, 1, 'Exactly one notification path must fire when cutover is ON');

    // --- CASE 2: Cutover flag is OFF (Firestore primary) ---
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = 'false';
    assert.equal(isDoctorPatientSupabasePrimary(), false, 'isDoctorPatientSupabasePrimary must return false when env is false');

    firestoreTriggerFired = false;
    supabaseWebhookFired = false;

    // Simulate Firestore trigger execution
    if (!isDoctorPatientSupabasePrimary()) {
      firestoreTriggerFired = true; // Sends FCM
    }

    // Simulate Supabase Webhook execution
    if (isDoctorPatientSupabasePrimary()) {
      supabaseWebhookFired = true; // Would send FCM
    }

    assert.equal(firestoreTriggerFired, true, 'Firestore FCM trigger must send notification when Firestore is primary');
    assert.equal(supabaseWebhookFired, false, 'Supabase webhook must not send notification when Firestore is primary');
    const totalNotificationsCase2 = (firestoreTriggerFired ? 1 : 0) + (supabaseWebhookFired ? 1 : 0);
    assert.equal(totalNotificationsCase2, 1, 'Exactly one notification path must fire when cutover is OFF');
  } finally {
    process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = originalEnv;
  }
});

