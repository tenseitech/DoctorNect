'use strict';

const fs = require('fs');
const path = require('path');
const { before, after, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-doctornect-s3-rules';
const PATIENT_UID = 'patient_auth_uid_1';
const PATIENT_ID = 'p1234567890';
const OTHER_PATIENT_UID = 'patient_auth_uid_2';
const OTHER_PATIENT_ID = 'p9876543210';

const LAB_UID = 'lab_auth_uid_1';
const LAB_ID = 'lab123456';
const OTHER_LAB_UID = 'lab_auth_uid_2';
const OTHER_LAB_ID = 'lab654321';

const DOCTOR_UID = 'doctor_auth_uid_1';
const DOCTOR_ID = 'doc123456';

let testEnv;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('firestore rules s3 storage tests (skipped: FIRESTORE_EMULATOR_HOST not set; run npm run test:firestore-s3-rules)', { skip: 'FIRESTORE_EMULATOR_HOST not set' }, () => {});
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

async function seedUsers() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    // Patient 1
    await db.collection('users').doc(PATIENT_UID).set({
      role: 'patient',
      profileId: PATIENT_ID,
    });
    await db.collection('patients').doc(PATIENT_ID).set({
      patientId: PATIENT_ID,
      name: 'John Doe',
    });

    // Patient 2
    await db.collection('users').doc(OTHER_PATIENT_UID).set({
      role: 'patient',
      profileId: OTHER_PATIENT_ID,
    });
    await db.collection('patients').doc(OTHER_PATIENT_ID).set({
      patientId: OTHER_PATIENT_ID,
      name: 'Jane Other',
    });

    // Lab 1
    await db.collection('users').doc(LAB_UID).set({
      role: 'lab',
      profileId: LAB_ID,
    });
    await db.collection('labs').doc(LAB_ID).set({
      labId: LAB_ID,
      name: 'Alpha Labs',
    });

    // Lab 2
    await db.collection('users').doc(OTHER_LAB_UID).set({
      role: 'lab',
      profileId: OTHER_LAB_ID,
    });
    await db.collection('labs').doc(OTHER_LAB_ID).set({
      labId: OTHER_LAB_ID,
      name: 'Beta Labs',
    });

    // Doctor
    await db.collection('users').doc(DOCTOR_UID).set({
      role: 'doctor',
      profileId: DOCTOR_ID,
    });
    await db.collection('doctors').doc(DOCTOR_ID).set({
      doctorId: DOCTOR_ID,
      verified: true,
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// health_records rules tests
// ─────────────────────────────────────────────────────────────────────────────

test('health_records: legacy record without storageProvider is accepted', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const db = patientCtx.firestore();

  await assertSucceeds(
    db.collection('health_records').doc('rec_legacy_1').set({
      patientId: PATIENT_ID,
      title: 'Blood Test',
      storageUrl: 'https://firebasestorage.googleapis.com/...',
      fileName: 'report.pdf',
    }),
  );
});

test('health_records: S3 provider with correct prefix is accepted', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const db = patientCtx.firestore();

  await assertSucceeds(
    db.collection('health_records').doc('rec_s3_valid').set({
      patientId: PATIENT_ID,
      title: 'Blood Test',
      storageProvider: 's3',
      storageKey: `health_records/${PATIENT_ID}/uuid123.pdf`,
      fileName: 'report.pdf',
    }),
  );
});

test('health_records: S3 provider with wrong patientId prefix is rejected', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const db = patientCtx.firestore();

  await assertFails(
    db.collection('health_records').doc('rec_s3_wrong_patient').set({
      patientId: PATIENT_ID,
      title: 'Blood Test',
      storageProvider: 's3',
      storageKey: `health_records/${OTHER_PATIENT_ID}/uuid123.pdf`,
      fileName: 'report.pdf',
    }),
  );
});

