'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  syncFirestoreDoctorToSupabase,
  syncFirestoreDoctorAvailabilityToSupabase,
  syncFirestoreDoctorBlockedDatesToSupabase,
  syncDoctorEducationToSupabase,
  syncDoctorBlockedDatesToSupabase,
  toStringArray,
  toIsoTimestamp,
  toDateString,
} = require('../cross_role_sync');

// Save original fetch
const originalFetch = global.fetch;

test('Helper: toStringArray parses various array and string inputs', () => {
  assert.deepEqual(toStringArray(['English', 'Hindi']), ['English', 'Hindi']);
  assert.deepEqual(toStringArray('Single Language'), ['Single Language']);
  assert.deepEqual(toStringArray(null, ['Default']), ['Default']);
  assert.deepEqual(toStringArray([], ['Default']), ['Default']);
  assert.deepEqual(toStringArray(['  Valid  ', '', null]), ['Valid']);
});

test('Helper: toDateString converts various date formats to YYYY-MM-DD', () => {
  assert.equal(toDateString('2026-10-15'), '2026-10-15');
  assert.equal(toDateString(new Date('2026-10-15T12:00:00Z')), '2026-10-15');
  assert.equal(toDateString({ toDate: () => new Date('2026-10-15T00:00:00Z') }), '2026-10-15');
  assert.equal(toDateString(null), null);
  assert.equal(toDateString('invalid-date'), null);
});

test('Helper: toIsoTimestamp safely converts dates and timestamps', () => {
  const iso = toIsoTimestamp('2026-10-15T10:00:00.000Z');
  assert.equal(iso, '2026-10-15T10:00:00.000Z');
  const fromObj = toIsoTimestamp({ toDate: () => new Date('2026-10-15T10:00:00.000Z') });
  assert.equal(fromObj, '2026-10-15T10:00:00.000Z');
  assert.equal(toIsoTimestamp(null), null);
});

test('Doctor Sync: Loop Prevention drops writes with syncedBy marker', async () => {
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return { ok: true, json: async () => [] };
  };

  try {
    const fakeEventBridge = {
      params: { doctorId: 'doc-loop-1' },
      data: {
        after: {
          exists: true,
          data: () => ({ doctorId: 'doc-loop-1', syncedBy: 'supabase_bridge' }),
        },
      },
    };
    await syncFirestoreDoctorToSupabase(fakeEventBridge);
    assert.equal(fetchCalled, false, 'Fetch must not be called when syncedBy: supabase_bridge');

    const fakeEventReconciler = {
      params: { doctorId: 'doc-loop-2' },
      data: {
        after: {
          exists: true,
          data: () => ({ doctorId: 'doc-loop-2', syncedBy: 'reconciler_bot' }),
        },
      },
    };
    await syncFirestoreDoctorToSupabase(fakeEventReconciler);
    assert.equal(fetchCalled, false, 'Fetch must not be called when syncedBy: reconciler_bot');
  } finally {
    global.fetch = originalFetch;
  }
});

