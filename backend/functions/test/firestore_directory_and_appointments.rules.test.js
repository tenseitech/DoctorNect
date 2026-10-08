'use strict';

const fs = require('fs');
const path = require('path');
const { before, after, beforeEach, test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-doctornect-dir-appt-rules';
const PATIENT_UID = 'patient_uid_1';
const PATIENT_ID = 'pat_1';
const DOCTOR_UID = 'doctor_uid_1';
const DOCTOR_ID = 'doc_1';
const UNVERIFIED_DOCTOR_ID = 'doc_unverified';
const STORE_UID = 'store_uid_1';
const STORE_ID = 'store_1';
const LAB_UID = 'lab_uid_1';
const LAB_ID = 'lab_1';
const AMB_UID = 'amb_uid_1';
const AMB_ID = 'amb_1';
const ADMIN_UID = 'admin_uid_1';
const APPT_ID = 'appt_1';

let testEnv;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('directory/appointment rules (skipped: FIRESTORE_EMULATOR_HOST not set)', {
    skip: 'FIRESTORE_EMULATOR_HOST not set; run firebase emulators:exec',
  }, () => {});
  return;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('users').doc(PATIENT_UID).set({
      role: 'patient',
      profileId: PATIENT_ID,
    });
    await db.collection('users').doc(DOCTOR_UID).set({
      role: 'doctor',
      profileId: DOCTOR_ID,
    });
    await db.collection('users').doc(STORE_UID).set({
      role: 'medicalStore',
      profileId: STORE_ID,
    });
    await db.collection('users').doc(LAB_UID).set({
      role: 'lab',
      profileId: LAB_ID,
    });
    await db.collection('users').doc(AMB_UID).set({
      role: 'ambulance',
      profileId: AMB_ID,
    });
    await db.collection('users').doc(ADMIN_UID).set({
      role: 'super_admin',
      profileId: 'admin',
    });
    await db.collection('doctors').doc(DOCTOR_ID).set({
      doctorId: DOCTOR_ID,
      ownerUid: DOCTOR_UID,
      verified: true,
      name: 'Dr Verified',
    });
    await db.collection('doctors').doc(UNVERIFIED_DOCTOR_ID).set({
      doctorId: UNVERIFIED_DOCTOR_ID,
      ownerUid: 'other',
      verified: false,
      name: 'Dr Pending',
    });
    await db.collection('medical_stores').doc(STORE_ID).set({
      storeId: STORE_ID,
      ownerUid: STORE_UID,
      verified: true,
    });
    await db.collection('medical_stores').doc('store_unverified').set({
      storeId: 'store_unverified',
      verified: false,
    });
    await db.collection('labs').doc(LAB_ID).set({
      labId: LAB_ID,
      ownerUid: LAB_UID,
      verified: true,
    });
    await db.collection('labs').doc('lab_unverified').set({
      labId: 'lab_unverified',
      verified: false,
    });
    await db.collection('appointments').doc(APPT_ID).set({
      appointmentId: APPT_ID,
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
      dateTime: new Date('2026-10-08T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      patientStatus: 'pending',
      doctorStatus: 'pendingRequest',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
    });
  });
}

describe('directory list rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  test('unauthenticated doctors list with verified==true and limit 100 is allowed', async () => {
    const anon = testEnv.unauthenticatedContext();
    const snap = await assertSucceeds(
      anon.firestore().collection('doctors').where('verified', '==', true).limit(100).get(),
    );
    assert.equal(snap.docs.every((d) => d.data().verified === true), true);
    assert.equal(snap.docs.some((d) => d.id === UNVERIFIED_DOCTOR_ID), false);
  });

  test('unauthenticated doctors list without verified filter is denied', async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(anon.firestore().collection('doctors').limit(100).get());
  });

  test('super admin can list unverified doctors', async () => {
    const admin = testEnv.authenticatedContext(ADMIN_UID);
    const snap = await assertSucceeds(
      admin.firestore().collection('doctors').limit(100).get(),
    );
    assert.ok(snap.docs.some((d) => d.id === UNVERIFIED_DOCTOR_ID));
  });

  test('signed-in medical_stores and labs lists require verified==true', async () => {
    const patient = testEnv.authenticatedContext(PATIENT_UID);
    await assertSucceeds(
      patient.firestore().collection('medical_stores').where('verified', '==', true).limit(100).get(),
    );
    await assertFails(patient.firestore().collection('medical_stores').limit(100).get());
    await assertSucceeds(
      patient.firestore().collection('labs').where('verified', '==', true).limit(100).get(),
    );
    await assertFails(patient.firestore().collection('labs').limit(100).get());
  });

  test('unauthenticated council-number lookup with verified filter and limit 1 is allowed', async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertSucceeds(
      anon.firestore()
        .collection('doctors')
        .where('verified', '==', true)
        .where('councilNumber', '==', 'MCI-1')
        .limit(1)
        .get(),
    );
  });

  test('super admin can list unverified medical_stores and labs', async () => {
    const admin = testEnv.authenticatedContext(ADMIN_UID);
    const stores = await assertSucceeds(
      admin.firestore().collection('medical_stores').limit(100).get(),
    );
    const labs = await assertSucceeds(
      admin.firestore().collection('labs').limit(100).get(),
    );
    assert.ok(stores.docs.some((d) => d.id === 'store_unverified'));
    assert.ok(labs.docs.some((d) => d.id === 'lab_unverified'));
  });
});

