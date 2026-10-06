'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');

const {
  MAX_PATIENTS_PER_SLOT,
  deriveSlotId,
  toIstDateAndTime,
  isSlotInsideDoctorAvailability,
  bookAppointmentHandler,
  reconcileAppointmentSlotHandler,
  reconcileAppointmentSlotTransaction,
  bookAppointment,
  ENFORCE_ABUSE_APP_CHECK,
} = require('../appointment_slots');
const { LIMITS, enforceAbuseLimit } = require('../abuse_rate_limit');
const { backfillSingleSlotTransaction } = require('../../scripts/backfill_doctor_slots');

function applyFieldTransforms(base, data) {
  const result = { ...base };
  for (const [k, v] of Object.entries(data)) {
    if (v && v.constructor && v.constructor.name === 'ArrayUnionTransform') {
      const arr = Array.isArray(result[k]) ? [...result[k]] : [];
      for (const el of v.elements) {
        if (!arr.includes(el)) arr.push(el);
      }
      result[k] = arr;
    } else if (v && v.constructor && v.constructor.name === 'ArrayRemoveTransform') {
      const arr = Array.isArray(result[k]) ? [...result[k]] : [];
      result[k] = arr.filter((el) => !v.elements.includes(el));
    } else if (v && v.constructor && v.constructor.name === 'ServerTimestampTransform') {
      result[k] = new Date();
    } else {
      result[k] = v;
    }
  }
  return result;
}

function createConcurrentMockFirestore() {
  const docs = new Map();
  let transactionChain = Promise.resolve();
  let autoIdCounter = 1;

  function cloneDoc(obj) {
    if (obj == null || typeof obj !== 'object') return obj;
    if (obj instanceof Date) return new Date(obj.getTime());
    if (typeof obj.toDate === 'function') return obj;
    if (Array.isArray(obj)) return obj.map(cloneDoc);
    const copy = {};
    for (const [k, v] of Object.entries(obj)) {
      copy[k] = cloneDoc(v);
    }
    return copy;
  }

  function readDoc(key) {
    const data = docs.get(key);
    return data == null ? null : cloneDoc(data);
  }

  function docRef(collection, id) {
    const key = `${collection}/${id}`;
    return {
      id,
      collection,
      key,
      async get() {
        const data = readDoc(key);
        return {
          id,
          ref: { id, collection, key },
          exists: data != null,
          data: () => (data == null ? undefined : { ...data }),
        };
      },
      async set(data, options = {}) {
        const base = options.merge ? (readDoc(key) || {}) : {};
        docs.set(key, applyFieldTransforms(base, data));
      },
    };
  }

  async function runTransaction(updateFn) {
    let releaseGate;
    const gate = new Promise((resolve) => {
      releaseGate = resolve;
    });
    const previous = transactionChain;
    transactionChain = transactionChain.then(() => gate);
    await previous;

    try {
      const pending = new Map();
      const tx = {
        async get(ref) {
          await Promise.resolve();
          const data = pending.has(ref.key)
            ? pending.get(ref.key)
            : readDoc(ref.key);
          return {
            id: ref.id,
            ref,
            exists: data != null,
            data: () => (data == null ? undefined : { ...data }),
          };
        },
        set(ref, data, { merge } = {}) {
          const base = pending.has(ref.key)
            ? (pending.get(ref.key) || {})
            : (merge ? (readDoc(ref.key) || {}) : {});
          pending.set(ref.key, applyFieldTransforms(base, data));
        },
        delete(ref) {
          pending.set(ref.key, null);
        },
      };

      const result = await updateFn(tx);
      for (const [key, value] of pending.entries()) {
        if (value == null) docs.delete(key);
        else docs.set(key, value);
      }
      return result;
    } finally {
      releaseGate();
    }
  }

  return {
    docs,
    collection(name) {
      return {
        doc(id) {
          const actualId = id || `auto_${name}_${autoIdCounter++}`;
          return docRef(name, actualId);
        },
        async get() {
          const list = [];
          for (const [k, v] of docs.entries()) {
            if (k.startsWith(`${name}/`)) {
              const docId = k.split('/')[1];
              list.push({
                id: docId,
                ref: docRef(name, docId),
                exists: true,
                data: () => ({ ...v }),
              });
            }
          }
          return { size: list.length, docs: list };
        },
      };
    },
    runTransaction,
  };
}