test('Doctor Sync: Upserts doctor record and education entries to PostgREST', async () => {
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
      params: { doctorId: 'doc-123' },
      data: {
        after: {
          exists: true,
          id: 'doc-123',
          data: () => ({
            doctorId: 'doc-123',
            name: 'Dr. John Doe',
            email: 'john.doe@example.com',
            mobile: '9876543210',
            specialization: 'Cardiology',
            qualification: 'MD',
            experienceYears: 12,
            consultationFee: 750,
            clinicName: 'Heart Care Clinic',
            city: 'Mumbai',
            languages: ['English', 'Hindi', 'Marathi'],
            rating: 4.8,
            reviewCount: 35,
            verified: true,
            education: [
              { degree: 'MBBS', college: 'GMC Mumbai', year: 2010 },
              { degree: 'MD Cardiology', college: 'AIIMS Delhi', year: 2014 },
            ],
          }),
        },
      },
    };

    await syncFirestoreDoctorToSupabase(fakeEvent);

    assert.ok(calls.length >= 2, `Expected at least 2 fetch calls, got ${calls.length}`);

    // Call 1: Upsert doctor
    const doctorCall = calls.find(c => c.url.includes('/rest/v1/doctors'));
    assert.ok(doctorCall, 'Expected a POST call to /rest/v1/doctors');
    assert.equal(doctorCall.method, 'POST');
    assert.equal(doctorCall.body.doctor_id, 'doc-123');
    assert.equal(doctorCall.body.name, 'Dr. John Doe');
    assert.equal(doctorCall.body.specialization, 'Cardiology');
    assert.equal(doctorCall.body.experience_years, 12);
    assert.equal(doctorCall.body.consultation_fee, 750);
    assert.equal(doctorCall.body.verified, true);
    assert.deepEqual(doctorCall.body.languages, ['English', 'Hindi', 'Marathi']);

    // Call 2 & 3: Delete & Insert doctor_education
    const eduDeleteCall = calls.find(c => c.url.includes('/rest/v1/doctor_education') && c.method === 'DELETE');
    assert.ok(eduDeleteCall, 'Expected DELETE call to /rest/v1/doctor_education');

    const eduPostCall = calls.find(c => c.url.includes('/rest/v1/doctor_education') && c.method === 'POST');
    assert.ok(eduPostCall, 'Expected POST call to /rest/v1/doctor_education');
    assert.equal(eduPostCall.body.length, 2);
    assert.equal(eduPostCall.body[0].degree, 'MBBS');
    assert.equal(eduPostCall.body[1].degree, 'MD Cardiology');
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});

test('Doctor Sync: Fallback education entry created from qualification if education array is empty', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, json: async () => [], text: async () => 'OK' };
  };

  try {
    await syncDoctorEducationToSupabase('doc-fallback', [], 'MBBS, DNB', {
      url: process.env.SUPABASE_URL,
      key: process.env.SUPABASE_SERVICE_ROLE_KEY,
    });

    const eduPost = calls.find(c => c.method === 'POST' && c.url.includes('/rest/v1/doctor_education'));
    assert.ok(eduPost, 'Expected education POST call');
    assert.equal(eduPost.body.length, 1);
    assert.equal(eduPost.body[0].doctor_id, 'doc-fallback');
    assert.equal(eduPost.body[0].degree, 'MBBS, DNB');
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});

test('Doctor Sync: Soft-delete when document is deleted in Firestore', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    return { ok: true, status: 200, text: async () => 'OK' };
  };

  try {
    const fakeDeleteEvent = {
      params: { doctorId: 'doc-to-delete' },
      data: {
        after: {
          exists: false,
        },
        before: {
          exists: true,
          id: 'doc-to-delete',
          data: () => ({ doctorId: 'doc-to-delete', name: 'Dr. Departing' }),
        },
      },
    };

    await syncFirestoreDoctorToSupabase(fakeDeleteEvent);

    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, 'PATCH');
    assert.ok(calls[0].url.includes('doctor_id=eq.doc-to-delete'));
    assert.equal(calls[0].body.deactivated, true);
    assert.ok(calls[0].body.deactivated_at);
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});

