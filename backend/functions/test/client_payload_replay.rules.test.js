'use strict';

const fs = require('fs');
const path = require('path');
const { before, after, test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-doctornect-payload-replay';
const PATIENT_UID = 'patient_uid_1';
const PATIENT_ID = 'pat_1';
const DOCTOR_UID = 'doctor_uid_1';
const DOCTOR_ID = 'doc_1';
const STORE_UID = 'store_uid_1';
const STORE_ID = 'store_1';
const AMB_UID = 'amb_uid_1';
const AMB_ID = 'amb_1';
const APPT_ID = 'appt_replay_1';
const RX_ID = 'rx_replay_1';
const DELIV_ID = 'deliv_replay_1';

let testEnv;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('client payload replay rules (skipped: FIRESTORE_EMULATOR_HOST not set)', {
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

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    // 1. Seed users
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
    await db.collection('users').doc(AMB_UID).set({
      role: 'ambulance',
      profileId: AMB_ID,
    });

    // 2. Seed profile listings
    await db.collection('patients').doc(PATIENT_ID).set({
      ownerUid: PATIENT_UID,
      name: 'John Doe',
    });
    await db.collection('doctors').doc(DOCTOR_ID).set({
      ownerUid: DOCTOR_UID,
      verified: true,
      name: 'Dr. Doctor',
    });
    await db.collection('medical_stores').doc(STORE_ID).set({
      ownerUid: STORE_UID,
      verified: true,
      name: 'Store One',
    });
    await db.collection('ambulances').doc(AMB_ID).set({
      authUid: AMB_UID,
      serviceName: 'City Ambulance',
      username: 'ambdriver',
      isAvailable: true,
      verified: false,
      verificationStatus: 'registered',
      totalRating: 5.0,
      ratingCount: 1,
    });

    // 3. Seed care team link so doctorCanReadPatientClinicalData holds
    await db.collection('patients').doc(PATIENT_ID).collection('care_team').doc(DOCTOR_ID).set({
      access: true,
      status: 'active',
      doctorId: DOCTOR_ID,
    });

    // 4. Seed initial appointment
    await resetBaselineAppointment(db);
  });
});

const baselineAppointment = {
  appointmentId: APPT_ID,
  doctorId: DOCTOR_ID,
  doctorName: 'Dr. Doctor',
  specialization: 'Cardiology',
  patientId: PATIENT_ID,
  patientName: 'John Doe',
  patientAge: 30,
  patientGender: 'Male',
  dateTime: new Date('2026-10-15T04:30:00.000Z'),
  slotLabel: '10:00 AM',
  tokenNumber: 1,
  visitType: 'newVisit',
  patientStatus: 'confirmed',
  doctorStatus: 'confirmed',
  hasPrescription: false,
  hasReport: false,
  hasReview: false,
  labReports: [],
  chiefComplaints: [],
  symptoms: [],
  observations: [],
  wasRescheduled: false,
  createdAt: new Date('2026-10-12T00:00:00.000Z'),
  updatedAt: new Date('2026-10-12T00:00:00.000Z'),
};

async function resetBaselineAppointment(dbInstance) {
  if (dbInstance) {
    await dbInstance.collection('appointments').doc(APPT_ID).set(baselineAppointment);
  } else {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('appointments').doc(APPT_ID).set(baselineAppointment);
    });
  }
}

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