// ---------------------------------------------------------------------------
// TEST SUITE
// ---------------------------------------------------------------------------

test('slot at a day boundary in IST correctly shifts to the next day in Asia/Kolkata', () => {
  // UTC 2026-10-05T18:45:00.000Z is 00:15 on 2026-10-06 in IST (UTC+5:30)
  const dt1 = '2026-10-05T18:45:00.000Z';
  const ist1 = toIstDateAndTime(dt1);
  assert.equal(ist1.date, '2026-10-06', 'Date must be 2026-10-06 in IST');
  assert.equal(ist1.time, '00:15', 'Time must be 00:15 in IST');

  const slotId1 = deriveSlotId('doc_boundary', dt1);
  assert.equal(slotId1, 'doc_boundary_2026-10-06_00:15');

  // UTC 2026-10-05T23:30:00.000Z is 05:00 on 2026-10-06 in IST
  const dt2 = '2026-10-05T23:30:00.000Z';
  const ist2 = toIstDateAndTime(dt2);
  assert.equal(ist2.date, '2026-10-06');
  assert.equal(ist2.time, '05:00');
  assert.equal(deriveSlotId('doc_boundary', dt2), 'doc_boundary_2026-10-06_05:00');
});

test('two concurrent bookAppointment calls on a slot with 2 active bookings: exactly one succeeds', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_busy';
  // 2026-10-06 is a Tuesday (working day). 03:30 UTC = 09:00 IST.
  const dateTime = '2026-10-06T03:30:00.000Z';
  const slotId = deriveSlotId(doctorId, dateTime);

  // Setup doctor profile: verified and not deactivated
  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Jane Smith',
    specialization: 'Cardiology',
    verified: true,
    deactivated: false,
  });

  // Seed slot with 2 active bookings
  db.docs.set(`doctor_slots/${slotId}`, {
    doctorId,
    date: '2026-10-06',
    time: '09:00',
    activeAppointmentIds: ['appt_existing_1', 'appt_existing_2'],
    slotOverflow: false,
  });
  db.docs.set('appointments/appt_existing_1', { patientId: 'patient_existing_1' });
  db.docs.set('appointments/appt_existing_2', { patientId: 'patient_existing_2' });

  // Setup two new patients
  db.docs.set('users/user_p3', { role: 'patient', name: 'Patient Three', profileId: 'patient_3' });
  db.docs.set('users/user_p4', { role: 'patient', name: 'Patient Four', profileId: 'patient_4' });

  // Two concurrent calls (with slotShareReason since slot already has bookings)
  const [res3, res4] = await Promise.allSettled([
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM', slotShareReason: 'Emergency consultation' },
      { uid: 'user_p3' },
      db,
    ),
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM', slotShareReason: 'Emergency consultation' },
      { uid: 'user_p4' },
      db,
    ),
  ]);

  const fulfilled = [res3, res4].filter((r) => r.status === 'fulfilled');
  const rejected = [res3, res4].filter((r) => r.status === 'rejected');

  assert.equal(fulfilled.length, 1, 'Exactly one concurrent booking must succeed');
  assert.equal(rejected.length, 1, 'Exactly one concurrent booking must be rejected');
  assert.equal(rejected[0].reason?.code, 'resource-exhausted', 'Rejection code must be resource-exhausted');

  const slotDoc = db.docs.get(`doctor_slots/${slotId}`);
  assert.equal(slotDoc.activeAppointmentIds.length, 3, 'Slot must now have exactly 3 active appointments');
  assert.equal(slotDoc.slotOverflow, false);
});