test('health_records: S3 provider with wrong folder prefix is rejected', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  const db = patientCtx.firestore();

  await assertFails(
    db.collection('health_records').doc('rec_s3_wrong_folder').set({
      patientId: PATIENT_ID,
      title: 'Blood Test',
      storageProvider: 's3',
      storageKey: `lab_reports/${PATIENT_ID}/uuid123.pdf`,
      fileName: 'report.pdf',
    }),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// lab_bookings rules tests
// ─────────────────────────────────────────────────────────────────────────────

test('lab_bookings: assigned lab can submit report with S3 provider and correct prefix', async () => {
  await seedUsers();
  const bookingId = 'booking_s3_valid_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertSucceeds(
    labCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      status: 'completed',
      reportFileName: 'report.pdf',
      reportStorageKey: `lab_reports/${PATIENT_ID}/${bookingId}/uuid-456.pdf`,
      reportStorageProvider: 's3',
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_bookings: assigned lab cannot submit report with S3 provider and mismatched patientId', async () => {
  await seedUsers();
  const bookingId = 'booking_s3_mismatch_patient';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertFails(
    labCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      status: 'completed',
      reportFileName: 'report.pdf',
      reportStorageKey: `lab_reports/${OTHER_PATIENT_ID}/${bookingId}/uuid-456.pdf`,
      reportStorageProvider: 's3',
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_bookings: assigned lab cannot submit report with S3 provider and mismatched bookingId', async () => {
  await seedUsers();
  const bookingId = 'booking_s3_mismatch_booking';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertFails(
    labCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      status: 'completed',
      reportFileName: 'report.pdf',
      reportStorageKey: `lab_reports/${PATIENT_ID}/other_booking_id/uuid-456.pdf`,
      reportStorageProvider: 's3',
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_bookings: assigned lab can submit legacy report without reportStorageProvider', async () => {
  await seedUsers();
  const bookingId = 'booking_legacy_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertSucceeds(
    labCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      status: 'completed',
      reportFileName: 'report.pdf',
      reportStorageUrl: 'https://firebasestorage.googleapis.com/...',
      reportBookingId: bookingId,
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_bookings: patient cannot set report fields', async () => {
  await seedUsers();
  const bookingId = 'booking_tamper_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertFails(
    patientCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      reportStorageKey: `lab_reports/${PATIENT_ID}/${bookingId}/tampered.pdf`,
      reportStorageProvider: 's3',
    }),
  );
});

test('lab_bookings: unassigned lab cannot submit report', async () => {
  await seedUsers();
  const bookingId = 'booking_unassigned_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_bookings').doc(bookingId).set({
      bookingId: bookingId,
      patientId: PATIENT_ID,
      labId: LAB_ID,
      status: 'confirmed',
      dateTime: new Date(),
    });
  });

  const otherLabCtx = testEnv.authenticatedContext(OTHER_LAB_UID);
  await assertFails(
    otherLabCtx.firestore().collection('lab_bookings').doc(bookingId).update({
      status: 'completed',
      reportFileName: 'report.pdf',
      reportStorageKey: `lab_reports/${PATIENT_ID}/${bookingId}/uuid-456.pdf`,
      reportStorageProvider: 's3',
    }),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// lab_orders rules tests
// ─────────────────────────────────────────────────────────────────────────────

test('lab_orders: assigned lab can submit report with S3 provider and correct prefix', async () => {
  await seedUsers();
  const orderId = 'order_s3_valid_1';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_orders').doc(orderId).set({
      orderId: orderId,
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
      labId: LAB_ID,
      status: 'ordered',
      createdAt: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertSucceeds(
    labCtx.firestore().collection('lab_orders').doc(orderId).update({
      status: 'completed',
      reportFileName: 'order_report.pdf',
      reportStorageKey: `lab_reports/${PATIENT_ID}/${orderId}/uuid-789.pdf`,
      reportStorageProvider: 's3',
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_orders: assigned lab cannot submit report with S3 provider and wrong prefix', async () => {
  await seedUsers();
  const orderId = 'order_s3_invalid_prefix';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_orders').doc(orderId).set({
      orderId: orderId,
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
      labId: LAB_ID,
      status: 'ordered',
      createdAt: new Date(),
    });
  });

  const labCtx = testEnv.authenticatedContext(LAB_UID);
  await assertFails(
    labCtx.firestore().collection('lab_orders').doc(orderId).update({
      status: 'completed',
      reportFileName: 'order_report.pdf',
      reportStorageKey: `health_records/${PATIENT_ID}/uuid-789.pdf`,
      reportStorageProvider: 's3',
      reportSubmittedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

test('lab_orders: doctor cannot set report fields', async () => {
  await seedUsers();
  const orderId = 'order_doctor_tamper';

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('lab_orders').doc(orderId).set({
      orderId: orderId,
      patientId: PATIENT_ID,
      doctorId: DOCTOR_ID,
      labId: LAB_ID,
      status: 'ordered',
      createdAt: new Date(),
    });
  });

  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  await assertFails(
    doctorCtx.firestore().collection('lab_orders').doc(orderId).update({
      reportStorageKey: `lab_reports/${PATIENT_ID}/${orderId}/fake.pdf`,
      reportStorageProvider: 's3',
    }),
  );
});

test('patients: owner can set valid S3 profile photo fields', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      photoKey: `patients/${PATIENT_ID}/profile/avatar123.jpg`,
      photoStorage: 's3',
      hasLocalPhoto: true,
      updatedAt: new Date(),
    }),
  );
});

