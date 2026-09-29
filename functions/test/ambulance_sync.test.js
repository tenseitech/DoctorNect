'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncFirestoreAmbulanceToSupabase,
  syncFirestoreAmbulancePrivateSettingsToSupabase,
  syncFirestoreAmbulanceBroadcastToSupabase,
  syncFirestoreAmbulanceRequestToSupabase,
  syncFirestoreAmbulanceInviteToSupabase,
  ensureAmbulanceExistsInPostgres,
  ensureAmbulanceBroadcastExistsInPostgres,
  ensureDoctorExistsInPostgres,
  hashAmbulancePin,
  isAmbulancePinHash,
  toValidUuid,
} = require('../cross_role_sync');

const originalFetch = global.fetch;

test('Ambulance Helpers: hashAmbulancePin & isAmbulancePinHash', () => {
  // Test plain text PIN hashing
  const plainPin = '987654';
  const hashed = hashAmbulancePin(plainPin);
  assert.match(hashed, /^pbkdf2\$sha256\$100000\$[a-f0-9]{32}\$[a-f0-9]{128}$/);
  assert.equal(isAmbulancePinHash(hashed), true);

  // Test legacy 64-char sha256 hex
  const legacyHash = 'a'.repeat(64);
  assert.equal(isAmbulancePinHash(legacyHash), true);

  // Test plain text detection
  assert.equal(isAmbulancePinHash('123456'), false);
  assert.equal(isAmbulancePinHash(''), false);
  assert.equal(isAmbulancePinHash(null), false);
});

