'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncFirestoreAppointmentToSupabase,
  syncFirestorePrescriptionToSupabase,
  buildAppointmentSupabasePayload,
  resolveWriterSyncOrigin,
  experienceYearsFromDoctorDoc,
  placeholderPatientPayload,
  ensurePatientExistsInPostgres,
  buildDoctorSupabasePayload,
  buildMedicalStoreSupabasePayload,
  buildAvailabilitySupabasePayload,
  buildAmbulanceBroadcastSupabasePayload,
  buildAmbulanceRequestSupabasePayload,
  buildAmbulanceInviteSupabasePayload,
} = require('../cross_role_sync');

const realFetch = global.fetch;

function withFakeSupabase(run) {
  const prevUrl = process.env.SUPABASE_URL;
  const prevKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.SUPABASE_URL = 'https://example.invalid';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-only';
  return Promise.resolve()
    .then(run)
    .finally(() => {
      global.fetch = realFetch;
      if (prevUrl === undefined) delete process.env.SUPABASE_URL;
      else process.env.SUPABASE_URL = prevUrl;
      if (prevKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
      else process.env.SUPABASE_SERVICE_ROLE_KEY = prevKey;
    });
}

test('Loop Prevention: Drops writes marked with syncedBy: supabase_bridge', async () => {
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return { ok: true };
  };

  const fakeEvent = {
    params: { appointmentId: 'apt-test-loop' },
    data: {
      after: {
        exists: true,
        data: () => ({
          appointmentId: 'apt-test-loop',
          syncedBy: 'supabase_bridge', // <--- Loop marker
          doctorStatus: 'confirmed',
        }),
      },
    },
  };

  await syncFirestoreAppointmentToSupabase(fakeEvent);
  assert.equal(fetchCalled, false, 'Fetch should NEVER be called when syncedBy is supabase_bridge');
});

test('Loop Prevention: Drops writes marked with syncedBy: reconciler_bot', async () => {
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return { ok: true };
  };

  const fakeEvent = {
    params: { prescriptionId: 'rx-test-loop' },
    data: {
      after: {
        exists: true,
        data: () => ({
          prescriptionId: 'rx-test-loop',
          syncedBy: 'reconciler_bot', // <--- Reconciler marker
        }),
      },
    },
  };

  await syncFirestorePrescriptionToSupabase(fakeEvent);
  assert.equal(fetchCalled, false, 'Fetch should NEVER be called when syncedBy is reconciler_bot');
});

test('missing age, token, and slot are omitted from the appointment payload', () => {
  const payload = buildAppointmentSupabasePayload(
    {
      doctorId: 'doc-1',
      doctorName: 'Ada',
      patientId: 'pat-1',
      patientName: 'Ben',
      updatedAt: '2026-01-01T00:00:00.000Z',
    },
    'apt-omit',
    'doctor_firestore',
  );
  assert.equal(Object.hasOwn(payload, 'patient_age'), false);
  assert.equal(Object.hasOwn(payload, 'token_number'), false);
  assert.equal(Object.hasOwn(payload, 'slot_label'), false);
  assert.equal(payload.patient_age, undefined);
  assert.notEqual(payload.patient_age, 30);
  assert.notEqual(payload.token_number, 1);
  assert.notEqual(payload.slot_label, '10:00 AM');
});

test('Appointment sync: missing age/token does not write placeholder values in live sync', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      const u = String(url);
      const method = (opts && opts.method) || 'GET';
      const body = opts && opts.body ? JSON.parse(opts.body) : null;
      calls.push({ url: u, method, body });
      if (u.includes('select=updated_at')) {
        return { ok: true, json: async () => [] };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };

    await syncFirestoreAppointmentToSupabase({
      params: { appointmentId: 'apt-no-placeholders' },
      data: {
        after: {
          exists: true,
          id: 'apt-no-placeholders',
          data: () => ({
            doctorId: 'doc-valid-1',
            patientId: 'pat-valid-1',
            doctorName: 'Dr. John',
            patientName: 'Jane Doe',
            syncOrigin: 'doctor_firestore',
            updatedAt: '2026-06-01T00:00:00.000Z',
            // patientAge and tokenNumber intentionally omitted
          }),
        },
      },
    });
  });

  const postCall = calls.find((c) => c.method === 'POST' && c.url.includes('/rest/v1/appointments'));
  assert.ok(postCall, 'Must perform POST /rest/v1/appointments');
  assert.equal(postCall.body.patient_age, undefined);
  assert.equal(Object.hasOwn(postCall.body, 'patient_age'), false);
  assert.notEqual(postCall.body.patient_age, 30);
  assert.equal(postCall.body.token_number, undefined);
  assert.equal(Object.hasOwn(postCall.body, 'token_number'), false);
  assert.notEqual(postCall.body.token_number, 1);
});