describe('HEAD Client Payload Replay Suite', () => {
  test('1. Patient cancel (cancelByPatient): payload replay', async () => {
    const patientDb = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = patientDb.collection('appointments').doc(APPT_ID);

    // Exact HEAD payload from AppointmentFirestoreMapper.toMap with SetOptions(merge: true)
    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'cancelled', // changed
      cancellationReason: 'Feeling better', // changed
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(), // changed
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('2. Doctor cancel: payload replay', async () => {
    // Reset appointment to confirmed baseline
    await resetBaselineAppointment();

    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('appointments').doc(APPT_ID);

    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'cancelled',
      cancellationReason: 'Doctor emergency',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('3. Doctor reschedule: payload replay', async () => {
    await resetBaselineAppointment();

    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('appointments').doc(APPT_ID);

    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-16T05:30:00.000Z'), // changed
      slotLabel: '11:00 AM', // changed
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: true, // changed
      updatedAt: new Date(), // changed
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('4. Doctor complete (saveConsultationOutcome): payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('appointments').doc(APPT_ID);

    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-16T05:30:00.000Z'),
      slotLabel: '11:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'completed', // changed
      diagnosis: 'Hypertension Stage 1', // changed
      clinicalNotes: 'Follow low sodium diet', // changed
      hasPrescription: true, // changed
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: true,
      updatedAt: new Date(), // changed
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('5. Walk-in create (addWalkInAppointment): payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const newId = 'pa_walkin_head';

    const payload = {
      appointmentId: 'APT12345',
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: 'wi_999',
      patientName: 'Walkin Patient',
      patientAge: 45,
      patientGender: 'Female',
      dateTime: new Date('2026-10-15T06:00:00.000Z'),
      slotLabel: '11:30 AM',
      tokenNumber: 2,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: ['Headache'],
      source: 'walkin',
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertSucceeds(docDb.collection('appointments').doc(newId).set(payload, { merge: true }));
  });

  test('6. Prescription create: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('prescriptions').doc(RX_ID);

    const payload = {
      prescriptionId: RX_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      clinicName: 'Heart Care Clinic',
      clinicAddress: '123 Main St',
      doctorPhone: '9876543210',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      appointmentId: APPT_ID,
      prescriptionDate: '2026-10-12T10:00:00.000Z',
      diagnosisType: 'Final',
      primaryDiagnosis: 'Hypertension',
      secondaryDiagnosis: '',
      chiefComplaint: 'Chest tightness',
      symptoms: 'Mild headache',
      symptomDuration: '3 days',
      pastHistory: 'None',
      allergies: 'Penicillin',
      generalExamination: 'Normal',
      vitals: {
        bloodPressure: '120/80',
        temperature: '98.6',
        pulse: '72',
        spo2: '99',
        weightKg: '70',
        heightCm: '175',
        respiratoryRate: '16',
      },
      medicines: [
        {
          id: 'med_1',
          name: 'Amlodipine 5mg',
          dosage: '5mg',
          form: 'Tablet',
          frequency: '1-0-0',
          quantity: 30,
          duration: '30 days',
          instructions: 'After breakfast',
          specialInstructions: '',
          isSos: false,
          substituteAllowed: true,
        },
      ],
      investigations: [
        {
          name: 'Lipid Profile',
          type: 'lab',
          group: 'Biochemistry',
          notes: 'Fasting 12 hrs',
        },
      ],
      advice: {
        diet: 'Low sodium',
        activity: '30 mins walking',
        lifestyle: 'Regular sleep',
        general: 'Drink plenty of water',
      },
      followUpNote: 'Review after 1 month',
      nextVisit: '2026-11-12T10:00:00.000Z',
      title: 'Hypertension',
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('7. Prescription update: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('prescriptions').doc(RX_ID);

    const payload = {
      prescriptionId: RX_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      clinicName: 'Heart Care Clinic',
      clinicAddress: '123 Main St',
      doctorPhone: '9876543210',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      appointmentId: APPT_ID,
      prescriptionDate: '2026-10-12T10:00:00.000Z',
      diagnosisType: 'Final',
      primaryDiagnosis: 'Essential Hypertension', // updated
      secondaryDiagnosis: '',
      chiefComplaint: 'Chest tightness',
      symptoms: 'Mild headache',
      symptomDuration: '3 days',
      pastHistory: 'None',
      allergies: 'Penicillin',
      generalExamination: 'Normal',
      vitals: {
        bloodPressure: '120/80',
        temperature: '98.6',
        pulse: '72',
        spo2: '99',
        weightKg: '70',
        heightCm: '175',
        respiratoryRate: '16',
      },
      medicines: [
        {
          id: 'med_1',
          name: 'Amlodipine 5mg',
          dosage: '5mg',
          form: 'Tablet',
          frequency: '1-0-0',
          quantity: 30,
          duration: '30 days',
          instructions: 'After breakfast',
          specialInstructions: '',
          isSos: false,
          substituteAllowed: true,
        },
      ],
      investigations: [],
      advice: {
        diet: 'Low sodium',
        activity: '30 mins walking',
        lifestyle: 'Regular sleep',
        general: 'Drink plenty of water',
      },
      followUpNote: 'Review after 1 month',
      nextVisit: '2026-11-12T10:00:00.000Z',
      title: 'Essential Hypertension',
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('8. Pharmacy delivery create (doctor): payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('pharmacy_deliveries').doc(DELIV_ID);

    const payload = {
      prescriptionId: RX_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      storeId: STORE_ID,
      storeName: 'Store One',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      status: 'pending',
      sentAt: new Date(),
      medicineCount: 1,
      medicineLines: [
        {
          medicineEntryId: 'med_1',
          availability: 'inStock',
          substituteName: '',
        },
      ],
      draft: {
        prescriptionId: RX_ID,
        doctorId: DOCTOR_ID,
        patientId: PATIENT_ID,
      },
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload));
  });

  test('9. Pharmacy delivery update (store): payload replay', async () => {
    const storeDb = testEnv.authenticatedContext(STORE_UID).firestore();
    const ref = storeDb.collection('pharmacy_deliveries').doc(DELIV_ID);

    const payload = {
      status: 'dispensed',
      viewedAt: new Date(),
      dispensedAt: new Date(),
      dispensingNotes: 'All medicines dispensed',
      medicineLines: [
        {
          medicineEntryId: 'med_1',
          availability: 'inStock',
          substituteName: '',
        },
      ],
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('10. community_medicines catalog add: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const payload = {
      name: 'Paracetamol 650mg',
      nameLower: 'paracetamol 650mg',
      dosageUnit: 'mg',
      form: 'Tablet',
      addedByDoctorId: DOCTOR_ID,
      addedAt: new Date(),
    };
    await assertSucceeds(docDb.collection('community_medicines').add(payload));
  });

  test('11. community_diagnoses catalog add: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const payload = {
      text: 'Acute Pharyngitis',
      textLower: 'acute pharyngitis',
      addedByDoctorId: DOCTOR_ID,
      addedAt: new Date(),
    };
    await assertSucceeds(docDb.collection('community_diagnoses').add(payload));
  });

  test('12. community_lab_tests catalog add: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const payload = {
      name: 'Complete Blood Count',
      nameLower: 'complete blood count',
      group: 'Hematology',
      addedByDoctorId: DOCTOR_ID,
      addedAt: new Date(),
    };
    await assertSucceeds(docDb.collection('community_lab_tests').add(payload));
  });

  test('13. community_radiology catalog add: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const payload = {
      name: 'Chest X-Ray PA View',
      nameLower: 'chest x-ray pa view',
      group: 'X-Ray',
      addedByDoctorId: DOCTOR_ID,
      addedAt: new Date(),
    };
    await assertSucceeds(docDb.collection('community_radiology').add(payload));
  });

  test('14. community_body_parts catalog add: payload replay', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const payload = {
      name: 'Right Knee Joint',
      nameLower: 'right knee joint',
      addedByDoctorId: DOCTOR_ID,
      addedAt: new Date(),
    };
    await assertSucceeds(docDb.collection('community_body_parts').add(payload));
  });

  test('15. ambulance updateAvailability: payload replay', async () => {
    const ambDb = testEnv.authenticatedContext(AMB_UID).firestore();
    const ref = ambDb.collection('ambulances').doc(AMB_ID);

    const payload = {
      isAvailable: false,
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('16. ambulance updateAmbulanceProfile: payload replay (fails if protected keys in diff)', async () => {
    const ambDb = testEnv.authenticatedContext(AMB_UID).firestore();
    const ref = ambDb.collection('ambulances').doc(AMB_ID);

    // Client merged.toMap() includes pin, totalRating, ratingCount, verified, etc.
    const failingPayload = {
      serviceName: 'City Ambulance Updated',
      ownerName: 'Owner Name',
      driverName: 'Driver Name',
      phone: '9876543210',
      vehicleNumber: 'MH01AB1234',
      ambulanceType: 'bls',
      username: 'ambdriver',
      city: 'Mumbai',
      serviceAreas: ['South Mumbai'],
      baseAddress: '123 Station Rd',
      licenseNumber: 'LIC123',
      insuranceNumber: 'INS456',
      hasOxygen: true,
      hasVentilator: false,
      hasStretcher: true,
      is24x7: true,
      pin: '123456', // protected key!
      totalRating: 5.0, // protected key!
      ratingCount: 1, // protected key!
      isAvailable: true,
      verified: false, // protected key!
      createdAt: '2026-10-12T00:00:00.000Z',
      address: {
        addressLine1: '123 Station Rd',
        addressLine2: '',
        country: 'India',
        state: 'Maharashtra',
        city: 'Mumbai',
        pinCode: '400001',
      },
    };

    // Fails because 'pin' is added/modified on root doc, and protected keys are diffed
    await assertFails(ref.set(failingPayload, { merge: true }));
  });

  test('17. ambulance registerAmbulance: payload replay', async () => {
    const newAmbUid = 'amb_new_uid_1';
    const newAmbId = 'amb_new_1';
    const ambDb = testEnv.authenticatedContext(newAmbUid).firestore();
    const ref = ambDb.collection('ambulances').doc(newAmbId);

    // Root doc payload created with includePrivateFields: false
    const rootPayload = {
      serviceName: 'Metro Ambulance',
      ownerName: 'Metro Owner',
      driverName: 'Metro Driver',
      phone: '9876543211',
      vehicleNumber: 'MH02CD5678',
      ambulanceType: 'als',
      username: 'metrodriver',
      city: 'Mumbai',
      serviceAreas: ['Andheri'],
      baseAddress: '456 Link Rd',
      licenseNumber: 'LIC789',
      insuranceNumber: 'INS012',
      hasOxygen: true,
      hasVentilator: true,
      hasStretcher: true,
      is24x7: true,
      totalRating: 0.0,
      ratingCount: 0,
      isAvailable: true,
      verified: false,
      createdAt: new Date(),
      address: {
        addressLine1: '456 Link Rd',
        addressLine2: '',
        country: 'India',
        state: 'Maharashtra',
        city: 'Mumbai',
        pinCode: '400053',
      },
      authUid: newAmbUid,
    };

    await assertSucceeds(ref.set(rootPayload));

    // Private settings doc payload
    const settingsPayload = {
      pin: '123456',
    };
    await assertSucceeds(ref.collection('private').doc('settings').set(settingsPayload, { merge: true }));
  });
});

describe('741cb46 Client Payload Replay Suite (lib/ paths)', () => {
  test('741cb46 patient cancel on existing doc ID', async () => {
    await resetBaselineAppointment();

    const patientDb = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = patientDb.collection('appointments').doc(APPT_ID);

    // 741cb46 AppointmentFirestoreMapper.toMap output for cancelByPatient
    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'cancelled',
      cancellationReason: 'Need to cancel',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('741cb46 patient cancel on mismatching/new doc ID fails', async () => {
    const patientDb = testEnv.authenticatedContext(PATIENT_UID).firestore();
    const ref = patientDb.collection('appointments').doc('pa1728000000000');

    const payload = {
      appointmentId: 'APT999',
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'cancelled',
      cancellationReason: 'Need to cancel',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertFails(ref.set(payload, { merge: true }));
  });

  test('741cb46 doctor cancel succeeds', async () => {
    await resetBaselineAppointment();

    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('appointments').doc(APPT_ID);

    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'cancelled',
      cancellationReason: 'Clinic closed',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('741cb46 doctor reschedule succeeds', async () => {
    await resetBaselineAppointment();

    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('appointments').doc(APPT_ID);

    const payload = {
      appointmentId: APPT_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      patientAge: 30,
      patientGender: 'Male',
      dateTime: new Date('2026-10-18T04:30:00.000Z'),
      slotLabel: '10:00 AM',
      tokenNumber: 1,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: [],
      symptoms: [],
      observations: [],
      wasRescheduled: true,
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });

  test('741cb46 walk-in create succeeds', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const newId = 'pa_walkin_741cb46';

    const payload = {
      appointmentId: 'APT741',
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      specialization: 'Cardiology',
      patientId: 'wi_741',
      patientName: 'Walkin Old',
      patientAge: 50,
      patientGender: 'Male',
      dateTime: new Date('2026-10-15T06:00:00.000Z'),
      slotLabel: '11:30 AM',
      tokenNumber: 3,
      visitType: 'newVisit',
      patientStatus: 'confirmed',
      doctorStatus: 'confirmed',
      hasPrescription: false,
      hasReport: false,
      hasReview: false,
      labReports: [],
      chiefComplaints: ['Cough'],
      source: 'walkin',
      symptoms: [],
      observations: [],
      wasRescheduled: false,
      updatedAt: new Date(),
    };

    await assertSucceeds(docDb.collection('appointments').doc(newId).set(payload, { merge: true }));
  });

  test('741cb46 pharmacy delivery create (doctor) succeeds', async () => {
    const docDb = testEnv.authenticatedContext(DOCTOR_UID).firestore();
    const ref = docDb.collection('pharmacy_deliveries').doc('deliv_741');

    const payload = {
      prescriptionId: RX_ID,
      doctorId: DOCTOR_ID,
      doctorName: 'Dr. Doctor',
      storeId: STORE_ID,
      storeName: 'Store One',
      patientId: PATIENT_ID,
      patientName: 'John Doe',
      status: 'pending',
      sentAt: new Date(),
      medicineCount: 1,
      medicineLines: [
        {
          medicineEntryId: 'med_1',
          availability: 'inStock',
          substituteName: '',
        },
      ],
      draft: {
        prescriptionId: RX_ID,
        doctorId: DOCTOR_ID,
        patientId: PATIENT_ID,
      },
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload));
  });

  test('741cb46 delivery update (store) succeeds', async () => {
    const storeDb = testEnv.authenticatedContext(STORE_UID).firestore();
    const ref = storeDb.collection('pharmacy_deliveries').doc('deliv_741');

    const payload = {
      status: 'dispensed',
      viewedAt: new Date(),
      dispensedAt: new Date(),
      dispensingNotes: 'Dispensed successfully',
      medicineLines: [
        {
          medicineEntryId: 'med_1',
          availability: 'inStock',
          substituteName: '',
        },
      ],
      updatedAt: new Date(),
    };

    await assertSucceeds(ref.set(payload, { merge: true }));
  });
});
