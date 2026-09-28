'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncFirestoreMedicalStoreToSupabase,
  syncFirestorePharmacyConnectionToSupabase,
  syncFirestorePharmacyDeliveryToSupabase,
  syncPharmacyDeliveryMedicinesToSupabase,
  syncFirestoreLabToSupabase,
  syncFirestoreLabCatalogTestToSupabase,
  syncFirestoreLabBookingToSupabase,
  syncFirestoreLabOrderToSupabase,
  syncFirestoreLabConnectionToSupabase,
  ensureDoctorExistsInPostgres,
  ensureMedicalStoreExistsInPostgres,
  ensureLabExistsInPostgres,
  ensurePatientExistsInPostgres,
  ensurePrescriptionExistsInPostgres,
  toValidUuid,
} = require('../cross_role_sync');

const originalFetch = global.fetch;

test('Helper: toValidUuid strictly validates RFC 4122 UUID strings', () => {
  assert.equal(toValidUuid('123e4567-e89b-12d3-a456-426614174000'), '123e4567-e89b-12d3-a456-426614174000');
  assert.equal(toValidUuid('550e8400-e29b-41d4-a716-446655440000'), '550e8400-e29b-41d4-a716-446655440000');
  // Firebase Auth UIDs are not UUIDs:
  assert.equal(toValidUuid('wXq92YpZ8n0abc1234def56789'), null);
  assert.equal(toValidUuid(''), null);
  assert.equal(toValidUuid(null), null);
  assert.equal(toValidUuid(12345), null);
});