test('patients: owner cannot set S3 profile photo with non-profile or wrong patient prefix', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  // Traversal / wrong purpose
  await assertFails(
    patientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      photoKey: `health_records/${PATIENT_ID}/record.pdf`,
      photoStorage: 's3',
    }),
  );
  // Other patient's id
  await assertFails(
    patientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      photoKey: `patients/${OTHER_PATIENT_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
    }),
  );
});

test('patients: non-owner cannot update patient photo fields', async () => {
  await seedUsers();
  const otherPatientCtx = testEnv.authenticatedContext(OTHER_PATIENT_UID);
  await assertFails(
    otherPatientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      photoKey: `patients/${PATIENT_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
    }),
  );
});

test('doctors: doctor can update own profile photo with valid prefix', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  await assertSucceeds(
    doctorCtx.firestore().collection('doctors').doc(DOCTOR_ID).update({
      photoKey: `doctor_profiles/${DOCTOR_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
      updatedAt: new Date(),
    }),
  );
});

test('doctors: doctor cannot update profile photo with clinical or mismatched prefix', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  await assertFails(
    doctorCtx.firestore().collection('doctors').doc(DOCTOR_ID).update({
      photoKey: `patients/${PATIENT_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
    }),
  );
  await assertFails(
    doctorCtx.firestore().collection('doctors').doc(DOCTOR_ID).update({
      photoKey: `doctor_profiles/other_doctor/profile/avatar.jpg`,
      photoStorage: 's3',
    }),
  );
});