test('cancel frees capacity and allows subsequent booking', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_cancel_test';
  const dateTime = '2026-10-06T03:30:00.000Z'; // Tuesday 09:00 IST
  const slotId = deriveSlotId(doctorId, dateTime);

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. John Doe',
    specialization: 'General',
    verified: true,
    deactivated: false,
  });

  // Slot currently full at capacity 3
  db.docs.set(`doctor_slots/${slotId}`, {
    doctorId,
    date: '2026-10-06',
    time: '09:00',
    activeAppointmentIds: ['appt_1', 'appt_2', 'appt_3'],
    slotOverflow: false,
  });
  db.docs.set('appointments/appt_1', { doctorId, dateTime, patientId: 'patient_1' });
  db.docs.set('appointments/appt_2', { doctorId, dateTime, patientId: 'patient_2' });
  db.docs.set('appointments/appt_3', { doctorId, dateTime, patientId: 'patient_3' });

  // Patient 4 tries to book full slot -> rejected
  db.docs.set('users/user_p4', { role: 'patient', name: 'Patient Four', profileId: 'patient_4' });
  await assert.rejects(
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM' },
      { uid: 'user_p4' },
      db,
    ),
    { code: 'resource-exhausted' },
  );

  // Now trigger runs to cancel appt_1
  await reconcileAppointmentSlotHandler(
    {
      params: { appointmentId: 'appt_1' },
      data: {
        before: {
          data: () => ({ doctorId, dateTime, cancellationReason: null }),
        },
        after: {
          data: () => ({ doctorId, dateTime, cancellationReason: 'Patient cancelled' }),
        },
      },
    },
    db,
  );

  const slotAfterCancel = db.docs.get(`doctor_slots/${slotId}`);
  assert.deepEqual(slotAfterCancel.activeAppointmentIds, ['appt_2', 'appt_3']);
  assert.equal(slotAfterCancel.activeAppointmentIds.length, 2, 'Slot should now have 2 active bookings');

  // Now Patient 4 books -> must succeed (providing slotShareReason since slot has 2 bookings)
  const bookRes = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM', slotShareReason: 'Emergency' },
    { uid: 'user_p4' },
    db,
  );
  assert.equal(bookRes.ok, true);

  const slotAfterRebook = db.docs.get(`doctor_slots/${slotId}`);
  assert.equal(slotAfterRebook.activeAppointmentIds.length, 3, 'Slot is back to capacity 3');
  assert.ok(slotAfterRebook.activeAppointmentIds.includes(bookRes.appointmentId));
});

test('legacy direct reschedule moves the appointment between slots', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_reschedule';
  const dateTimeA = '2026-10-06T03:30:00.000Z'; // 09:00 IST
  const dateTimeB = '2026-10-06T03:45:00.000Z'; // 09:15 IST
  const slotIdA = deriveSlotId(doctorId, dateTimeA);
  const slotIdB = deriveSlotId(doctorId, dateTimeB);

  // Slot A has appt_movable
  db.docs.set(`doctor_slots/${slotIdA}`, {
    doctorId,
    date: '2026-10-06',
    time: '09:00',
    activeAppointmentIds: ['appt_movable'],
    slotOverflow: false,
  });

  // Slot B starts empty
  db.docs.set(`doctor_slots/${slotIdB}`, {
    doctorId,
    date: '2026-10-06',
    time: '09:15',
    activeAppointmentIds: ['appt_other'],
    slotOverflow: false,
  });

  // Trigger runs on appointment reschedule from A to B
  await reconcileAppointmentSlotHandler(
    {
      params: { appointmentId: 'appt_movable' },
      data: {
        before: {
          data: () => ({ doctorId, dateTime: dateTimeA, cancellationReason: null }),
        },
        after: {
          data: () => ({ doctorId, dateTime: dateTimeB, cancellationReason: null }),
        },
      },
    },
    db,
  );

  const slotDocA = db.docs.get(`doctor_slots/${slotIdA}`);
  const slotDocB = db.docs.get(`doctor_slots/${slotIdB}`);

  assert.equal(slotDocA.activeAppointmentIds.includes('appt_movable'), false, 'Removed from Slot A');
  assert.equal(slotDocB.activeAppointmentIds.includes('appt_movable'), true, 'Added to Slot B');
  assert.deepEqual(slotDocB.activeAppointmentIds, ['appt_other', 'appt_movable']);
});