test('Loop Prevention: All 5 Ambulance triggers drop syncedBy writes', async () => {
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return { ok: true, json: async () => [] };
  };

  try {
    const makeBridgeEvent = (idKey, idVal) => ({
      params: { [idKey]: idVal },
      data: {
        after: {
          exists: true,
          data: () => ({ [idKey]: idVal, syncedBy: 'supabase_bridge' }),
        },
      },
    });

    const triggers = [
      () => syncFirestoreAmbulanceToSupabase(makeBridgeEvent('ambulanceId', 'amb-1')),
      () => syncFirestoreAmbulancePrivateSettingsToSupabase(makeBridgeEvent('ambulanceId', 'amb-1')),
      () => syncFirestoreAmbulanceBroadcastToSupabase(makeBridgeEvent('broadcastId', 'bc-1')),
      () => syncFirestoreAmbulanceRequestToSupabase(makeBridgeEvent('requestId', 'req-1')),
      () => syncFirestoreAmbulanceInviteToSupabase(makeBridgeEvent('inviteId', 'inv-1')),
    ];

    for (const run of triggers) {
      fetchCalled = false;
      await run();
      assert.equal(fetchCalled, false, 'Trigger must drop syncedBy: supabase_bridge write');
    }
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Sync: Upserts ambulances with vehicle, address, and ratings', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return {
      ok: true,
      status: 200,
      json: async () => [],
      text: async () => 'OK',
    };
  };

  try {
    const fakeEvent = {
      params: { ambulanceId: 'amb-101' },
      data: {
        after: {
          exists: true,
          id: 'amb-101',
          data: () => ({
            ambulanceId: 'amb-101',
            authUid: '123e4567-e89b-12d3-a456-426614174000',
            serviceName: 'Lifeline Critical Care',
            ownerName: 'Rajesh Varma',
            driverName: 'Ramesh Patil',
            phone: '9820011223',
            vehicleNumber: 'MH-02-BD-1234',
            ambulanceType: 'als',
            username: 'Amb_Lifeline',
            baseAddress: 'Andheri West Emergency Depot',
            licenseNumber: 'DL-MH-AMB-9988',
            insuranceNumber: 'INS-887766',
            hasOxygen: true,
            hasVentilator: true,
            hasStretcher: true,
            is24x7: true,
            ratePerKm: 35.5,
            totalRating: 4.85,
            ratingCount: 42,
            isAvailable: true,
            profileCompleted: true,
            verified: true,
            address: {
              addressLine1: 'Unit 5, Lifeline Hub',
              addressLine2: 'SV Road',
              city: 'Mumbai',
              state: 'Maharashtra',
              country: 'India',
              pinCode: '400058',
            },
            serviceAreas: ['Andheri West', 'Juhu', 'Versova'],
          }),
        },
      },
    };

    await syncFirestoreAmbulanceToSupabase(fakeEvent);

    const postCall = calls.find(c => c.url.includes('/rest/v1/ambulances?on_conflict=ambulance_id'));
    assert.ok(postCall, 'Should POST to /rest/v1/ambulances?on_conflict=ambulance_id');
    assert.equal(postCall.body.ambulance_id, 'amb-101');
    assert.equal(postCall.body.auth_uid, '123e4567-e89b-12d3-a456-426614174000');
    assert.equal(postCall.body.service_name, 'Lifeline Critical Care');
    assert.equal(postCall.body.driver_name, 'Ramesh Patil');
    assert.equal(postCall.body.ambulance_type, 'als');
    assert.equal(postCall.body.username, 'amb_lifeline'); // normalized lowercase
    assert.equal(postCall.body.has_oxygen, true);
    assert.equal(postCall.body.has_ventilator, true);
    assert.equal(postCall.body.rate_per_km, 35.5);
    assert.equal(postCall.body.total_rating, 4.85);
    assert.equal(postCall.body.rating_count, 42);
    assert.equal(postCall.body.city, 'Mumbai');
    assert.equal(postCall.body.pincode, '400058');
    assert.deepEqual(postCall.body.service_areas, ['Andheri West', 'Juhu', 'Versova']);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Sync: Hard-deletes ambulance on deletion', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeDeleteEvent = {
      params: { ambulanceId: 'amb-101' },
      data: {
        before: { id: 'amb-101', exists: true },
        after: { exists: false },
      },
    };

    await syncFirestoreAmbulanceToSupabase(fakeDeleteEvent);

    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/rest\/v1\/ambulances\?ambulance_id=eq\.amb-101/);
    assert.equal(calls[0].method, 'DELETE');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Private Settings Sync: Hashes plaintext PIN, self-heals parent, and stores pin_hash', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    // Check GET returns empty for parent check so self-healing creates placeholder
    if (opts.method === 'GET' || !opts.method) {
      return { ok: true, status: 200, json: async () => [] };
    }
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { ambulanceId: 'amb-202' },
      data: {
        after: {
          exists: true,
          id: 'amb-202',
          data: () => ({
            pin: '654321', // Plaintext PIN entered by driver
            fcmToken: 'fcm-token-driver-202',
            fcmTokenUpdatedAt: '2026-09-10T12:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreAmbulancePrivateSettingsToSupabase(fakeEvent);

    // 1. Should have self-healed parent ambulance
    const parentPost = calls.find(c => c.url.includes('/rest/v1/ambulances?on_conflict=ambulance_id'));
    assert.ok(parentPost, 'Should ensure parent ambulance exists in Postgres');
    assert.equal(parentPost.body.ambulance_id, 'amb-202');

    // 2. Should have upserted ambulance_private_settings
    const settingsPost = calls.find(c => c.url.includes('/rest/v1/ambulance_private_settings?on_conflict=ambulance_id'));
    assert.ok(settingsPost, 'Should upsert ambulance_private_settings');
    assert.equal(settingsPost.body.ambulance_id, 'amb-202');
    assert.equal(settingsPost.body.fcm_token, 'fcm-token-driver-202');
    assert.notEqual(settingsPost.body.pin_hash, '654321', 'Must never send plaintext PIN to Postgres');
    assert.match(settingsPost.body.pin_hash, /^pbkdf2\$sha256\$100000\$/, 'Must hash plaintext PIN with PBKDF2');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Private Settings Sync: Preserves existing pin_hash on FCM token-only update', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    if (url.includes('/rest/v1/ambulances?ambulance_id=eq.')) {
      return { ok: true, json: async () => [{ ambulance_id: 'amb-303' }] };
    }
    if (url.includes('/rest/v1/ambulance_private_settings?ambulance_id=eq.') && url.includes('select=pin_hash')) {
      return { ok: true, json: async () => [{ pin_hash: 'pbkdf2$sha256$100000$salt$existinghash' }] };
    }
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeFcmOnlyEvent = {
      params: { ambulanceId: 'amb-303' },
      data: {
        after: {
          exists: true,
          id: 'amb-303',
          data: () => ({
            fcmToken: 'new-refreshed-fcm-token',
            fcmTokenUpdatedAt: '2026-09-12T08:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreAmbulancePrivateSettingsToSupabase(fakeFcmOnlyEvent);

    const settingsPost = calls.find(c => c.url.includes('/rest/v1/ambulance_private_settings?on_conflict=ambulance_id'));
    assert.ok(settingsPost, 'Should upsert ambulance_private_settings');
    assert.equal(settingsPost.body.ambulance_id, 'amb-303');
    assert.equal(settingsPost.body.fcm_token, 'new-refreshed-fcm-token');
    assert.equal(settingsPost.body.pin_hash, 'pbkdf2$sha256$100000$salt$existinghash', 'Must preserve existing pin_hash');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Broadcast Sync: Upserts broadcast and marks sibling requests taken on accept', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeAcceptEvent = {
      params: { broadcastId: 'bc-555' },
      data: {
        after: {
          exists: true,
          id: 'bc-555',
          data: () => ({
            broadcastId: 'bc-555',
            patientId: 'pat-999',
            patientName: 'Sunita Rao',
            pickupLocation: 'Bandra Terminus',
            dropLocation: 'Lilavati Hospital',
            contactPhone: '9811223344',
            notes: 'Patient having chest pain, oxygen required',
            status: 'accepted',
            acceptedDriverId: 'amb-winner-1',
            acceptedDriverName: 'Anil Kumar',
            acceptedDriverPhone: '9988776655',
            acceptedVehicleNumber: 'MH-03-CC-9988',
            acceptedAmbulanceType: 'icu',
            acceptedAt: '2026-09-15T14:30:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreAmbulanceBroadcastToSupabase(fakeAcceptEvent);

    // 1. Broadcast upsert
    const bcPost = calls.find(c => c.url.includes('/rest/v1/ambulance_broadcasts?on_conflict=broadcast_id'));
    assert.ok(bcPost, 'Should upsert ambulance_broadcasts');
    assert.equal(bcPost.body.broadcast_id, 'bc-555');
    assert.equal(bcPost.body.status, 'accepted');
    assert.equal(bcPost.body.accepted_driver_id, 'amb-winner-1');
    assert.equal(bcPost.body.accepted_vehicle_number, 'MH-03-CC-9988');

    // 2. Sibling requests updated to 'taken'
    const siblingPatch = calls.find(c => c.url.includes('/rest/v1/ambulance_requests?') && c.method === 'PATCH');
    assert.ok(siblingPatch, 'Should PATCH sibling requests');
    assert.match(siblingPatch.url, /broadcast_id=eq\.bc-555/);
    assert.match(siblingPatch.url, /driver_id=neq\.amb-winner-1/);
    assert.match(siblingPatch.url, /status=eq\.pending/);
    assert.equal(siblingPatch.body.status, 'taken');
    assert.equal(siblingPatch.body.accepted_driver_id, 'amb-winner-1');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Broadcast Sync: Cancels sibling requests in Postgres when broadcast is cancelled', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeCancelEvent = {
      params: { broadcastId: 'bc-777' },
      data: {
        after: {
          exists: true,
          id: 'bc-777',
          data: () => ({
            broadcastId: 'bc-777',
            status: 'cancelled',
          }),
        },
      },
    };

    await syncFirestoreAmbulanceBroadcastToSupabase(fakeCancelEvent);

    const siblingCancel = calls.find(c => c.url.includes('/rest/v1/ambulance_requests?') && c.method === 'PATCH');
    assert.ok(siblingCancel, 'Should PATCH pending requests to cancelled');
    assert.match(siblingCancel.url, /broadcast_id=eq\.bc-777/);
    assert.match(siblingCancel.url, /status=eq\.pending/);
    assert.equal(siblingCancel.body.status, 'cancelled');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Request Sync: Upserts per-driver request and self-heals parents', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    // Check GET returns empty for parent check so self-healing creates placeholder
    if (opts.method === 'GET' || !opts.method) {
      return { ok: true, status: 200, json: async () => [] };
    }
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeRequestEvent = {
      params: { requestId: 'req-888' },
      data: {
        after: {
          exists: true,
          id: 'req-888',
          data: () => ({
            requestId: 'req-888',
            broadcastId: 'bc-555',
            driverId: 'amb-driver-9',
            patientId: 'pat-999',
            patientName: 'Sunita Rao',
            pickupLocation: 'Bandra Terminus',
            dropLocation: 'Lilavati Hospital',
            contactPhone: '9811223344',
            status: 'pending',
          }),
        },
      },
    };

    await syncFirestoreAmbulanceRequestToSupabase(fakeRequestEvent);

    // 1. Should self-heal parent broadcast
    const parentBc = calls.find(c => c.url.includes('/rest/v1/ambulance_broadcasts?on_conflict=broadcast_id'));
    assert.ok(parentBc, 'Should self-heal parent broadcast in Postgres');
    assert.equal(parentBc.body.broadcast_id, 'bc-555');

    // 2. Should self-heal parent ambulance
    const parentAmb = calls.find(c => c.url.includes('/rest/v1/ambulances?on_conflict=ambulance_id'));
    assert.ok(parentAmb, 'Should self-heal parent ambulance in Postgres');
    assert.equal(parentAmb.body.ambulance_id, 'amb-driver-9');

    // 3. Should upsert ambulance_requests
    const reqPost = calls.find(c => c.url.includes('/rest/v1/ambulance_requests?on_conflict=request_id'));
    assert.ok(reqPost, 'Should upsert ambulance_requests');
    assert.equal(reqPost.body.request_id, 'req-888');
    assert.equal(reqPost.body.broadcast_id, 'bc-555');
    assert.equal(reqPost.body.driver_id, 'amb-driver-9');
    assert.equal(reqPost.body.status, 'pending');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Ambulance Invite Sync: Upserts driver invite, maps expired -> cancelled, self-heals doctor', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    // Check GET returns empty for parent check so self-healing creates placeholder
    if (opts.method === 'GET' || !opts.method) {
      return { ok: true, status: 200, json: async () => [] };
    }
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeInviteEvent = {
      params: { inviteId: 'inv-444' },
      data: {
        after: {
          exists: true,
          id: 'inv-444',
          data: () => ({
            inviteId: 'inv-444',
            token: 'token-abc-xyz',
            doctorId: 'doc-hospital-admin',
            ambulanceId: 'amb-new-fleet',
            serviceName: 'Metropolitan Fleet',
            driverName: 'Vikram Joshi',
            phone: '9898989898',
            status: 'expired', // should map to 'cancelled'
            username: 'amb_vikram',
            createdAt: '2026-09-01T10:00:00.000Z',
          }),
        },
      },
    };

    await syncFirestoreAmbulanceInviteToSupabase(fakeInviteEvent);

    // 1. Should self-heal parent doctor
    const parentDoc = calls.find(c => c.url.includes('/rest/v1/doctors?on_conflict=doctor_id'));
    assert.ok(parentDoc, 'Should self-heal parent doctor in Postgres');
    assert.equal(parentDoc.body.doctor_id, 'doc-hospital-admin');

    // 2. Should upsert ambulance_invites
    const invPost = calls.find(c => c.url.includes('/rest/v1/ambulance_invites?on_conflict=invite_id'));
    assert.ok(invPost, 'Should upsert ambulance_invites');
    assert.equal(invPost.body.invite_id, 'inv-444');
    assert.equal(invPost.body.token, 'token-abc-xyz');
    assert.equal(invPost.body.doctor_id, 'doc-hospital-admin');
    assert.equal(invPost.body.ambulance_id, 'amb-new-fleet');
    assert.equal(invPost.body.status, 'cancelled', 'Expired status must map to cancelled for Postgres constraint');
  } finally {
    global.fetch = originalFetch;
  }
});
