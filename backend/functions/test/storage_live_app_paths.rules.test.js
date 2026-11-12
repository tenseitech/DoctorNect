'use strict';

const fs = require('fs');
const path = require('path');
const { before, after, test } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-doctornect-kyc';
const PATIENT_UID = 'patient-user-1';
const PATIENT_PROFILE_ID = 'patient-prof-1';
const DOCTOR_UID = 'doctor-user-1';
const DOCTOR_PROFILE_ID = 'doc-prof-1';
const LAB_UID = 'lab-user-1';
const LAB_PROFILE_ID = 'lab-prof-1';
const OTHER_UID = 'unrelated-user-1';

const JPEG_BYTES = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
const PDF_BYTES = new Uint8Array([0x25, 0x50, 0x44, 0x46]);

let testEnv;

if (!process.env.FIREBASE_STORAGE_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
  test('storage live app paths rules tests (skipped: emulator not running)', { skip: 'Storage/Firestore emulator not running' }, () => {});
  return;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
    storage: {
      rules: fs.readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8'),
    },
  });

  // Seed user mappings in Firestore
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('users').doc(PATIENT_UID).set({
      role: 'patient',
      profileId: PATIENT_PROFILE_ID,
    });
    await db.collection('users').doc(DOCTOR_UID).set({
      role: 'doctor',
      profileId: DOCTOR_PROFILE_ID,
    });
    await db.collection('users').doc(LAB_UID).set({
      role: 'lab',
      profileId: LAB_PROFILE_ID,
    });
    await db.collection('users').doc(OTHER_UID).set({
      role: 'patient',
      profileId: 'other-prof-99',
    });

    // Seed doctor profile
    await db.collection('doctors').doc(DOCTOR_PROFILE_ID).set({
      ownerUid: DOCTOR_UID,
      verified: true,
    });

    // Seed lab booking for lab report test
    await db.collection('lab_bookings').doc('booking-123').set({
      patientId: PATIENT_PROFILE_ID,
      labId: LAB_PROFILE_ID,
      status: 'confirmed',
    });
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

// 1. Patient Profile Photos
test('patient owner can upload profile photo and any signed-in user can read it', async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_UID);
  const photoPath = `patients/${PATIENT_PROFILE_ID}/profile_photo.jpg`;

  await assertSucceeds(
    patientCtx.storage().ref(photoPath).put(JPEG_BYTES, { contentType: 'image/jpeg' }),
  );
  await assertSucceeds(otherCtx.storage().ref(photoPath).getMetadata());

  // Other patient cannot overwrite someone else's profile photo
  await assertFails(
    otherCtx.storage().ref(photoPath).put(JPEG_BYTES, { contentType: 'image/jpeg' }),
  );
});

// 2. Doctor Profile Photos
test('doctor owner can upload profile photo and any signed-in user can read it', async () => {
  const docCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_UID);
  const docPhotoPath = `doctor_profiles/${DOCTOR_PROFILE_ID}/profile.jpg`;

  await assertSucceeds(
    docCtx.storage().ref(docPhotoPath).put(JPEG_BYTES, { contentType: 'image/jpeg' }),
  );
  await assertSucceeds(otherCtx.storage().ref(docPhotoPath).getMetadata());

  // Other user cannot overwrite doctor's profile photo
  await assertFails(
    otherCtx.storage().ref(docPhotoPath).put(JPEG_BYTES, { contentType: 'image/jpeg' }),
  );
});

// 3. Health Records
test('patient owner can upload and read health records; unrelated user cannot', async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_UID);
  const recordPath = `health_records/${PATIENT_PROFILE_ID}/rec-001/prescription.pdf`;

  await assertSucceeds(
    patientCtx.storage().ref(recordPath).put(PDF_BYTES, { contentType: 'application/pdf' }),
  );
  await assertSucceeds(patientCtx.storage().ref(recordPath).getMetadata());

  // Unrelated user cannot read or write patient health records
  await assertFails(otherCtx.storage().ref(recordPath).getMetadata());
  await assertFails(
    otherCtx.storage().ref(recordPath).put(PDF_BYTES, { contentType: 'application/pdf' }),
  );
});

// 4. Lab Reports
test('assigned lab can upload lab report and patient owner can read it', async () => {
  const labCtx = testEnv.authenticatedContext(LAB_UID);
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_UID);
  const reportPath = `lab_reports/${PATIENT_PROFILE_ID}/booking-123/blood_test.pdf`;

  await assertSucceeds(
    labCtx.storage().ref(reportPath).put(PDF_BYTES, { contentType: 'application/pdf' }),
  );
  await assertSucceeds(patientCtx.storage().ref(reportPath).getMetadata());

  // Unrelated user cannot read or write the report
  await assertFails(otherCtx.storage().ref(reportPath).getMetadata());
});

// 5. Promoted Ad Banners
test('provider can upload banner image and any signed-in user can read it', async () => {
  const docCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_UID);
  const bannerPath = `promoted_ads/${DOCTOR_UID}/banner_summer.png`;

  await assertSucceeds(
    docCtx.storage().ref(bannerPath).put(JPEG_BYTES, { contentType: 'image/png' }),
  );
  await assertSucceeds(otherCtx.storage().ref(bannerPath).getMetadata());

  // Another user cannot overwrite provider's ad image
  await assertFails(
    otherCtx.storage().ref(bannerPath).put(JPEG_BYTES, { contentType: 'image/png' }),
  );
});
