'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { syncFirestoreAppointmentToSupabase, syncFirestorePrescriptionToSupabase } = require('../cross_role_sync');

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
