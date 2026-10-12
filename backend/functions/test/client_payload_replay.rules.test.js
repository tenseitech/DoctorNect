'use strict';

const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const { before, after, test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID_HEAD = 'demo-replay-head';
const PROJECT_ID_LIVE = 'demo-replay-live';

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

let testEnvHead;
let testEnvLive;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('client payload replay rules (skipped: FIRESTORE_EMULATOR_HOST not set)', {
    skip: 'FIRESTORE_EMULATOR_HOST not set; run firebase emulators:exec',
  }, () => {});
  return;
}

function getLiveRules() {
  const scratchPath = path.resolve(
    'C:/Users/khije/.gemini/antigravity-ide/brain/3f22e75d-e991-48d4-a39e-16b42fef7950/scratch/firestore.rules.7e0ab46'
  );
  if (fs.existsSync(scratchPath)) {
    return fs.readFileSync(scratchPath, 'utf8');
  }
  return cp.execSync('git show 7e0ab46:backend/firestore.rules', { encoding: 'utf8' });
}

// Build baseline appointment document matching Admin SDK writer (bookAppointment in appointment_slots.js)
function buildCallableBaselineAppointment(overrides = {}) {
  return {
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
    createdVia: 'bookAppointment', // Server-only Admin SDK field
    createdAt: new Date('2026-10-12T00:00:00.000Z'), // Server timestamp representation
    updatedAt: new Date('2026-10-12T00:00:00.000Z'),
    ...overrides,
  };
}

async function seedEnvironment(env) {
  await env.withSecurityRulesDisabled(async (context) => {
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

    // 4. Seed initial callable-created appointment
    await db.collection('appointments').doc(APPT_ID).set(buildCallableBaselineAppointment());
  });
}

async function resetAppointmentDoc(env, customFields = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('appointments').doc(APPT_ID).set(
      buildCallableBaselineAppointment(customFields)
    );
  });
}

