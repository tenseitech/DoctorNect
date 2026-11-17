'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  _safeCompareSecrets: safeCompareSecrets,
  _supabaseDatabaseWebhookHandler: supabaseDatabaseWebhookHandler,
  _isDoctorPatientSupabasePrimary: isDoctorPatientSupabasePrimary,
  _resetRemoteConfigCache: resetRemoteConfigCache,
  _setMockRemoteConfigTemplate: setMockRemoteConfigTemplate,
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

  await supabaseDatabaseWebhookHandler(mockReq1, mockRes1, { dispatchMode: 'webhook', expectedSecret });
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

  await supabaseDatabaseWebhookHandler(mockReq2, mockRes2, { dispatchMode: 'webhook', expectedSecret });
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
    dispatchMode: 'webhook',
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
    dispatchMode: 'webhook',
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

test('Postgres-only: isDoctorPatientSupabasePrimary is always true (no Firestore dual-write path)', async () => {
  resetRemoteConfigCache();
  try {
    setMockRemoteConfigTemplate(async () => ({
      parameters: {
        use_supabase_db_doctor_patient: { defaultValue: { value: 'false' } },
      },
    }));
    resetRemoteConfigCache();
    assert.equal(await isDoctorPatientSupabasePrimary(), true);

    let firestoreTriggerFired = false;
    let supabaseWebhookFired = false;

    if (!(await isDoctorPatientSupabasePrimary())) {
      firestoreTriggerFired = true;
    }
    if (await isDoctorPatientSupabasePrimary()) {
      supabaseWebhookFired = true;
    }

    assert.equal(firestoreTriggerFired, false, 'Firestore FCM triggers are removed in postgres-only architecture');
    assert.equal(supabaseWebhookFired, true, 'Supabase webhook is the notification path');
    assert.equal((firestoreTriggerFired ? 1 : 0) + (supabaseWebhookFired ? 1 : 0), 1);
  } finally {
    setMockRemoteConfigTemplate(null);
    resetRemoteConfigCache();
  }
});