test('present age, token, and slot are copied and patient origin is not retagged', () => {
  assert.equal(resolveWriterSyncOrigin({ syncOrigin: 'patient_supabase' }), 'patient_supabase');
  assert.equal(resolveWriterSyncOrigin({ createdBy: 'patient' }), 'patient_firestore');
  assert.equal(resolveWriterSyncOrigin({ source: 'walkin' }), 'doctor_firestore');
  assert.equal(resolveWriterSyncOrigin({ doctorId: 'doc-1' }), null);
  const payload = buildAppointmentSupabasePayload(
    {
      doctorName: 'Ada',
      patientName: 'Ben',
      patientAge: 41,
      tokenNumber: 4,
      slotLabel: '09:30 AM',
      updatedAt: '2026-01-02T00:00:00.000Z',
    },
    'apt-patient',
    resolveWriterSyncOrigin({ createdBy: 'patient' }),
  );
  assert.equal(payload.patient_age, 41);
  assert.equal(payload.token_number, 4);
  assert.equal(payload.slot_label, '09:30 AM');
  assert.equal(payload.sync_origin, 'patient_firestore');
  assert.notEqual(payload.sync_origin, 'doctor_firestore');
});

test('undetermined appointment origin is not upserted', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      calls.push({ url: String(url), method: (opts && opts.method) || 'GET' });
      return { ok: true, json: async () => [], text: async () => '' };
    };
    await syncFirestoreAppointmentToSupabase({
      params: { appointmentId: 'apt-unknown' },
      data: {
        after: {
          exists: true,
          id: 'apt-unknown',
          data: () => ({ doctorId: 'doc-1', patientId: 'pat-1' }),
        },
      },
    });
  });
  assert.equal(calls.some((call) => call.url.includes('/rest/v1/appointments')), false);
  assert.ok(calls.some((call) => call.url.includes('sync_dead_letter_queue')));
});

test('a stale Firestore snapshot does not upsert the appointment', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      calls.push({ url: String(url), method: (opts && opts.method) || 'GET' });
      if (String(url).includes('select=updated_at')) {
        return {
          ok: true,
          json: async () => [{ updated_at: '2099-01-01T00:00:00.000Z' }],
          text: async () => '',
        };
      }
      return { ok: true, json: async () => [], text: async () => '' };
    };
    await syncFirestoreAppointmentToSupabase({
      params: { appointmentId: 'apt-stale' },
      data: {
        after: {
          exists: true,
          id: 'apt-stale',
          data: () => ({
            doctorId: 'doc-1',
            syncOrigin: 'doctor_firestore',
            updatedAt: '2020-01-01T00:00:00.000Z',
            patientAge: 40,
            tokenNumber: 2,
            slotLabel: '11:00 AM',
          }),
        },
      },
    });
  });
  assert.ok(calls.some((call) => call.url.includes('select=updated_at')));
  assert.equal(
    calls.some((call) => call.method === 'POST' && call.url.includes('/rest/v1/appointments')),
    false,
  );
});

test('appointment sync skips when a name is missing and keeps names that are present', () => {
  const missing = buildAppointmentSupabasePayload(
    { doctorId: 'doc-1', patientId: 'pat-1', doctorName: 'Ada' },
    'apt-noname',
    'doctor_firestore',
  );
  assert.equal(missing.skip, true);
  assert.match(missing.reason, /patient_name/);
  assert.equal(JSON.stringify(missing).includes('Patient'), false);

  const present = buildAppointmentSupabasePayload(
    { doctorName: 'Ada', patientName: 'Ben', doctorId: 'doc-1' },
    'apt-named',
    'doctor_firestore',
  );
  assert.equal(present.skip, undefined);
  assert.equal(present.doctor_name, 'Ada');
  assert.equal(present.patient_name, 'Ben');
});

test('ambulance rows skip instead of inventing a phone, name, or location', () => {
  const broadcast = buildAmbulanceBroadcastSupabasePayload('bc-1', { patientId: 'pat-1' });
  assert.equal(broadcast.skip, true);
  assert.match(broadcast.reason, /contact_phone/);
  assert.equal(JSON.stringify(broadcast).includes('0000000000'), false);

  const broadcastWithStatusOmitted = buildAmbulanceBroadcastSupabasePayload('bc-2', {
    patientId: 'pat-1',
    patientName: 'Ben',
    pickupLocation: 'Gate',
    dropLocation: 'Ward',
    contactPhone: '9000000003',
  });
  assert.equal(broadcastWithStatusOmitted.skip, false);
  assert.equal(broadcastWithStatusOmitted.row.status, 'pending');

  const request = buildAmbulanceRequestSupabasePayload('req-1', {
    broadcastId: 'bc-2',
    driverId: 'amb-1',
    patientId: 'pat-1',
    patientName: 'Ben',
    pickupLocation: 'Gate',
    dropLocation: 'Ward',
  });
  assert.equal(request.skip, true);
  assert.match(request.reason, /contact_phone/);

  const invite = buildAmbulanceInviteSupabasePayload('inv-1', {
    doctorId: 'doc-1',
    ambulanceId: 'amb-1',
    serviceName: 'City',
    driverName: 'Rae',
  });
  assert.equal(invite.skip, true);
  assert.match(invite.reason, /phone/);
  const expired = buildAmbulanceInviteSupabasePayload('inv-2', {
    doctorId: 'doc-1',
    ambulanceId: 'amb-1',
    serviceName: 'City',
    driverName: 'Rae',
    phone: '9000000004',
    token: 'tok',
    status: 'expired',
  });
  assert.equal(expired.row.status, 'cancelled');
});

