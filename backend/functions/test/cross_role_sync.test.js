'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncFirestoreAppointmentToSupabase,
  syncFirestorePrescriptionToSupabase,
  buildAppointmentSupabasePayload,
  resolveWriterSyncOrigin,
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
      patientId: 'pat-1',
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

test('present age, token, and slot are copied and patient origin is not retagged', () => {
  assert.equal(resolveWriterSyncOrigin({ syncOrigin: 'patient_supabase' }), 'patient_supabase');
  assert.equal(resolveWriterSyncOrigin({ createdBy: 'patient' }), 'patient_firestore');
  assert.equal(resolveWriterSyncOrigin({ source: 'walkin' }), 'doctor_firestore');
  assert.equal(resolveWriterSyncOrigin({ doctorId: 'doc-1' }), null);
  const payload = buildAppointmentSupabasePayload(
    {
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