test('Loop Prevention: All 8 Pharmacy & Lab triggers drop syncedBy writes', async () => {
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
      () => syncFirestoreMedicalStoreToSupabase(makeBridgeEvent('storeId', 'store-1')),
      () => syncFirestorePharmacyConnectionToSupabase(makeBridgeEvent('connectionId', 'conn-1')),
      () => syncFirestorePharmacyDeliveryToSupabase(makeBridgeEvent('deliveryId', 'deliv-1')),
      () => syncFirestoreLabToSupabase(makeBridgeEvent('labId', 'lab-1')),
      () => syncFirestoreLabCatalogTestToSupabase(makeBridgeEvent('testId', 'test-1')),
      () => syncFirestoreLabBookingToSupabase(makeBridgeEvent('bookingId', 'book-1')),
      () => syncFirestoreLabOrderToSupabase(makeBridgeEvent('orderId', 'order-1')),
      () => syncFirestoreLabConnectionToSupabase(makeBridgeEvent('connectionId', 'lconn-1')),
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

test('Pharmacy Store Sync: Upserts medical_stores with structured address and defaults', async () => {
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
      params: { storeId: 'store-100' },
      data: {
        after: {
          exists: true,
          id: 'store-100',
          data: () => ({
            storeId: 'store-100',
            storeName: 'Apollo Pharmacy Bandra',
            ownerName: 'Sunil Mehta',
            drugLicenseNumber: 'DL-MH-123456',
            phone: '9876543210',
            email: 'Apollo.Bandra@Example.com',
            gstNumber: '27AAAAA0000A1Z5',
            address: {
              addressLine1: 'Shop 4, Hill Road',
              addressLine2: 'Near Station',
              city: 'Mumbai',
              state: 'Maharashtra',
              country: 'India',
              pinCode: '400050',
            },
            profileCompleted: true,
            verified: true,
            verifiedAt: '2026-09-01T10:00:00.000Z',
            ownerUid: '550e8400-e29b-41d4-a716-446655440000',
          }),
        },
      },
    };

    await syncFirestoreMedicalStoreToSupabase(fakeEvent);

    assert.equal(calls.length, 1);
    const storeCall = calls[0];
    assert.match(storeCall.url, /\/rest\/v1\/medical_stores\?on_conflict=store_id/);
    assert.equal(storeCall.method, 'POST');
    assert.equal(storeCall.body.store_id, 'store-100');
    assert.equal(storeCall.body.store_name, 'Apollo Pharmacy Bandra');
    assert.equal(storeCall.body.owner_name, 'Sunil Mehta');
    assert.equal(storeCall.body.drug_license_number, 'DL-MH-123456');
    assert.equal(storeCall.body.email, 'apollo.bandra@example.com');
    assert.equal(storeCall.body.gst_number, '27AAAAA0000A1Z5');
    assert.equal(storeCall.body.address_line1, 'Shop 4, Hill Road');
    assert.equal(storeCall.body.address_line2, 'Near Station');
    assert.equal(storeCall.body.city, 'Mumbai');
    assert.equal(storeCall.body.pincode, '400050');
    assert.equal(storeCall.body.owner_uid, '550e8400-e29b-41d4-a716-446655440000');
    assert.equal(storeCall.body.profile_completed, true);
    assert.equal(storeCall.body.verified, true);
    assert.equal(storeCall.body.deactivated, false);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Pharmacy Store Sync: Soft-deletes store on document deletion', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { storeId: 'store-to-delete' },
      data: {
        before: { id: 'store-to-delete', exists: true },
        after: { exists: false },
      },
    };

    await syncFirestoreMedicalStoreToSupabase(fakeEvent);

    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/rest\/v1\/medical_stores\?store_id=eq\.store-to-delete/);
    assert.equal(calls[0].method, 'PATCH');
    assert.equal(calls[0].body.deactivated, true);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Pharmacy Connection Sync: Ensures parent doctor/store and upserts connection', async () => {
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
      params: { connectionId: 'pconn-500' },
      data: {
        after: {
          exists: true,
          id: 'pconn-500',
          data: () => ({
            doctorId: 'doc-42',
            doctorName: 'Dr. Sharma',
            medicalStoreId: 'store-100',
            storeName: 'Apollo Bandra',
            status: 'active',
            requestedBy: 'doctor',
            requestedAt: '2026-09-10T08:00:00.000Z',
            respondedAt: '2026-09-10T09:30:00.000Z',
          }),
        },
      },
    };

    await syncFirestorePharmacyConnectionToSupabase(fakeEvent);

    // 1. check doc exists (GET)
    // 2. ensure doc (POST) if not exists
    // 3. check store exists (GET)
    // 4. ensure store (POST) if not exists
    // 5. upsert pharmacy_connection (POST)
    const connPost = calls.find(c => c.url.includes('/rest/v1/pharmacy_connections?on_conflict=connection_id'));
    assert.ok(connPost, 'Should upsert pharmacy_connection');
    assert.equal(connPost.body.connection_id, 'pconn-500');
    assert.equal(connPost.body.doctor_id, 'doc-42');
    assert.equal(connPost.body.medical_store_id, 'store-100');
    assert.equal(connPost.body.status, 'active');
    assert.equal(connPost.body.requested_by, 'doctor');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Pharmacy Delivery Sync: Upserts header and child delivery medicines', async () => {
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
      params: { deliveryId: 'deliv-88' },
      data: {
        after: {
          exists: true,
          id: 'deliv-88',
          data: () => ({
            prescriptionId: 'rx-200',
            doctorId: 'doc-42',
            storeId: 'store-100',
            patientId: 'pat-999',
            doctorName: 'Dr. Sharma',
            storeName: 'Apollo Bandra',
            patientName: 'Rahul Verma',
            status: 'partiallyDispensed',
            sentAt: '2026-09-12T10:00:00.000Z',
            dispensingNotes: 'Substituted Paracetamol with Crocin 650',
            medicineCount: 2,
            medicineLines: [
              { medicineEntryId: 'rx-200_med_0', availability: 'available', substituteName: null },
              { medicineEntryId: 'rx-200_med_1', availability: 'substituted', substituteName: 'Crocin 650' },
            ],
            draft: { patientId: 'pat-999', diagnosis: 'Fever' },
          }),
        },
      },
    };

    await syncFirestorePharmacyDeliveryToSupabase(fakeEvent);

    const delivPost = calls.find(c => c.url.includes('/rest/v1/pharmacy_deliveries?on_conflict=delivery_id'));
    assert.ok(delivPost, 'Should upsert pharmacy_deliveries');
    assert.equal(delivPost.body.delivery_id, 'deliv-88');
    assert.equal(delivPost.body.status, 'partiallyDispensed');
    assert.equal(delivPost.body.medicine_count, 2);

    const medDel = calls.find(c => c.url.includes('/rest/v1/pharmacy_delivery_medicines?delivery_id=eq.deliv-88') && c.method === 'DELETE');
    assert.ok(medDel, 'Should delete existing pharmacy_delivery_medicines');

    const medPost = calls.find(c => c.url.endsWith('/rest/v1/pharmacy_delivery_medicines') && c.method === 'POST');
    assert.ok(medPost, 'Should insert new pharmacy_delivery_medicines');
    assert.equal(medPost.body.length, 2);
    assert.equal(medPost.body[0].availability, 'available');
    assert.equal(medPost.body[1].availability, 'substituted');
    assert.equal(medPost.body[1].substitute_name, 'Crocin 650');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Lab Profile Sync: Upserts labs table with defaults and soft-deletes on removal', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    // 1. Upsert
    const fakeUpsert = {
      params: { labId: 'lab-300' },
      data: {
        after: {
          exists: true,
          id: 'lab-300',
          data: () => ({
            labName: 'Thyrocare Powai',
            licenseNumber: 'LAB-MH-789',
            phone: '9876500000',
            email: 'Powai@Thyrocare.Com',
            rating: 4.8,
            area: 'Hiranandani Powai',
            city: 'Mumbai',
            state: 'Maharashtra',
            profileCompleted: true,
            verified: true,
          }),
        },
      },
    };
    await syncFirestoreLabToSupabase(fakeUpsert);

    const labPost = calls.find(c => c.url.includes('/rest/v1/labs?on_conflict=lab_id'));
    assert.ok(labPost, 'Should upsert labs');
    assert.equal(labPost.body.lab_id, 'lab-300');
    assert.equal(labPost.body.lab_name, 'Thyrocare Powai');
    assert.equal(labPost.body.email, 'powai@thyrocare.com');
    assert.equal(labPost.body.rating, 4.8);
    assert.equal(labPost.body.area, 'Hiranandani Powai');

    // 2. Soft-delete
    calls.length = 0;
    const fakeDelete = {
      params: { labId: 'lab-300' },
      data: {
        before: { id: 'lab-300', exists: true },
        after: { exists: false },
      },
    };
    await syncFirestoreLabToSupabase(fakeDelete);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/rest\/v1\/labs\?lab_id=eq\.lab-300/);
    assert.equal(calls[0].method, 'PATCH');
    assert.equal(calls[0].body.deactivated, true);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Lab Catalog Sync: Handles both aggregate tests array and individual test documents', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    // A: Aggregate 'default' catalog doc
    const fakeAggregate = {
      params: { testId: 'default' },
      data: {
        after: {
          exists: true,
          data: () => ({
            tests: [
              { id: 'cbc', name: 'Complete Blood Count', parameters: ['Hb', 'WBC', 'Platelets'], fastingRequired: false, sampleType: 'blood', reportHours: 12, popular: true, category: 'Hematology' },
              { id: 'lipid_profile', name: 'Lipid Profile', parameters: ['Cholesterol', 'Triglycerides'], fastingRequired: true, sampleType: 'blood', reportHours: 24, popular: true, category: 'Biochemistry' },
            ],
          }),
        },
      },
    };
    await syncFirestoreLabCatalogTestToSupabase(fakeAggregate);

    assert.equal(calls.length, 1);
    assert.equal(calls[0].body.length, 2);
    assert.equal(calls[0].body[0].test_id, 'cbc');
    assert.equal(calls[0].body[0].fasting_required, false);
    assert.equal(calls[0].body[1].test_id, 'lipid_profile');
    assert.equal(calls[0].body[1].fasting_required, true);

    // B: Single test document
    calls.length = 0;
    const fakeSingle = {
      params: { testId: 'thyroid_t3_t4_tsh' },
      data: {
        after: {
          exists: true,
          id: 'thyroid_t3_t4_tsh',
          data: () => ({
            name: 'Thyroid Profile',
            parameters: ['T3', 'T4', 'TSH'],
            fastingRequired: true,
            sampleType: 'blood',
            reportHours: 24,
            popular: true,
            category: 'Endocrinology',
          }),
        },
      },
    };
    await syncFirestoreLabCatalogTestToSupabase(fakeSingle);

    assert.equal(calls.length, 1);
    assert.equal(calls[0].body[0].test_id, 'thyroid_t3_t4_tsh');
    assert.equal(calls[0].body[0].name, 'Thyroid Profile');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Lab Booking Sync: Upserts lab_bookings and ensures parent patient & lab records', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { bookingId: 'book-777' },
      data: {
        after: {
          exists: true,
          id: 'book-777',
          data: () => ({
            patientId: 'pat-555',
            labId: 'lab-300',
            patientName: 'Pooja Nair',
            patientAge: 28,
            patientGender: 'Female',
            contactNumber: '9988776655',
            testId: 'lipid_profile',
            testName: 'Lipid Profile',
            testNames: ['Lipid Profile'],
            testIds: ['lipid_profile'],
            bookingForSelf: true,
            collectionType: 'homeCollection',
            partnerLab: 'Thyrocare Powai',
            address: 'Flat 101, Lakeview Tower, Powai',
            dateTime: '2026-09-15T07:30:00.000Z',
            slotLabel: '7:30 AM',
            status: 'sampleCollected',
            source: 'app',
          }),
        },
      },
    };

    await syncFirestoreLabBookingToSupabase(fakeEvent);

    const bookingPost = calls.find(c => c.url.includes('/rest/v1/lab_bookings?on_conflict=booking_id'));
    assert.ok(bookingPost, 'Should upsert lab_bookings');
    assert.equal(bookingPost.body.booking_id, 'book-777');
    assert.equal(bookingPost.body.patient_id, 'pat-555');
    assert.equal(bookingPost.body.lab_id, 'lab-300');
    assert.equal(bookingPost.body.collection_type, 'homeCollection');
    assert.equal(bookingPost.body.status, 'sampleCollected');
    assert.equal(bookingPost.body.source, 'app');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Lab Order Sync: Upserts doctor-initiated lab order with urgency and tests', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { orderId: 'lorder-101' },
      data: {
        after: {
          exists: true,
          id: 'lorder-101',
          data: () => ({
            doctorId: 'doc-42',
            patientId: 'pat-555',
            labId: 'lab-300',
            doctorName: 'Dr. Sharma',
            patientName: 'Pooja Nair',
            patientAge: 28,
            labName: 'Thyrocare Powai',
            testIds: ['cbc', 'crp'],
            testNames: ['Complete Blood Count', 'C-Reactive Protein'],
            indication: 'Persistent acute fever for 4 days',
            urgency: 'Urgent',
            fastingRequired: false,
            homeCollection: true,
            source: 'investigations',
            status: 'ordered',
          }),
        },
      },
    };

    await syncFirestoreLabOrderToSupabase(fakeEvent);

    const orderPost = calls.find(c => c.url.includes('/rest/v1/lab_orders?on_conflict=order_id'));
    assert.ok(orderPost, 'Should upsert lab_orders');
    assert.equal(orderPost.body.order_id, 'lorder-101');
    assert.equal(orderPost.body.doctor_id, 'doc-42');
    assert.equal(orderPost.body.patient_id, 'pat-555');
    assert.equal(orderPost.body.urgency, 'Urgent');
    assert.equal(orderPost.body.status, 'ordered');
    assert.deepEqual(orderPost.body.test_ids, ['cbc', 'crp']);
    assert.deepEqual(orderPost.body.test_names, ['Complete Blood Count', 'C-Reactive Protein']);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Lab Connection Sync: Upserts lab_connections and hard-deletes on removal', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    // 1. Upsert
    const fakeUpsert = {
      params: { connectionId: 'lconn-202' },
      data: {
        after: {
          exists: true,
          id: 'lconn-202',
          data: () => ({
            doctorId: 'doc-42',
            labId: 'lab-300',
            doctorName: 'Dr. Sharma',
            labName: 'Thyrocare Powai',
            status: 'active',
            requestedBy: 'lab',
            requestedAt: '2026-09-05T09:00:00.000Z',
          }),
        },
      },
    };
    await syncFirestoreLabConnectionToSupabase(fakeUpsert);

    const connPost = calls.find(c => c.url.includes('/rest/v1/lab_connections?on_conflict=connection_id'));
    assert.ok(connPost, 'Should upsert lab_connections');
    assert.equal(connPost.body.connection_id, 'lconn-202');
    assert.equal(connPost.body.status, 'active');
    assert.equal(connPost.body.requested_by, 'lab');

    // 2. Hard delete
    calls.length = 0;
    const fakeDelete = {
      params: { connectionId: 'lconn-202' },
      data: {
        before: { id: 'lconn-202', exists: true },
        after: { exists: false },
      },
    };
    await syncFirestoreLabConnectionToSupabase(fakeDelete);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/rest\/v1\/lab_connections\?connection_id=eq\.lconn-202/);
    assert.equal(calls[0].method, 'DELETE');
  } finally {
    global.fetch = originalFetch;
  }
});