test('duplicate delivery of the same trigger event leaves the array unchanged', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_dup';
  const dateTime = '2026-10-06T03:30:00.000Z';
  const slotId = deriveSlotId(doctorId, dateTime);

  const event = {
    params: { appointmentId: 'appt_dup_1' },
    data: {
      before: { data: () => null },
      after: {
        data: () => ({ doctorId, dateTime, cancellationReason: null }),
      },
    },
  };

  // First delivery
  await reconcileAppointmentSlotHandler(event, db);
  const firstSlot = db.docs.get(`doctor_slots/${slotId}`);
  assert.deepEqual(firstSlot.activeAppointmentIds, ['appt_dup_1']);

  // Duplicate delivery of the exact same event
  await reconcileAppointmentSlotHandler(event, db);
  const secondSlot = db.docs.get(`doctor_slots/${slotId}`);
  assert.deepEqual(secondSlot.activeAppointmentIds, ['appt_dup_1'], 'Duplicate delivery must not duplicate ID');
});

test('patient double-booking the same slot is rejected', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_double';
  const dateTime = '2026-10-06T03:30:00.000Z';
  const slotId = deriveSlotId(doctorId, dateTime);

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Dave',
    specialization: 'Dermatology',
    verified: true,
    deactivated: false,
  });

  db.docs.set('users/user_greedy', {
    role: 'patient',
    name: 'Greedy Patient',
    profileId: 'patient_greedy',
  });

  // First booking by patient_greedy succeeds
  const firstBooking = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM' },
    { uid: 'user_greedy' },
    db,
  );
  assert.equal(firstBooking.ok, true);

  // Second booking by same patient in same slot is rejected
  await assert.rejects(
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM' },
      { uid: 'user_greedy' },
      db,
    ),
    { code: 'failed-precondition' },
  );
});

test('legacy direct write pushing slot over capacity sets slotOverflow: true and deletes nothing', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_overflow';
  const dateTime = '2026-10-06T03:30:00.000Z';
  const slotId = deriveSlotId(doctorId, dateTime);

  // Slot already has 3 bookings (full)
  db.docs.set(`doctor_slots/${slotId}`, {
    doctorId,
    date: '2026-10-06',
    time: '09:00',
    activeAppointmentIds: ['appt_1', 'appt_2', 'appt_3'],
    slotOverflow: false,
  });

  // A 4th appointment is created directly by legacy code
  await reconcileAppointmentSlotHandler(
    {
      params: { appointmentId: 'appt_legacy_4' },
      data: {
        before: { data: () => null },
        after: {
          data: () => ({ doctorId, dateTime, cancellationReason: null }),
        },
      },
    },
    db,
  );

  const slotDoc = db.docs.get(`doctor_slots/${slotId}`);
  assert.equal(slotDoc.activeAppointmentIds.length, 4, 'All 4 IDs must be preserved');
  assert.deepEqual(slotDoc.activeAppointmentIds, ['appt_1', 'appt_2', 'appt_3', 'appt_legacy_4']);
  assert.equal(slotDoc.slotOverflow, true, 'slotOverflow must be set to true');
});

test('bookAppointment rejects non-patients, unverified/deactivated doctors, and unavailable slots', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_valid';
  const dateTime = '2026-10-06T03:30:00.000Z'; // Tuesday 09:00 IST

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Valid',
    specialization: 'ENT',
    verified: true,
    deactivated: false,
  });

  // 1. Non-patient rejected
  db.docs.set('users/user_doc', { role: 'doctor', name: 'Dr. Other' });
  await assert.rejects(
    bookAppointmentHandler({ doctorId, dateTime }, { uid: 'user_doc' }, db),
    { code: 'permission-denied' },
  );

  // 2. Unverified doctor rejected
  db.docs.set('doctors/doc_unverified', { verified: false, deactivated: false });
  db.docs.set('users/user_p', { role: 'patient', name: 'Valid Patient' });
  await assert.rejects(
    bookAppointmentHandler({ doctorId: 'doc_unverified', dateTime }, { uid: 'user_p' }, db),
    { code: 'failed-precondition' },
  );

  // 3. Deactivated doctor rejected
  db.docs.set('doctors/doc_deactivated', { verified: true, deactivated: true });
  await assert.rejects(
    bookAppointmentHandler({ doctorId: 'doc_deactivated', dateTime }, { uid: 'user_p' }, db),
    { code: 'failed-precondition' },
  );

  // 4. Slot outside availability (e.g. Sunday when schedule is Mon-Fri)
  // 2026-10-04 is Sunday. 03:30 UTC = 09:00 IST.
  const sundayDateTime = '2026-10-04T03:30:00.000Z';
  await assert.rejects(
    bookAppointmentHandler({ doctorId, dateTime: sundayDateTime }, { uid: 'user_p' }, db),
    { code: 'failed-precondition' },
  );
});

