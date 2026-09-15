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
const DOCTOR_ID = 'doc-kyc-1';
const OWNER_UID = 'owner-doctor-uid';
const OTHER_UID = 'other-user-uid';
const ADMIN_UID = 'admin-user-uid';
const ADMIN_EMAIL = 'admin@doctornect.com';
const KYC_PATH = `doctors/${DOCTOR_ID}/certificates/reg.pdf`;
const PDF_BYTES = new Uint8Array([0x25, 0x50, 0x44, 0x46]);

let testEnv;

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
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seedDoctorOwner() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('doctors').doc(DOCTOR_ID).set({
      ownerUid: OWNER_UID,
      doctorId: DOCTOR_ID,
      verified: false,
    });
  });
}

async function seedExistingKyc() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.storage().ref(KYC_PATH).put(PDF_BYTES, {
      contentType: 'application/pdf',
    });
  });
}

test('super admin can read doctor KYC documents', async () => {
  await seedDoctorOwner();
  await seedExistingKyc();

  const adminCtx = testEnv.authenticatedContext(ADMIN_UID, { email: ADMIN_EMAIL });
  await assertSucceeds(adminCtx.storage().ref(KYC_PATH).getMetadata());
});

test('owner doctor can upload KYC but cannot read it back', async () => {
  await seedDoctorOwner();

  const ownerCtx = testEnv.authenticatedContext(OWNER_UID, { email: 'owner@doctor.com' });
  await assertSucceeds(
    ownerCtx.storage().ref(KYC_PATH).put(PDF_BYTES, { contentType: 'application/pdf' }),
  );
  await assertFails(ownerCtx.storage().ref(KYC_PATH).getMetadata());
});

test('unrelated signed-in user cannot read or write doctor KYC', async () => {
  await seedDoctorOwner();
  await seedExistingKyc();

  const otherCtx = testEnv.authenticatedContext(OTHER_UID, { email: 'other@example.com' });
  await assertFails(otherCtx.storage().ref(KYC_PATH).getMetadata());
  await assertFails(
    otherCtx.storage().ref(KYC_PATH).put(PDF_BYTES, { contentType: 'application/pdf' }),
  );
});