test('missing doctor experience is omitted and a present value is copied', () => {
  assert.equal(experienceYearsFromDoctorDoc({}), undefined);
  assert.equal(experienceYearsFromDoctorDoc({ experienceYears: 12 }), 12);
  assert.equal(experienceYearsFromDoctorDoc({ yearsExperience: 0 }), 0);
});

test('placeholder patient omits age and refuses a missing mobile', () => {
  const missing = placeholderPatientPayload('pat-1', {}, {});
  assert.equal(missing.skip, true);
  assert.equal(missing.reason, 'patient_mobile_missing');

  const noAge = placeholderPatientPayload('pat-2', { mobile: '1000000001', name: 'Ada' }, {});
  assert.equal(noAge.skip, false);
  assert.equal(noAge.patient.mobile, '1000000001');
  assert.equal(Object.hasOwn(noAge.patient, 'age'), false);

  const namedNoGender = placeholderPatientPayload('pat-3', { mobile: '1000000001', name: 'Ada' }, {});
  assert.equal(Object.hasOwn(namedNoGender.patient, 'gender'), false);
  assert.equal(namedNoGender.patient.name, 'Ada');

  const missingName = placeholderPatientPayload('pat-4', { mobile: '1000000001', age: 4 }, {});
  assert.equal(missingName.skip, true);
  assert.equal(missingName.reason, 'patient_name_missing');

  const withAge = placeholderPatientPayload('pat-5', { mobile: '1000000001', name: 'Ada', age: 4 }, {});
  assert.equal(withAge.patient.age, 4);
});

test('doctor, store, and availability payloads do not invent missing values', () => {
  const missingDoctor = buildDoctorSupabasePayload('doc-1', { name: 'Ada' });
  assert.equal(missingDoctor.skip, true);
  assert.match(missingDoctor.reason, /email/);
  assert.equal(JSON.stringify(missingDoctor).includes('0000000000'), false);
  assert.equal(JSON.stringify(missingDoctor).includes('Mumbai'), false);

  const doctor = buildDoctorSupabasePayload('doc-1', {
    name: 'Ada',
    email: 'ada@example.com',
    mobile: '1000000001',
    specialization: 'Cardiology',
    qualification: 'MBBS',
    city: 'Pune',
  });
  assert.equal(doctor.skip, false);
  assert.equal(doctor.doctor.city, 'Pune');
  assert.equal(Object.hasOwn(doctor.doctor, 'state'), false);
  assert.equal(Object.hasOwn(doctor.doctor, 'country'), false);

  const store = buildMedicalStoreSupabasePayload('store-1', { storeName: 'Ada Store' });
  assert.equal(store.skip, true);
  assert.equal(JSON.stringify(store).includes('PENDING'), false);

  const hours = buildAvailabilitySupabasePayload('doc-1', {});
  assert.deepEqual(hours, { doctor_id: 'doc-1' });
  const copied = buildAvailabilitySupabasePayload('doc-1', { morningStart: '10:00 AM', eveningEnabled: false });
  assert.equal(copied.morning_start, '10:00 AM');
  assert.equal(copied.evening_enabled, false);
  assert.equal(Object.hasOwn(copied, 'morning_end'), false);
});

test('missing patient mobile is dead-lettered and not inserted', async () => {
  const calls = [];
  await withFakeSupabase(async () => {
    global.fetch = async (url, opts) => {
      calls.push({ url: String(url), method: (opts && opts.method) || 'GET', body: opts && opts.body });
      return { ok: true, json: async () => [], text: async () => '' };
    };
    await ensurePatientExistsInPostgres('pat-no-mobile', {}, {
      url: 'https://example.invalid',
      key: 'test-only',
    });
  });
  assert.equal(calls.some((call) => call.method === 'POST' && call.url.includes('/rest/v1/patients')), false);
  const dlq = calls.find((call) => call.url.includes('sync_dead_letter_queue'));
  assert.ok(dlq);
  assert.match(String(dlq.body), /patient_mobile_missing/);
});