test('bookAppointment ignores client-supplied patientId and binds strictly to authenticated user profile', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_auth_bound';
  const dateTime = '2026-10-06T03:30:00.000Z'; // Tuesday 09:00 IST

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Authentic',
    specialization: 'General',
    verified: true,
    deactivated: false,
  });

  // Legitimate user authenticated with profileId 'real_patient_id'
  db.docs.set('users/user_real', {
    role: 'patient',
    name: 'Real Patient',
    profileId: 'real_patient_id',
    mobile: '9876543210',
  });

  // Client attempts to spoof patientId by sending someone else's ID
  const result = await bookAppointmentHandler(
    {
      doctorId,
      dateTime,
      slotLabel: '09:00 AM',
      patientId: 'attacker_spoofed_victim_id',
      patientName: 'Spoofed Name',
    },
    { uid: 'user_real' },
    db,
  );

  assert.equal(result.ok, true);
  const createdAppt = db.docs.get(`appointments/${result.appointmentId}`);
  assert.equal(
    createdAppt.patientId,
    'real_patient_id',
    'patientId must be taken strictly from authenticated profile, not client input',
  );
  assert.notEqual(
    createdAppt.patientId,
    'attacker_spoofed_victim_id',
    'Client-supplied patientId must NEVER be trusted',
  );
});

test('bookAppointment callable enforces App Check when request.app is missing', async () => {
  // Callable level invocation without request.app
  const requestWithoutAppCheck = {
    auth: { uid: 'user_p' },
    data: { doctorId: 'doc_1', dateTime: '2026-10-06T03:30:00.000Z' },
  };

  await assert.rejects(
    bookAppointment.run(requestWithoutAppCheck),
    (err) => err.code === 'failed-precondition' && err.message.includes('App integrity check required'),
  );
});

test('reconcileAppointmentSlot skips malformed appointments (missing doctorId or dateTime) without throwing', async () => {
  const db = createConcurrentMockFirestore();

  // 1. Missing doctorId
  const malformed1 = {
    params: { appointmentId: 'appt_bad_doc' },
    data: {
      before: { data: () => null },
      after: {
        data: () => ({ doctorId: null, dateTime: '2026-10-06T03:30:00.000Z' }),
      },
    },
  };
  // Must complete cleanly without throwing
  await reconcileAppointmentSlotHandler(malformed1, db);

  // 2. Missing dateTime
  const malformed2 = {
    params: { appointmentId: 'appt_bad_dt' },
    data: {
      before: { data: () => null },
      after: {
        data: () => ({ doctorId: 'doc_valid', dateTime: null }),
      },
    },
  };
  await reconcileAppointmentSlotHandler(malformed2, db);

  // Verify no corrupt slot was written to doctor_slots
  assert.equal(db.docs.size, 0, 'No doctor_slot should be written for malformed appointments');
});