test('Doctor Availability Sync: Upserts availability and blocked dates', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    // If GET doctors check, return existing doctor
    if (opts.method === 'GET') {
      return { ok: true, status: 200, json: async () => [{ doctor_id: 'doc-avail-1' }] };
    }
    return { ok: true, status: 200, text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { doctorId: 'doc-avail-1' },
      data: {
        after: {
          exists: true,
          id: 'doc-avail-1',
          data: () => ({
            doctorId: 'doc-avail-1',
            workingDays: ['Mon', 'Tue', 'Wed', 'Thu'],
            morningStart: '09:30 AM',
            morningEnd: '01:30 PM',
            eveningEnabled: true,
            eveningStart: '05:00 PM',
            eveningEnd: '09:00 PM',
            slotDurationMins: 20,
            maxPatientsPerDay: 25,
            breakEnabled: true,
            breakStart: '01:30 PM',
            breakEnd: '02:30 PM',
            blockedDates: [
              '2026-11-01',
              '2026-11-02',
            ],
          }),
        },
      },
    };

    await syncFirestoreDoctorAvailabilityToSupabase(fakeEvent);

    const availCall = calls.find(c => c.url.includes('/rest/v1/doctor_availability') && c.method === 'POST');
    assert.ok(availCall, 'Expected POST to doctor_availability');
    assert.equal(availCall.body.doctor_id, 'doc-avail-1');
    assert.deepEqual(availCall.body.working_days, ['Mon', 'Tue', 'Wed', 'Thu']);
    assert.equal(availCall.body.morning_start, '09:30 AM');
    assert.equal(availCall.body.slot_duration_mins, 20);
    assert.equal(availCall.body.max_patients_per_day, 25);
    assert.equal(availCall.body.break_enabled, true);

    const blockedDelete = calls.find(c => c.url.includes('/rest/v1/doctor_blocked_dates') && c.method === 'DELETE');
    assert.ok(blockedDelete, 'Expected DELETE to doctor_blocked_dates');

    const blockedPost = calls.find(c => c.url.includes('/rest/v1/doctor_blocked_dates') && c.method === 'POST');
    assert.ok(blockedPost, 'Expected POST to doctor_blocked_dates');
    assert.equal(blockedPost.body.length, 2);
    assert.equal(blockedPost.body[0].blocked_date, '2026-11-01');
    assert.equal(blockedPost.body[1].blocked_date, '2026-11-02');
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});

test('Doctor Blocked Dates Standalone Sync: Handles standalone collection writes', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url, method: opts.method, body: opts.body ? JSON.parse(opts.body) : null });
    if (opts.method === 'GET') {
      return { ok: true, status: 200, json: async () => [{ doctor_id: 'doc-standalone' }] };
    }
    return { ok: true, status: 200, text: async () => 'OK' };
  };

  try {
    const fakeEvent = {
      params: { docId: 'doc-standalone' },
      data: {
        after: {
          exists: true,
          id: 'doc-standalone',
          data: () => ({
            doctorId: 'doc-standalone',
            blockedDates: ['2026-12-25', '2026-12-26'],
          }),
        },
      },
    };

    await syncFirestoreDoctorBlockedDatesToSupabase(fakeEvent);

    const postCall = calls.find(c => c.url.includes('/rest/v1/doctor_blocked_dates') && c.method === 'POST');
    assert.ok(postCall, 'Expected POST to doctor_blocked_dates');
    assert.equal(postCall.body.length, 2);
    assert.equal(postCall.body[0].blocked_date, '2026-12-25');
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});

test('DLQ & Error Handling: PostgREST error records failure to DLQ and rethrows', async () => {
  process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-key';

  const dlqCalls = [];
  global.fetch = async (url, opts) => {
    if (url.includes('/rest/v1/sync_dead_letter_queue')) {
      dlqCalls.push(JSON.parse(opts.body));
      return { ok: true, status: 201, text: async () => 'Created' };
    }
    // Simulate PostgREST failure
    return {
      ok: false,
      status: 500,
      text: async () => 'Internal Server Error: Database unreachable',
    };
  };

  try {
    const fakeEvent = {
      params: { doctorId: 'doc-error-test' },
      data: {
        after: {
          exists: true,
          id: 'doc-error-test',
          data: () => ({ doctorId: 'doc-error-test', name: 'Dr. Fail' }),
        },
      },
    };

    await assert.rejects(
      async () => {
        await syncFirestoreDoctorToSupabase(fakeEvent);
      },
      (err) => {
        assert.match(err.message, /Internal Server Error/);
        return true;
      }
    );

    assert.ok(dlqCalls.length >= 1, 'Expected DLQ failure to be recorded');
    assert.equal(dlqCalls[0].entity_type, 'doctor');
    assert.equal(dlqCalls[0].entity_id, 'doc-error-test');
    assert.match(dlqCalls[0].error_message, /Internal Server Error/);
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  }
});