describe('promotedAds provider role rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  function draft(providerId) {
    return {
      adId: `ad_${providerId}`,
      providerType: 'doctor',
      providerId,
      title: 'Promo',
      description: 'Desc',
      imageUrl: 'https://example.com/a.jpg',
      imageKey: `promoted_ads/${providerId}/ad1/banner.jpg`,
      imageStorage: 's3',
      ctaLabel: 'Book',
      durationHours: 24,
      amountPaid: 300,
      paymentStatus: 'pending',
      status: 'draft',
      createdAt: new Date(),
    };
  }

  test('doctor, medicalStore, lab, ambulance can create; patient cannot', async () => {
    await assertSucceeds(
      testEnv.authenticatedContext(DOCTOR_UID).firestore().collection('promotedAds').doc('ad_doc').set(draft(DOCTOR_UID)),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(STORE_UID).firestore().collection('promotedAds').doc('ad_store').set({
        ...draft(STORE_UID),
        providerType: 'pharmacy',
      }),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(LAB_UID).firestore().collection('promotedAds').doc('ad_lab').set({
        ...draft(LAB_UID),
        providerType: 'lab',
      }),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(AMB_UID).firestore().collection('promotedAds').doc('ad_amb').set({
        ...draft(AMB_UID),
        providerType: 'ambulance',
      }),
    );
    await assertFails(
      testEnv.authenticatedContext(PATIENT_UID).firestore().collection('promotedAds').doc('ad_pat').set(draft(PATIENT_UID)),
    );
  });
});

describe('patient appointment create', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  // Mirrors AppointmentFirestoreMapper.toMap from SharedAppointmentsStore.addBooking
  // (direct client .set, not the unused bookAppointment Cloud Function).
  function patientCreatePayload() {
    return {
      appointmentId: 'appt_new_1',
      doctorId: DOCTOR_ID,
      doctorName: 'Dr Verified',
      specialization: 'General Physician',
      patientId: PATIENT_ID,
      patientName: 'Pat One',
      patientAge: 32,
      patientGender: 'Female',
      dateTime: new Date('2026-10-11T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 3,
      visitType: 'newVisit',
      patientStatus: 'pending',
      doctorStatus: 'pendingRequest',
      clinicName: 'Clinic',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: ['fever'],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };
  }

  test('signed-in patient can create appointment with mapper payload', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertSucceeds(
      db.collection('appointments').doc('appt_new_1').set(patientCreatePayload()),
    );
  });

  test('patient cannot create appointment for another patientId', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertFails(
      db.collection('appointments').doc('appt_stolen').set({
        ...patientCreatePayload(),
        appointmentId: 'appt_stolen',
        patientId: 'other_patient',
      }),
    );
  });

  test('patient create without dateTime is denied', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const payload = patientCreatePayload();
    delete payload.dateTime;
    await assertFails(
      db.collection('appointments').doc('appt_nodt').set({
        ...payload,
        appointmentId: 'appt_nodt',
      }),
    );
  });
});

describe('appointment update key restrictions', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  test('patient cancel/reschedule/review keys are allowed', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertSucceeds(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Plans changed',
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      dateTime: new Date('2026-10-09T04:30:00.000Z'),
      slotLabel: '11:00 AM',
      tokenNumber: 2,
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      hasReview: true,
      reviewRating: 5,
      reviewId: `${PATIENT_ID}_${DOCTOR_ID}`,
      reviewCreatedAt: new Date(),
      updatedAt: new Date(),
    }));
  });

  test('patient cannot tamper with diagnosis, prescription flag, or ids', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({ diagnosis: 'hacked' }));
    await assertFails(ref.update({ hasPrescription: true }));
    await assertFails(ref.update({ clinicalNotes: 'nope' }));
    await assertFails(ref.update({ patientId: 'other_patient' }));
    await assertFails(ref.update({ doctorId: 'other_doctor' }));
  });

  test('doctor accept/complete/notes/prescription keys are allowed', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertSucceeds(ref.update({
      doctorStatus: 'confirmed',
      patientStatus: 'confirmed',
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      doctorStatus: 'completed',
      patientStatus: 'confirmed',
      diagnosis: 'Viral fever',
      clinicalNotes: 'Rest',
      hasPrescription: true,
      chiefComplaints: ['fever'],
      symptoms: ['cough'],
      observations: ['nad'],
      hasReport: true,
      labReports: ['CBC'],
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Clinic closed',
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      dateTime: new Date('2026-10-10T04:30:00.000Z'),
      slotLabel: '12:00 PM',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }));
  });

  test('doctor cannot change patientId/doctorId, review fields, or fees', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({ patientId: 'stolen' }));
    await assertFails(ref.update({ doctorId: 'stolen' }));
    await assertFails(ref.update({ hasReview: true, reviewRating: 1 }));
    await assertFails(ref.update({ fee: 1 }));
    await assertFails(ref.update({ consultationFee: 999 }));
  });

  test('patient cannot change fee or status fields reserved for doctors', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({ fee: 0 }));
    await assertFails(ref.update({ consultationFee: 0 }));
    await assertFails(ref.update({ hasReport: true }));
  });
});