test('slotShareReason is required when slot already has 1 or 2 active bookings, but optional for empty slot', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_share_reason_test';
  const dateTime = '2026-10-06T03:30:00.000Z'; // Tuesday 09:00 IST
  const slotId = deriveSlotId(doctorId, dateTime);

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Shared Slot',
    specialization: 'General',
    verified: true,
    deactivated: false,
  });

  db.docs.set('users/user_p1', { role: 'patient', name: 'Patient 1', profileId: 'p_1' });
  db.docs.set('users/user_p2', { role: 'patient', name: 'Patient 2', profileId: 'p_2' });
  db.docs.set('users/user_p3', { role: 'patient', name: 'Patient 3', profileId: 'p_3' });

  // 1. First booking on empty slot succeeds WITHOUT slotShareReason
  const firstRes = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM' },
    { uid: 'user_p1' },
    db,
  );
  assert.equal(firstRes.ok, true);

  // 2. Second booking on same slot WITHOUT slotShareReason is REJECTED with invalid-argument
  await assert.rejects(
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM' },
      { uid: 'user_p2' },
      db,
    ),
    (err) => err.code === 'invalid-argument' && err.message.includes('reason for sharing this time slot'),
  );

  // 3. Second booking WITH slotShareReason SUCCEEDS
  const secondRes = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM', slotShareReason: 'Emergency family visit' },
    { uid: 'user_p2' },
    db,
  );
  assert.equal(secondRes.ok, true);

  // 4. In bookAppointment, client-supplied wasRescheduled is NOT honored (always false).
  // Therefore, booking on a shared slot with wasRescheduled: true but WITHOUT slotShareReason must be REJECTED.
  await assert.rejects(
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM', wasRescheduled: true },
      { uid: 'user_p3' },
      db,
    ),
    (err) => err.code === 'invalid-argument' && err.message.includes('reason for sharing this time slot'),
  );

  // 5. When slotShareReason is supplied along with wasRescheduled: true, booking succeeds,
  // but appointmentDoc.wasRescheduled is strictly false.
  const rescheduleRes = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM', wasRescheduled: true, slotShareReason: 'Emergency follow-up' },
    { uid: 'user_p3' },
    db,
  );
  assert.equal(rescheduleRes.ok, true);
  const createdAppt = db.docs.get(`appointments/${rescheduleRes.appointmentId}`);
  assert.equal(createdAppt.wasRescheduled, false, 'appointment.wasRescheduled must always be false in bookAppointment');

  // Slot should now have 3 active bookings
  const slotDoc = db.docs.get(`doctor_slots/${slotId}`);
  assert.equal(slotDoc.activeAppointmentIds.length, 3);
});

test('legacy appointment with token 5 raises counter so subsequent callable booking receives token 6', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_legacy_token';
  const dateTimeA = '2026-10-06T03:30:00.000Z'; // 09:00 IST
  const dateTimeB = '2026-10-06T03:45:00.000Z'; // 09:15 IST

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Legacy Token Test',
    specialization: 'Cardiology',
    verified: true,
    deactivated: false,
  });

  db.docs.set('users/user_p6', { role: 'patient', name: 'Patient Six', profileId: 'p_6' });

  // 1. Simulate legacy write creating an appointment with token 5
  // The reconcile trigger processes this creation
  await reconcileAppointmentSlotHandler(
    {
      params: { appointmentId: 'appt_legacy_token_5' },
      data: {
        before: { data: () => null },
        after: {
          data: () => ({
            doctorId,
            dateTime: dateTimeA,
            tokenNumber: 5,
            cancellationReason: null,
          }),
        },
      },
    },
    db,
  );

  const counterDoc = db.docs.get(`doctor_day_counters/${doctorId}_2026-10-06`);
  assert.equal(counterDoc.lastTokenNumber, 5, 'Counter must be raised to 5 by legacy appointment');

  // 2. Next callable booking must receive token 6
  const bookRes = await bookAppointmentHandler(
    { doctorId, dateTime: dateTimeB, slotLabel: '09:15 AM' },
    { uid: 'user_p6' },
    db,
  );

  assert.equal(bookRes.tokenNumber, 6, 'Callable must receive token 6');
  const apptDoc = db.docs.get(`appointments/${bookRes.appointmentId}`);
  assert.equal(apptDoc.tokenNumber, 6, 'Created appointment document must have token 6');
  const updatedCounter = db.docs.get(`doctor_day_counters/${doctorId}_2026-10-06`);
  assert.equal(updatedCounter.lastTokenNumber, 6, 'Counter must now be 6');
});

test('concurrent callables on different slots of one doctor-day get distinct sequential tokens', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_concurrent_tokens';
  const dateTime1 = '2026-10-06T03:30:00.000Z'; // 09:00 IST
  const dateTime2 = '2026-10-06T03:45:00.000Z'; // 09:15 IST

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Concurrent Tokens',
    specialization: 'Pediatrics',
    verified: true,
    deactivated: false,
  });

  db.docs.set('users/user_c1', { role: 'patient', name: 'Patient C1', profileId: 'p_c1' });
  db.docs.set('users/user_c2', { role: 'patient', name: 'Patient C2', profileId: 'p_c2' });

  // Fire concurrent bookings on 2 distinct slots
  const [res1, res2] = await Promise.all([
    bookAppointmentHandler({ doctorId, dateTime: dateTime1, slotLabel: '09:00 AM' }, { uid: 'user_c1' }, db),
    bookAppointmentHandler({ doctorId, dateTime: dateTime2, slotLabel: '09:15 AM' }, { uid: 'user_c2' }, db),
  ]);

  assert.equal(res1.ok, true);
  assert.equal(res2.ok, true);
  assert.notEqual(res1.tokenNumber, res2.tokenNumber, 'Concurrent bookings must get distinct tokens');

  const tokens = [res1.tokenNumber, res2.tokenNumber].sort();
  assert.deepEqual(tokens, [1, 2], 'Tokens must be sequential 1 and 2');

  const counter = db.docs.get(`doctor_day_counters/${doctorId}_2026-10-06`);
  assert.equal(counter.lastTokenNumber, 2);
});