before(async () => {
  // 1. Initialize HEAD rules environment
  testEnvHead = await initializeTestEnvironment({
    projectId: PROJECT_ID_HEAD,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  await seedEnvironment(testEnvHead);

  // 2. Initialize Live rules (7e0ab46) environment
  testEnvLive = await initializeTestEnvironment({
    projectId: PROJECT_ID_LIVE,
    firestore: {
      rules: getLiveRules(),
    },
  });
  await seedEnvironment(testEnvLive);
});

after(async () => {
  if (testEnvHead) await testEnvHead.cleanup();
  if (testEnvLive) await testEnvLive.cleanup();
});

// Helper for running flows against a given environment
function registerReplaySuite(suiteTitle, getEnv, isLive) {
  describe(suiteTitle, () => {
    test('1. Patient cancel (cancelByPatient): payload replay on real baseline', async () => {
      const env = getEnv();
      await resetAppointmentDoc(env);

      const patientDb = env.authenticatedContext(PATIENT_UID).firestore();
      const ref = patientDb.collection('appointments').doc(APPT_ID);

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
        cancellationReason: 'Feeling better',
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

    test('2. Doctor cancel: payload replay on real baseline', async () => {
      const env = getEnv();
      await resetAppointmentDoc(env);

      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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

    test('3. Doctor reschedule: payload replay on real baseline', async () => {
      const env = getEnv();
      await resetAppointmentDoc(env);

      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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

    test('4. Doctor complete (saveConsultationOutcome): payload replay on real baseline', async () => {
      const env = getEnv();
      await resetAppointmentDoc(env);

      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
        doctorStatus: 'completed',
        diagnosis: 'Hypertension Stage 1',
        clinicalNotes: 'Follow low sodium diet',
        hasPrescription: true,
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

    test('4b. Patient direct reschedule (client write regression test)', async () => {
      const env = getEnv();
      await resetAppointmentDoc(env);

      const patientDb = env.authenticatedContext(PATIENT_UID).firestore();
      const ref = patientDb.collection('appointments').doc(APPT_ID);

      const payload = {
        appointmentId: APPT_ID,
        doctorId: DOCTOR_ID,
        doctorName: 'Dr. Doctor',
        specialization: 'Cardiology',
        patientId: PATIENT_ID,
        patientName: 'John Doe',
        patientAge: 30,
        patientGender: 'Male',
        dateTime: new Date('2026-10-18T05:30:00.000Z'),
        slotLabel: '11:00 AM',
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

      if (isLive) {
        // PASSES on Live rules (7e0ab46) via appointmentPatientUpdateKeys()
        await assertSucceeds(ref.set(payload, { merge: true }));
      } else {
        // FAILS on HEAD rules: appointmentPatientReschedule was removed in 401ac69 (callable-only)
        await assertFails(ref.set(payload, { merge: true }));
      }
    });

    test('5. Walk-in create (addWalkInAppointment): payload replay', async () => {
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const newId = `pa_walkin_${isLive ? 'live' : 'head'}`;

      const payload = {
        appointmentId: 'APT12345',
        doctorId: DOCTOR_ID,
        doctorName: 'Dr. Doctor',
        specialization: 'Cardiology',
        patientId: 'wi99999',
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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const ref = docDb.collection('prescriptions').doc(RX_ID + (isLive ? '_live' : '_head'));

      const payload = {
        prescriptionId: RX_ID + (isLive ? '_live' : '_head'),
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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const ref = docDb.collection('prescriptions').doc(RX_ID + (isLive ? '_live' : '_head'));

      const payload = {
        primaryDiagnosis: 'Essential Hypertension',
        updatedAt: new Date(),
      };

      await assertSucceeds(ref.set(payload, { merge: true }));
    });

    test('8. Pharmacy delivery create (doctor): payload replay', async () => {
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const ref = docDb.collection('pharmacy_deliveries').doc(DELIV_ID + (isLive ? '_live' : '_head'));

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
      const env = getEnv();
      const storeDb = env.authenticatedContext(STORE_UID).firestore();
      const ref = storeDb.collection('pharmacy_deliveries').doc(DELIV_ID + (isLive ? '_live' : '_head'));

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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const payload = {
        text: 'Acute Pharyngitis',
        textLower: 'acute pharyngitis',
        addedByDoctorId: DOCTOR_ID,
        addedAt: new Date(),
      };
      await assertSucceeds(docDb.collection('community_diagnoses').add(payload));
    });

    test('12. community_lab_tests catalog add: payload replay', async () => {
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
      const env = getEnv();
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const payload = {
        name: 'Right Knee Joint',
        nameLower: 'right knee joint',
        addedByDoctorId: DOCTOR_ID,
        addedAt: new Date(),
      };
      await assertSucceeds(docDb.collection('community_body_parts').add(payload));
    });

    test('15. ambulance updateAvailability: payload replay', async () => {
      const env = getEnv();
      const ambDb = env.authenticatedContext(AMB_UID).firestore();
      const ref = ambDb.collection('ambulances').doc(AMB_ID);

      const payload = {
        isAvailable: false,
      };

      await assertSucceeds(ref.set(payload, { merge: true }));
    });

    test('16. ambulance updateAmbulanceProfile: with PIN in diff fails on both live and HEAD', async () => {
      const env = getEnv();
      const ambDb = env.authenticatedContext(AMB_UID).firestore();
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
        pin: 'pbkdf2$sha256$120000$salt$hash', // protected key!
        totalRating: 5.0,
        ratingCount: 1,
        isAvailable: true,
        verified: false,
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

      // Denied on both HEAD (L1215) and Live (L1107) because pin is an affected key on the root doc
      await assertFails(ref.set(failingPayload, { merge: true }));
    });

    test('16b. ambulance updateAmbulanceProfile: clean profile without PIN passes on both', async () => {
      const env = getEnv();
      const ambDb = env.authenticatedContext(AMB_UID).firestore();
      const ref = ambDb.collection('ambulances').doc(AMB_ID);

      // Normal edit where pin is omitted (pin == '') and totalRating/verified are unchanged
      const cleanPayload = {
        serviceName: 'City Ambulance Updated Name',
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
        totalRating: 5.0,
        ratingCount: 1,
        isAvailable: true,
        verified: false,
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

      await assertSucceeds(ref.set(cleanPayload, { merge: true }));
    });

    test('17. ambulance registerAmbulance: payload replay', async () => {
      const env = getEnv();
      const newAmbUid = `amb_new_uid_${isLive ? 'live' : 'head'}`;
      const newAmbId = `amb_new_${isLive ? 'live' : 'head'}`;
      const ambDb = env.authenticatedContext(newAmbUid).firestore();
      const ref = ambDb.collection('ambulances').doc(newAmbId);

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

      const settingsPayload = {
        pin: '123456',
      };
      await assertSucceeds(ref.collection('private').doc('settings').set(settingsPayload, { merge: true }));
    });
  });
}

// 1. Run HEAD rules suite
registerReplaySuite('HEAD Rules Replay Suite (Real Baseline)', () => testEnvHead, false);

// 2. Run Live (7e0ab46) rules suite
registerReplaySuite('Live Rules (7e0ab46) Replay Suite (Real Baseline)', () => testEnvLive, true);

// 3. Run 741cb46 Client Payload Suite on Real Baseline
describe('741cb46 Client Payload Replay Suite on Real Baseline (HEAD vs Live)', () => {
  test('741cb46 patient cancel on existing doc ID passes on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      await resetAppointmentDoc(env);
      const patientDb = env.authenticatedContext(PATIENT_UID).firestore();
      const ref = patientDb.collection('appointments').doc(APPT_ID);

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
    }
  });

  test('741cb46 patient cancel on mismatching/new doc ID fails on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      const patientDb = env.authenticatedContext(PATIENT_UID).firestore();
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
    }
  });

  test('741cb46 doctor cancel succeeds on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      await resetAppointmentDoc(env);
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
    }
  });

  test('741cb46 doctor reschedule succeeds on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      await resetAppointmentDoc(env);
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
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
    }
  });

  test('741cb46 walk-in create succeeds on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const newId = `pa_walkin_741_${env.projectId}`;

      const payload = {
        appointmentId: 'APT741',
        doctorId: DOCTOR_ID,
        doctorName: 'Dr. Doctor',
        specialization: 'Cardiology',
        patientId: 'wi74100',
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
    }
  });

  test('741cb46 pharmacy delivery create (doctor) succeeds on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      const docDb = env.authenticatedContext(DOCTOR_UID).firestore();
      const ref = docDb.collection('pharmacy_deliveries').doc(`deliv_741_${env.projectId}`);

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
    }
  });

  test('741cb46 delivery update (store) succeeds on both HEAD and Live', async () => {
    for (const env of [testEnvHead, testEnvLive]) {
      const storeDb = env.authenticatedContext(STORE_UID).firestore();
      const ref = storeDb.collection('pharmacy_deliveries').doc(`deliv_741_${env.projectId}`);

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
    }
  });
});

// 4. Baseline Comparison: WITHOUT createdVia (6532271) vs WITH createdVia under HEAD rules
describe('Baseline Comparison: WITHOUT createdVia (6532271) vs WITH createdVia under HEAD rules', () => {
  async function seedDoc(withCreatedVia, overrides = {}) {
    await testEnvHead.withSecurityRulesDisabled(async (ctx) => {
      const doc = buildCallableBaselineAppointment(overrides);
      if (!withCreatedVia) {
        delete doc.createdVia;
      }
      await ctx.firestore().collection('appointments').doc(APPT_ID).set(doc);
    });
  }

  const patientCancelPayload = {
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
    cancellationReason: 'Feeling better',
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

  const doctorCancelPayload = {
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

  const doctorReschedulePayload = {
    appointmentId: APPT_ID,
    doctorId: DOCTOR_ID,
    doctorName: 'Dr. Doctor',
    specialization: 'Cardiology',
    patientId: PATIENT_ID,
    patientName: 'John Doe',
    patientAge: 30,
    patientGender: 'Male',
    dateTime: new Date('2026-10-16T04:30:00.000Z'),
    slotLabel: '11:00 AM',
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

  const doctorCompletePayload = {
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
    doctorStatus: 'completed',
    diagnosis: 'Mild hypertension',
    clinicalNotes: 'Take meds regularly',
    hasPrescription: true,
    hasReport: false,
    hasReview: false,
    labReports: [],
    chiefComplaints: [],
    symptoms: [],
    observations: [],
    wasRescheduled: false,
    updatedAt: new Date(),
  };

  // Group A: Baseline WITHOUT createdVia (live 6532271 key set)
  test('A1. baseline WITHOUT createdVia: patient cancel succeeds under HEAD rules', async () => {
    await seedDoc(false);
    const db = testEnvHead.authenticatedContext(PATIENT_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(patientCancelPayload, { merge: true }));
  });

  test('A2. baseline WITHOUT createdVia: doctor cancel succeeds under HEAD rules', async () => {
    await seedDoc(false);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorCancelPayload, { merge: true }));
  });

  test('A3. baseline WITHOUT createdVia: doctor reschedule succeeds under HEAD rules', async () => {
    await seedDoc(false);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorReschedulePayload, { merge: true }));
  });

  test('A4. baseline WITHOUT createdVia: doctor complete succeeds under HEAD rules', async () => {
    await seedDoc(false);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorCompletePayload, { merge: true }));
  });

  // Group B: Baseline WITH createdVia (HEAD callable key set)
  test('B1. baseline WITH createdVia: patient cancel succeeds under HEAD rules', async () => {
    await seedDoc(true);
    const db = testEnvHead.authenticatedContext(PATIENT_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(patientCancelPayload, { merge: true }));
  });

  test('B2. baseline WITH createdVia: doctor cancel succeeds under HEAD rules', async () => {
    await seedDoc(true);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorCancelPayload, { merge: true }));
  });

  test('B3. baseline WITH createdVia: doctor reschedule succeeds under HEAD rules', async () => {
    await seedDoc(true);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorReschedulePayload, { merge: true }));
  });

  test('B4. baseline WITH createdVia: doctor complete succeeds under HEAD rules', async () => {
    await seedDoc(true);
    const db = testEnvHead.authenticatedContext(DOCTOR_UID).firestore();
    await assertSucceeds(db.collection('appointments').doc(APPT_ID).set(doctorCompletePayload, { merge: true }));
  });
});