test('users: user can update own photo fields with matching prefix but not arbitrary prefix', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('users').doc(PATIENT_UID).update({
      photoKey: `patients/${PATIENT_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
      updatedAt: new Date(),
    }),
  );

  await assertFails(
    patientCtx.firestore().collection('users').doc(PATIENT_UID).update({
      photoKey: `health_records/${PATIENT_ID}/avatar.jpg`,
      photoStorage: 's3',
    }),
  );

  // Cross-user prefix rejected
  await assertFails(
    patientCtx.firestore().collection('users').doc(PATIENT_UID).update({
      photoKey: `patients/${OTHER_PATIENT_ID}/profile/avatar.jpg`,
      photoStorage: 's3',
    }),
  );
});

test('patients: legacy update accepted without photoKey/photoStorage (e.g. only name changed)', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      name: 'John Updated Doe',
      updatedAt: new Date(),
    }),
  );
});

test('patients: legacy update accepted with photoStorage "firebase" and only photoUrl', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('patients').doc(PATIENT_ID).update({
      photoStorage: 'firebase',
      photoUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/profile.jpg?alt=media',
      photoURL: 'https://firebasestorage.googleapis.com/v0/b/app/o/profile.jpg?alt=media',
      hasLocalPhoto: true,
      updatedAt: new Date(),
    }),
  );
});

test('doctors: legacy update accepted without photoKey/photoStorage (e.g. only name/address changed)', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  await assertSucceeds(
    doctorCtx.firestore().collection('doctors').doc(DOCTOR_ID).update({
      name: 'Dr. Jane Updated',
      address: '456 Medical Lane',
      updatedAt: new Date(),
    }),
  );
});

test('doctors: legacy update accepted with photoStorage "firebase" and only photoUrl', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  await assertSucceeds(
    doctorCtx.firestore().collection('doctors').doc(DOCTOR_ID).update({
      photoStorage: 'firebase',
      photoUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/doc.jpg?alt=media',
      photoURL: 'https://firebasestorage.googleapis.com/v0/b/app/o/doc.jpg?alt=media',
      updatedAt: new Date(),
    }),
  );
});

test('users: legacy update accepted without photoKey/photoStorage', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('users').doc(PATIENT_UID).update({
      displayName: 'Patient Jane',
      updatedAt: new Date(),
    }),
  );
});

test('users: legacy update accepted with photoStorage "firebase" and only photoUrl', async () => {
  await seedUsers();
  const patientCtx = testEnv.authenticatedContext(PATIENT_UID);
  await assertSucceeds(
    patientCtx.firestore().collection('users').doc(PATIENT_UID).update({
      photoStorage: 'firebase',
      photoUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/user.jpg?alt=media',
      photoURL: 'https://firebasestorage.googleapis.com/v0/b/app/o/user.jpg?alt=media',
      updatedAt: new Date(),
    }),
  );
});

test('promotedAds: owning provider can create and update ad with valid S3 banner key', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const adId = 'ad_test_101';

  // 1. Create with S3 banner
  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).set({
      providerId: DOCTOR_UID,
      providerType: 'doctor',
      title: 'Doctor Clinic Promotion',
      description: 'Visit our expert clinic',
      imageUrl: 'https://s3.example.com/banner.jpg',
      imageKey: `promoted_ads/${DOCTOR_UID}/${adId}/banner_01.jpg`,
      imageStorage: 's3',
      status: 'draft',
      paymentStatus: 'pending',
      amountPaid: 300,
      durationHours: 24,
      createdAt: new Date(),
    }),
  );

  // 2. Update with new S3 banner
  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).update({
      imageUrl: 'https://s3.example.com/banner_new.jpg',
      imageKey: `promoted_ads/${DOCTOR_UID}/${adId}/banner_02.jpg`,
      imageStorage: 's3',
      title: 'Doctor Clinic Promotion Updated',
    }),
  );
});

test('promotedAds: provider cannot use wrong prefix or traversal in imageKey', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const adId = 'ad_test_traversal';

  // Wrong provider prefix
  await assertFails(
    doctorCtx.firestore().collection('promotedAds').doc(adId).set({
      providerId: DOCTOR_UID,
      providerType: 'doctor',
      title: 'Wrong Prefix Ad',
      description: 'Should fail',
      imageUrl: 'https://example.com/img.jpg',
      imageKey: `promoted_ads/${OTHER_PATIENT_UID}/${adId}/banner.jpg`,
      imageStorage: 's3',
      status: 'draft',
      paymentStatus: 'pending',
    }),
  );

  // Traversal
  await assertFails(
    doctorCtx.firestore().collection('promotedAds').doc(adId).set({
      providerId: DOCTOR_UID,
      providerType: 'doctor',
      title: 'Traversal Ad',
      description: 'Should fail',
      imageUrl: 'https://example.com/img.jpg',
      imageKey: `promoted_ads/${DOCTOR_UID}/${adId}/../../secrets.txt`,
      imageStorage: 's3',
      status: 'draft',
      paymentStatus: 'pending',
    }),
  );
});

test('promotedAds: non-owner provider cannot update another provider ad', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const otherCtx = testEnv.authenticatedContext(OTHER_PATIENT_UID);
  const adId = 'ad_test_ownership';

  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).set({
      providerId: DOCTOR_UID,
      providerType: 'doctor',
      title: 'Owner Ad',
      description: 'Description',
      imageUrl: 'https://s3.example.com/banner.jpg',
      imageKey: `promoted_ads/${DOCTOR_UID}/${adId}/banner.jpg`,
      imageStorage: 's3',
      status: 'draft',
      paymentStatus: 'pending',
    }),
  );

  await assertFails(
    otherCtx.firestore().collection('promotedAds').doc(adId).update({
      title: 'Hacked title',
    }),
  );
});

test('promotedAds: legacy update accepted without imageKey/imageStorage or with imageStorage "firebase"', async () => {
  await seedUsers();
  const doctorCtx = testEnv.authenticatedContext(DOCTOR_UID);
  const adId = 'ad_test_legacy';

  // Legacy create
  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).set({
      providerId: DOCTOR_UID,
      providerType: 'doctor',
      title: 'Legacy Promo',
      description: 'Legacy ad description',
      imageUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/ad.jpg?alt=media',
      status: 'draft',
      paymentStatus: 'pending',
    }),
  );

  // Legacy update without imageKey/imageStorage
  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).update({
      title: 'Legacy Promo Updated',
    }),
  );

  // Legacy update with imageStorage 'firebase' and only imageUrl
  await assertSucceeds(
    doctorCtx.firestore().collection('promotedAds').doc(adId).update({
      imageStorage: 'firebase',
      imageUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/ad2.jpg?alt=media',
    }),
  );
});

// ----------------------------------------------------------------------------
// ADMIN PERMISSION TESTS (isAccountAdmin email_verified gate)
// ----------------------------------------------------------------------------
test('admin: allowlisted admin email with email_verified: true can list users', async () => {
  await seedUsers();
  const adminCtx = testEnv.authenticatedContext('admin_uid_verified', {
    email: 'admin@doctornect.com',
    email_verified: true,
  });
  await assertSucceeds(adminCtx.firestore().collection('users').get());
});

test('admin: allowlisted admin email with email_verified: false CANNOT list users', async () => {
  await seedUsers();
  const spoofedCtx = testEnv.authenticatedContext('admin_uid_unverified', {
    email: 'admin@doctornect.com',
    email_verified: false,
  });
  await assertFails(spoofedCtx.firestore().collection('users').get());
});

test('admin: allowlisted admin email with email_verified: false CANNOT read arbitrary user doc', async () => {
  await seedUsers();
  const spoofedCtx = testEnv.authenticatedContext('admin_uid_unverified', {
    email: 'admin@doctornect.com',
    email_verified: false,
  });
  await assertFails(spoofedCtx.firestore().collection('users').doc(PATIENT_UID).get());
});

