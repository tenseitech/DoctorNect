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
} = require('../appointment_slots');

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

  function readDoc(key) {
    const data = docs.get(key);
    return data == null ? null : JSON.parse(JSON.stringify(data));
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

  // Two concurrent calls
  const [res3, res4] = await Promise.allSettled([
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM' },
      { uid: 'user_p3' },
      db,
    ),
    bookAppointmentHandler(
      { doctorId, dateTime, slotLabel: '09:00 AM' },
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

  // Now Patient 4 books -> must succeed
  const bookRes = await bookAppointmentHandler(
    { doctorId, dateTime, slotLabel: '09:00 AM' },
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