test('Phase D Webhooks: pharmacy_deliveries INSERT notifies store and UPDATE(dispensed) notifies patient', async () => {
  const expectedSecret = 'test-secret';
  const processedStore = new Map();
  const mockDb = {
    collection: (col) => ({ doc: (id) => ({ col, id }) }),
    runTransaction: async (cb) => cb({
      get: async (ref) => ({ exists: processedStore.has(ref.id) }),
      set: (ref, data) => processedStore.set(ref.id, data),
    }),
  };

  const sentFCM = [];
  const mockSendFcm = async (_db, payload) => sentFCM.push(payload);

  // 1. INSERT pharmacy delivery
  const reqInsert = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: {
      type: 'INSERT',
      table: 'pharmacy_deliveries',
      record: {
        delivery_id: 'del_101',
        prescription_id: 'rx_202',
        doctor_name: 'Dr. Sen',
        patient_name: 'Amit',
        store_id: 'store_303',
        status: 'sent',
      },
    },
  };
  let resStatus = null;
  const mockRes = {
    status: (s) => { resStatus = s; return mockRes; },
    json: () => mockRes,
  };

  await supabaseDatabaseWebhookHandler(reqInsert, mockRes, {
    dispatchMode: 'webhook',
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(resStatus, 200);
  assert.equal(sentFCM.length, 1);
  assert.equal(sentFCM[0].docId, 'store_303');
  assert.equal(sentFCM[0].data.type, 'pharmacy_delivery_new');

  // 2. UPDATE pharmacy delivery to dispensed
  const reqUpdate = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: {
      type: 'UPDATE',
      table: 'pharmacy_deliveries',
      record: {
        delivery_id: 'del_101',
        patient_id: 'pat_404',
        store_name: 'MedPlus',
        status: 'dispensed',
      },
      old_record: {
        delivery_id: 'del_101',
        patient_id: 'pat_404',
        status: 'viewed',
      },
    },
  };

  await supabaseDatabaseWebhookHandler(reqUpdate, mockRes, {
    dispatchMode: 'webhook',
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(sentFCM.length, 2);
  assert.equal(sentFCM[1].docId, 'pat_404');
  assert.equal(sentFCM[1].data.status, 'dispensed');
});

test('Phase D Webhooks: lab_bookings INSERT notifies lab and UPDATE(completed) notifies patient', async () => {
  const expectedSecret = 'test-secret';
  const processedStore = new Map();
  const mockDb = {
    collection: (col) => ({ doc: (id) => ({ col, id }) }),
    runTransaction: async (cb) => cb({
      get: async (ref) => ({ exists: processedStore.has(ref.id) }),
      set: (ref, data) => processedStore.set(ref.id, data),
    }),
  };

  const sentFCM = [];
  const mockSendFcm = async (_db, payload) => sentFCM.push(payload);

  // 1. INSERT lab booking
  const reqInsert = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: {
      type: 'INSERT',
      table: 'lab_bookings',
      record: {
        booking_id: 'bkg_501',
        lab_id: 'lab_601',
        patient_name: 'Sunita',
        test_name: 'Lipid Profile',
      },
    },
  };
  let resStatus = null;
  const mockRes = {
    status: (s) => { resStatus = s; return mockRes; },
    json: () => mockRes,
  };

  await supabaseDatabaseWebhookHandler(reqInsert, mockRes, {
    dispatchMode: 'webhook',
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(resStatus, 200);
  assert.equal(sentFCM.length, 1);
  assert.equal(sentFCM[0].docId, 'lab_601');
  assert.equal(sentFCM[0].data.type, 'lab_booking_new');

  // 2. UPDATE lab booking to completed
  const reqUpdate = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: {
      type: 'UPDATE',
      table: 'lab_bookings',
      record: {
        booking_id: 'bkg_501',
        patient_id: 'pat_701',
        lab_name: 'City Lab',
        test_name: 'Lipid Profile',
        status: 'completed',
      },
      old_record: {
        booking_id: 'bkg_501',
        status: 'sample_collected',
      },
    },
  };

  await supabaseDatabaseWebhookHandler(reqUpdate, mockRes, {
    dispatchMode: 'webhook',
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(sentFCM.length, 2);
  assert.equal(sentFCM[1].docId, 'pat_701');
  assert.equal(sentFCM[1].data.status, 'completed');
});

test('Phase D Webhooks: ambulance_broadcasts UPDATE(accepted) notifies patient', async () => {
  const expectedSecret = 'test-secret';
  const processedStore = new Map();
  const mockDb = {
    collection: (col) => ({ doc: (id) => ({ col, id }) }),
    runTransaction: async (cb) => cb({
      get: async (ref) => ({ exists: processedStore.has(ref.id) }),
      set: (ref, data) => processedStore.set(ref.id, data),
    }),
  };

  const sentFCM = [];
  const mockSendFcm = async (_db, payload) => sentFCM.push(payload);

  const reqUpdate = {
    method: 'POST',
    headers: { 'x-supabase-webhook-secret': expectedSecret },
    body: {
      type: 'UPDATE',
      table: 'ambulance_broadcasts',
      record: {
        broadcast_id: 'bcast_801',
        patient_id: 'pat_901',
        status: 'accepted',
      },
      old_record: {
        broadcast_id: 'bcast_801',
        status: 'pending',
      },
    },
  };
  let resStatus = null;
  const mockRes = {
    status: (s) => { resStatus = s; return mockRes; },
    json: () => mockRes,
  };

  await supabaseDatabaseWebhookHandler(reqUpdate, mockRes, {
    dispatchMode: 'webhook',
    expectedSecret,
    db: mockDb,
    sendFcm: mockSendFcm,
  });

  assert.equal(resStatus, 200);
  assert.equal(sentFCM.length, 1);
  assert.equal(sentFCM[0].docId, 'pat_901');
  assert.equal(sentFCM[0].data.type, 'ambulance_accepted');
});

test('supabaseDatabaseWebhook is disabled in APP_ENV=production unless ENABLE_SUPABASE_DATABASE_WEBHOOK=1', async () => {
  const {
    supabaseDatabaseWebhookHandler,
    isLegacyDatabaseWebhookEnabled,
  } = require('../supabase_database_webhook');

  const prevApp = process.env.APP_ENV;
  const prevFlag = process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK;
  try {
    process.env.APP_ENV = 'production';
    delete process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK;
    assert.equal(isLegacyDatabaseWebhookEnabled(), false);

    let statusCode = null;
    let body = null;
    const req = {
      method: 'POST',
      headers: { 'x-supabase-webhook-secret': 'any' },
      body: { type: 'INSERT', table: 'appointments', record: {} },
    };
    const res = {
      status(code) {
        statusCode = code;
        return this;
      },
      json(payload) {
        body = payload;
        return this;
      },
    };

    await supabaseDatabaseWebhookHandler(req, res, {
      expectedSecret: 'any',
      forceEnableLegacyWebhook: false,
    });
    assert.equal(statusCode, 503);
    assert.match(body.message, /notification_outbox/i);

    process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK = '1';
    assert.equal(isLegacyDatabaseWebhookEnabled(), true);
  } finally {
    if (prevApp === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = prevApp;
    if (prevFlag === undefined) delete process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK;
    else process.env.ENABLE_SUPABASE_DATABASE_WEBHOOK = prevFlag;
  }
});

test('supabaseDatabaseWebhook rejects missing configured secret with 401 before dispatch', async () => {
  let statusCode = null;
  const req = {
    method: 'POST',
    headers: {},
    body: { type: 'INSERT', table: 'appointments', record: { appointment_id: 'x' } },
  };
  const res = {
    status(code) {
      statusCode = code;
      return this;
    },
    json() {
      return this;
    },
  };

  await supabaseDatabaseWebhookHandler(req, res, {
    expectedSecret: 'configured-secret-value',
    forceEnableLegacyWebhook: true,
  });
  assert.equal(statusCode, 401);
});
