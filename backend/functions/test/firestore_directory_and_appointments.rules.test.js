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

  async function seedAd(id, status, providerId) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('promotedAds').doc(id).set({
        ...draft(providerId),
        adId: id,
        status,
      });
    });
  }

  test('non-owner cannot read draft, pending_payment, or pending_approval ads', async () => {
    await seedAd('ad_draft', 'draft', DOCTOR_UID);
    await seedAd('ad_pay', 'pending_payment', DOCTOR_UID);
    await seedAd('ad_review', 'pending_approval', DOCTOR_UID);
    const patient = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const stranger = testEnv.authenticatedContext(STORE_UID).firestore();
    for (const id of ['ad_draft', 'ad_pay', 'ad_review']) {
      await assertFails(patient.collection('promotedAds').doc(id).get());
      await assertFails(stranger.collection('promotedAds').doc(id).get());
    }
  });

  test('owner and super admin can read a pending ad; active ads are readable', async () => {
    await seedAd('ad_review', 'pending_approval', DOCTOR_UID);
    await seedAd('ad_live', 'active', DOCTOR_UID);
    await assertSucceeds(
      testEnv.authenticatedContext(DOCTOR_UID).firestore().collection('promotedAds').doc('ad_review').get(),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(ADMIN_UID).firestore().collection('promotedAds').doc('ad_review').get(),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(PATIENT_UID).firestore().collection('promotedAds').doc('ad_live').get(),
    );
    await assertSucceeds(
      testEnv.authenticatedContext(PATIENT_UID).firestore()
        .collection('promotedAds')
        .where('status', '==', 'active')
        .get(),
    );
  });
});

describe('patient appointment create', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  // Direct client create is denied. bookAppointment (Admin SDK) is the patient path.
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

  test('signed-in patient cannot create an appointment directly', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertFails(
      db.collection('appointments').doc('appt_new_1').set(patientCreatePayload()),
    );
  });

  test('verified doctor can still create a walk-in appointment', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(
      db.collection('appointments').doc('wi_appt').set({
        appointmentId: 'wi_appt',
        doctorId: DOCTOR_UID,
        patientId: 'wi1710000000000',
        source: 'walkin',
        dateTime: new Date('2026-10-11T04:30:00.000Z'),
      }),
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

  test('patient cancel and reschedule update the existing document and cannot create another', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const existing = db.collection('appointments').doc(APPT_ID);
    await assertFails(existing.set({
      dateTime: new Date('2026-10-09T05:30:00.000Z'),
      slotLabel: '11:00 AM',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }, { merge: true }));
    await assertSucceeds(existing.set({
      doctorStatus: 'cancelled',
      cancellationReason: 'Plans changed',
      updatedAt: new Date(),
    }, { merge: true }));
    await assertFails(
      db.collection('appointments').doc('appt_second').set(patientCreatePayload()),
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
    await assertFails(ref.update({
      dateTime: new Date('2026-10-09T04:30:00.000Z'),
      slotLabel: '11:00 AM',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Plans changed',
      updatedAt: new Date(),
    }));
    await assertFails(ref.update({
      hasReview: true,
      reviewRating: 5,
      reviewId: `${PATIENT_ID}_${DOCTOR_ID}`,
      reviewCreatedAt: new Date(),
      updatedAt: new Date(),
    }));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('appointments').doc(APPT_ID).update({
        doctorStatus: 'completed',
      });
    });
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

describe('tightened appointment rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
  });

  test('patient create is denied, including set(merge) on a missing document', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertFails(db.collection('appointments').doc('missing_appt').set({
      doctorId: DOCTOR_ID,
      patientId: PATIENT_ID,
      source: 'app',
    }, { merge: true }));
  });

  test('doctor walk-in create is allowed only for their uid and without createdVia', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc('wi_ok').set({
      source: 'walkin',
      doctorId: DOCTOR_UID,
      patientId: 'wi1',
    }));
    await assertFails(db.collection('appointments').doc('wi_other').set({
      source: 'walkin',
      doctorId: 'someone_else',
      patientId: 'wi2',
    }));
    await assertFails(db.collection('appointments').doc('wi_via').set({
      source: 'walkin',
      doctorId: DOCTOR_UID,
      patientId: 'wi3',
      createdVia: 'bookAppointment',
    }));
  });

  test('patient cancel, reschedule, and review are allowed', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({
      dateTime: new Date('2026-10-12T04:30:00.000Z'),
      slotLabel: '11:00 AM',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Plans changed',
      updatedAt: new Date(),
    }));
    await assertFails(ref.update({
      hasReview: true,
      reviewRating: 4,
      reviewId: 'rev_1',
      reviewCreatedAt: new Date(),
      updatedAt: new Date(),
    }));
  });

  test('patient review is allowed only after the appointment is completed', async () => {
    const patient = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = patient.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({
      hasReview: true,
      reviewRating: 5,
      reviewId: 'rev_1',
      reviewCreatedAt: new Date(),
      updatedAt: new Date(),
    }));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('appointments').doc(APPT_ID).update({
        doctorStatus: 'completed',
      });
    });
    await assertSucceeds(ref.update({
      hasReview: true,
      reviewRating: 5,
      reviewId: 'rev_1',
      reviewCreatedAt: new Date(),
      updatedAt: new Date(),
    }));
    await assertFails(ref.update({ reviewRating: 0, updatedAt: new Date() }));
    await assertFails(ref.update({ reviewRating: 6, updatedAt: new Date() }));
  });

  test('patient reschedule is denied and cancel depends on doctorStatus', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({
      dateTime: new Date('2026-10-12T04:30:00.000Z'),
      slotLabel: '11:00 AM',
      tokenNumber: 8,
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      wasRescheduled: true,
      updatedAt: new Date(),
    }));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('appointments').doc(APPT_ID).update({
        doctorStatus: 'completed',
      });
    });
    await assertFails(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'too late',
      updatedAt: new Date(),
    }));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('appointments').doc(APPT_ID).update({
        doctorStatus: 'confirmed',
      });
    });
    await assertSucceeds(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Plans changed',
      updatedAt: new Date(),
    }));
  });

  test('invalid status and a doctor cancel with an extra key are denied', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({
      doctorStatus: 'not-a-status',
      patientStatus: 'confirmed',
      updatedAt: new Date(),
    }));
    await assertFails(ref.update({
      doctorStatus: 'cancelled',
      cancellationReason: 'Clinic closed',
      diagnosis: 'extra',
      updatedAt: new Date(),
    }));
  });

  test('patient cannot change doctorId, createdVia, tokenNumber, or status to completed', async () => {
    const db = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.update({ doctorId: 'other' }));
    await assertFails(ref.update({ createdVia: 'bookAppointment' }));
    await assertFails(ref.update({ tokenNumber: 9 }));
    await assertFails(ref.update({ doctorStatus: 'completed', updatedAt: new Date() }));
  });

  test('each doctor clinical update is allowed and patientId is not', async () => {
    const db = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertSucceeds(ref.update({
      doctorStatus: 'confirmed',
      patientStatus: 'confirmed',
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({ chiefComplaints: ['fever'], updatedAt: new Date() }));
    await assertSucceeds(ref.update({ observations: ['nad'], updatedAt: new Date() }));
    await assertSucceeds(ref.update({ symptoms: ['cough'], updatedAt: new Date() }));
    await assertSucceeds(ref.update({
      labReports: ['CBC'],
      hasReport: true,
      updatedAt: new Date(),
    }));
    await assertSucceeds(ref.update({
      diagnosis: 'Viral fever',
      clinicalNotes: 'Rest',
      hasPrescription: true,
      doctorStatus: 'completed',
      patientStatus: 'confirmed',
      updatedAt: new Date(),
    }));
    await assertFails(ref.update({ patientId: 'stolen' }));
  });

  test('another signed-in user cannot read or update the appointment', async () => {
    const db = testEnv.authenticatedContext(STORE_UID).firestore();
    const ref = db.collection('appointments').doc(APPT_ID);
    await assertFails(ref.get());
    await assertFails(ref.update({ doctorStatus: 'cancelled' }));
  });
});

