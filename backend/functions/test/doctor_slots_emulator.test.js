'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const {
  deriveSlotId,
  bookAppointmentHandler,
} = require('../appointment_slots');
const {
  backfillSingleSlotTransaction,
  scanAppointmentsForSlots,
} = require('../../scripts/backfill_doctor_slots');

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;

if (!EMULATOR_HOST) {
  test(
    'Firestore emulator race test (skipped: FIRESTORE_EMULATOR_HOST not set; run npm run test:doctor-slots-emulator)',
    { skip: 'FIRESTORE_EMULATOR_HOST not set' },
    () => {},
  );
} else {
  test('10 parallel bookAppointment calls at one empty slot: exactly 3 succeed, 7 get resource-exhausted, activeAppointmentIds has 3 entries', async (t) => {
    // Connect to Firestore emulator using demo project to guarantee zero production contact
    const appName = `emulator-race-${Date.now()}`;
    const app = admin.initializeApp(
      {
        projectId: 'demo-doctornect-slots',
      },
      appName,
    );

    t.after(async () => {
      await deleteApp(app);
    });

    const db = getFirestore(app);
    const doctorId = `doc_race_${Date.now()}`;
    // 2026-10-06 is a Tuesday (working day in default availability). 03:30 UTC = 09:00 IST.
    const dateTime = '2026-10-06T03:30:00.000Z';
    const slotId = deriveSlotId(doctorId, dateTime);

    // 1. Seed doctor profile: verified and not deactivated
    await db.collection('doctors').doc(doctorId).set({
      name: 'Dr. Concurrency Race',
      specialization: 'Internal Medicine',
      verified: true,
      deactivated: false,
    });

    // 2. Seed 10 distinct patient user profiles
    const patientUids = [];
    for (let i = 0; i < 10; i++) {
      const uid = `race_user_${Date.now()}_${i}`;
      patientUids.push(uid);
      await db.collection('users').doc(uid).set({
        role: 'patient',
        name: `Race Patient ${i}`,
        profileId: `patient_profile_${uid}`,
        mobile: `900000000${i}`,
      });
    }

    // 3. Fire 10 parallel bookAppointment calls at the same empty slot
    const calls = patientUids.map((uid) =>
      bookAppointmentHandler(
        {
          doctorId,
          dateTime,
          slotLabel: '09:00 AM',
          slotShareReason: 'Shared slot booking agreement',
        },
        { uid },
        db,
      ),
    );

    const settled = await Promise.allSettled(calls);

    const succeeded = settled.filter((r) => r.status === 'fulfilled');
    const rejected = settled.filter((r) => r.status === 'rejected');

    // 4. Assertions required:
    //    - exactly 3 succeed
    //    - 7 get resource-exhausted
    //    - activeAppointmentIds has exactly 3 entries
    assert.equal(succeeded.length, 3, 'Exactly 3 parallel calls must succeed');
    assert.equal(rejected.length, 7, 'Exactly 7 parallel calls must be rejected');

    for (const rej of rejected) {
      assert.equal(
        rej.reason?.code,
        'resource-exhausted',
        `Rejection code must be resource-exhausted, got: ${rej.reason?.code} (${rej.reason?.message})`,
      );
    }

    const slotSnap = await db.collection('doctor_slots').doc(slotId).get();
    assert.equal(slotSnap.exists, true, 'doctor_slots document must exist');
    const slotData = slotSnap.data();
    const activeAppointmentIds = slotData?.activeAppointmentIds || [];

    assert.equal(
      activeAppointmentIds.length,
      3,
      'activeAppointmentIds array must contain exactly 3 entries',
    );
    assert.equal(slotData?.slotOverflow, false, 'slotOverflow must remain false');

    // Confirm that the 3 succeeded appointment IDs match the entries in activeAppointmentIds
    const successfulApptIds = succeeded.map((s) => s.value.appointmentId);
    for (const apptId of successfulApptIds) {
      assert.ok(
        activeAppointmentIds.includes(apptId),
        `activeAppointmentIds must include succeeded appointment ${apptId}`,
      );
    }

    const tokens = succeeded.map((s) => s.value.tokenNumber);
    assert.equal(new Set(tokens).size, 3, 'All successful bookings on the same slot must have distinct token numbers');
  });

  test('concurrent callables on different slots of one doctor-day get distinct tokens', async (t) => {
    const appName = `emulator-distinct-tokens-${Date.now()}`;
    const app = admin.initializeApp(
      {
        projectId: 'demo-doctornect-tokens',
      },
      appName,
    );

    t.after(async () => {
      await deleteApp(app);
    });

    const db = getFirestore(app);
    const doctorId = `doc_tokens_${Date.now()}`;
    // 2026-10-06 is a Tuesday. 5 different time slots on the same day:
    // 03:30 (09:00 IST), 04:00 (09:30 IST), 04:30 (10:00 IST), 05:00 (10:30 IST), 05:30 (11:00 IST)
    const slotTimes = [
      { dateTime: '2026-10-06T03:30:00.000Z', slotLabel: '09:00 AM' },
      { dateTime: '2026-10-06T04:00:00.000Z', slotLabel: '09:30 AM' },
      { dateTime: '2026-10-06T04:30:00.000Z', slotLabel: '10:00 AM' },
      { dateTime: '2026-10-06T05:00:00.000Z', slotLabel: '10:30 AM' },
      { dateTime: '2026-10-06T05:30:00.000Z', slotLabel: '11:00 AM' },
    ];

    // 1. Seed doctor profile
    await db.collection('doctors').doc(doctorId).set({
      name: 'Dr. Multi Slot Tokens',
      specialization: 'General Medicine',
      verified: true,
      deactivated: false,
    });

    // 2. Seed 5 patient profiles
    const patientUids = [];
    for (let i = 0; i < 5; i++) {
      const uid = `token_user_${Date.now()}_${i}`;
      patientUids.push(uid);
      await db.collection('users').doc(uid).set({
        role: 'patient',
        name: `Token Patient ${i}`,
        profileId: `patient_profile_${uid}`,
        mobile: `911111111${i}`,
      });
    }

    // 3. Fire 5 parallel bookings across different slots on the same doctor-day
    const results = await Promise.all(
      slotTimes.map((slot, idx) =>
        bookAppointmentHandler(
          {
            doctorId,
            dateTime: slot.dateTime,
            slotLabel: slot.slotLabel,
          },
          { uid: patientUids[idx] },
          db,
        ),
      ),
    );

    const tokens = results.map((r) => r.tokenNumber);
    assert.equal(tokens.length, 5);
    assert.equal(new Set(tokens).size, 5, 'All concurrent bookings must receive distinct tokens');

    const counterSnap = await db.collection('doctor_day_counters').doc(`${doctorId}_2026-10-06`).get();
    assert.equal(counterSnap.exists, true);
    assert.equal(counterSnap.data()?.lastTokenNumber, 5);
  });

  test('backfill: real Timestamp values in Firestore emulator verify active included, cancelled excluded, moved-slot excluded', async (t) => {
    const appName = `emulator-backfill-${Date.now()}`;
    const app = admin.initializeApp(
      {
        projectId: 'demo-doctornect-backfill',
      },
      appName,
    );

    t.after(async () => {
      await deleteApp(app);
    });

    const db = getFirestore(app);
    const doctorId = `doc_bf_${Date.now()}`;
    // 03:30 UTC = 09:00 IST on 2026-10-06
    const dt9amUtc = new Date('2026-10-06T03:30:00.000Z');
    const slotId9am = deriveSlotId(doctorId, dt9amUtc.toISOString());

    // 04:30 UTC = 10:00 IST on 2026-10-06
    const dt10amUtc = new Date('2026-10-06T04:30:00.000Z');
    const slotId10am = deriveSlotId(doctorId, dt10amUtc.toISOString());

    const apptActiveId = `appt_active_${Date.now()}`;
    const apptCancelledId = `appt_cancelled_${Date.now()}`;
    const apptMovedId = `appt_moved_${Date.now()}`;

    // 1. Seed with REAL Firestore Timestamp objects
    // apptActive: active for 09:00 slot
    await db.collection('appointments').doc(apptActiveId).set({
      doctorId,
      dateTime: Timestamp.fromDate(dt9amUtc),
      cancellationReason: null,
      patientId: 'patient_1',
    });

    // apptCancelled: in 09:00 slot, but has cancellationReason
    await db.collection('appointments').doc(apptCancelledId).set({
      doctorId,
      dateTime: Timestamp.fromDate(dt9amUtc),
      cancellationReason: 'Patient cancelled consultation',
      patientId: 'patient_2',
    });

    // apptMoved: moved to 10:00 slot
    await db.collection('appointments').doc(apptMovedId).set({
      doctorId,
      dateTime: Timestamp.fromDate(dt10amUtc),
      cancellationReason: null,
      patientId: 'patient_3',
    });

    // 2. Run dry-run scan on this real Firestore emulator data
    const dryRunReport = await scanAppointmentsForSlots(db);
    assert.equal(dryRunReport.totalScanned, 3);
    assert.equal(dryRunReport.activeCount, 2, 'Two active appointments across the system');
    assert.equal(dryRunReport.cancelledCount, 1, 'One cancelled appointment skipped');
    assert.equal(dryRunReport.invalidCount, 0);

    const slot9amScan = dryRunReport.slotMap.get(slotId9am);
    assert.ok(slot9amScan, '09:00 slot exists in dry-run scan');
    assert.deepEqual(slot9amScan.activeAppointmentIds, [apptActiveId]);

    const slot10amScan = dryRunReport.slotMap.get(slotId10am);
    assert.ok(slot10amScan, '10:00 slot exists in dry-run scan');
    assert.deepEqual(slot10amScan.activeAppointmentIds, [apptMovedId]);

    // 3. Test slot apply transaction for 09:00 slot:
    // Pass candidate list containing all three IDs (simulating stale scan or dirty candidates)
    const applyResult = await backfillSingleSlotTransaction(db, {
      slotId: slotId9am,
      doctorId,
      date: '2026-10-06',
      time: '09:00',
      activeAppointmentIds: [apptActiveId, apptCancelledId, apptMovedId],
    });

    // Assert: only apptActive is included!
    assert.deepEqual(
      applyResult.verifiedActiveIds,
      [apptActiveId],
      'Cancelled appointment and moved appointment must be excluded from 09:00 slot',
    );
    assert.equal(applyResult.isOverflow, false);

    // Verify stored document in doctor_slots
    const slotSnap = await db.collection('doctor_slots').doc(slotId9am).get();
    assert.equal(slotSnap.exists, true);
    assert.deepEqual(slotSnap.data()?.activeAppointmentIds, [apptActiveId]);
    assert.equal(slotSnap.data()?.slotOverflow, false);
  });
}