test('cancelled appointment tokens are never reused by subsequent bookings', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_cancel_token';
  const dateTime = '2026-10-06T03:30:00.000Z';

  db.docs.set(`doctors/${doctorId}`, {
    name: 'Dr. Cancel Token',
    specialization: 'Dermatology',
    verified: true,
    deactivated: false,
  });

  db.docs.set('users/user_t1', { role: 'patient', name: 'Patient T1', profileId: 'p_t1' });
  db.docs.set('users/user_t2', { role: 'patient', name: 'Patient T2', profileId: 'p_t2' });

  // 1. First booking gets token 1
  const b1 = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM' },
    { uid: 'user_t1' },
    db,
  );
  assert.equal(b1.tokenNumber, 1);

  // 2. Appointment 1 is cancelled via trigger
  await reconcileAppointmentSlotHandler(
    {
      params: { appointmentId: b1.appointmentId },
      data: {
        before: { data: () => ({ doctorId, dateTime, cancellationReason: null, tokenNumber: 1 }) },
        after: { data: () => ({ doctorId, dateTime, cancellationReason: 'Patient cancelled', tokenNumber: 1 }) },
      },
    },
    db,
  );

  // 3. Second booking must get token 2, NOT reuse token 1
  const b2 = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM' },
    { uid: 'user_t2' },
    db,
  );
  assert.equal(b2.tokenNumber, 2, 'Token 1 must not be reused after cancellation');
});

test('booking abuse bucket limits uid to 10 calls per 60s and rejects the 11th call', async () => {
  const db = createConcurrentMockFirestore();
  const uid = 'uid_booking_rate_limit_test';
  const mockRequest = {
    auth: { uid },
    rawRequest: { ip: '192.168.1.100' },
  };

  // Limit for uid is 10
  assert.equal(LIMITS.booking.uid.max, 10);

  // 10 calls succeed
  for (let i = 1; i <= 10; i++) {
    await enforceAbuseLimit(db, mockRequest, 'booking');
  }

  // 11th call must be rejected
  await assert.rejects(
    enforceAbuseLimit(db, mockRequest, 'booking'),
    (err) => err.code === 'resource-exhausted',
  );
});

test('backfillSingleSlotTransaction ignores appointments cancelled between scan and apply', async () => {
  const db = createConcurrentMockFirestore();
  const doctorId = 'doc_backfill_cancel_test';
  const dateTime = '2026-10-06T03:30:00.000Z'; // 09:00 IST
  const slotId = deriveSlotId(doctorId, dateTime);

  // appt_1 remains active
  db.docs.set('appointments/appt_1', {
    doctorId,
    dateTime,
    cancellationReason: null,
  });

  // appt_2 was active at initial scan, but got cancelled before apply transaction runs
  db.docs.set('appointments/appt_2', {
    doctorId,
    dateTime,
    cancellationReason: 'Cancelled by patient',
  });

  const entry = {
    slotId,
    doctorId,
    date: '2026-10-06',
    time: '09:00',
    activeAppointmentIds: ['appt_1', 'appt_2'], // scanned with both
  };

  const result = await backfillSingleSlotTransaction(db, entry);

  assert.deepEqual(result.verifiedActiveIds, ['appt_1'], 'Cancelled appt_2 must be excluded');
  assert.equal(result.isOverflow, false);

  const slotDoc = db.docs.get(`doctor_slots/${slotId}`);
  assert.deepEqual(slotDoc.activeAppointmentIds, ['appt_1']);
});