describe('prescription, delivery, and ambulance party rules', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.collection('prescriptions').doc('rx_1').set({
        prescriptionId: 'rx_1',
        patientId: PATIENT_ID,
        doctorId: DOCTOR_ID,
        title: 'Prescription',
      });
      await db.collection('pharmacy_deliveries').doc('del_1').set({
        prescriptionId: 'rx_1',
        doctorId: DOCTOR_ID,
        storeId: STORE_ID,
        patientId: PATIENT_ID,
        status: 'sent',
      });
      await db.collection('ambulances').doc(AMB_ID).set({
        authUid: AMB_UID,
        username: 'driver1',
        serviceName: 'City Ambulance',
        isAvailable: true,
      });
    });
  });

  test('unrelated signed-in user cannot read or write a prescription', async () => {
    const db = testEnv.authenticatedContext(STORE_UID).firestore();
    const ref = db.collection('prescriptions').doc('rx_1');
    await assertFails(ref.get());
    await assertFails(ref.set({
      prescriptionId: 'rx_1',
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
      title: 'nope',
    }));
  });

  test('patient can read their prescription and the doctor can update the title', async () => {
    const patient = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertSucceeds(patient.collection('prescriptions').doc('rx_1').get());
    await assertFails(patient.collection('prescriptions').doc('rx_1').update({ title: 'changed' }));

    const doctor = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(doctor.collection('prescriptions').doc('rx_1').update({
      title: 'Viral fever',
    }));
    await assertSucceeds(doctor.collection('prescriptions').doc('rx_new').set({
      prescriptionId: 'rx_new',
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
    }));
  });

  test('unrelated signed-in user cannot read or write a pharmacy delivery', async () => {
    const db = testEnv.authenticatedContext(LAB_UID).firestore();
    const ref = db.collection('pharmacy_deliveries').doc('del_1');
    await assertFails(ref.get());
    await assertFails(ref.update({ status: 'viewed' }));
  });

  test('patient can read a delivery and the store can update its status', async () => {
    const patient = testEnv.authenticatedContext(PATIENT_UID).firestore();
    await assertSucceeds(patient.collection('pharmacy_deliveries').doc('del_1').get());

    const store = testEnv.authenticatedContext(STORE_UID).firestore();
    await assertSucceeds(store.collection('pharmacy_deliveries').doc('del_1').update({
      status: 'viewed',
    }));

    const doctor = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(doctor.collection('pharmacy_deliveries').doc('del_new').set({
      doctorId: DOCTOR_ID,
      patientId: PATIENT_ID,
      storeId: STORE_ID,
      status: 'sent',
    }));
  });

  test('unrelated signed-in user cannot read or write an ambulance', async () => {
    const db = testEnv.authenticatedContext(LAB_UID).firestore();
    const ref = db.collection('ambulances').doc(AMB_ID);
    await assertFails(ref.get());
    await assertFails(ref.update({ isAvailable: false }));
  });

  test('the driver can read their ambulance and update availability', async () => {
    const db = testEnv.authenticatedContext(AMB_UID).firestore();
    const ref = db.collection('ambulances').doc(AMB_ID);
    await assertSucceeds(ref.get());
    await assertSucceeds(ref.update({ isAvailable: false }));
  });
});
