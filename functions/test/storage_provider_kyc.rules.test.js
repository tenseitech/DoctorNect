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
const OWNER_UID = 'owner-provider-uid';
const OTHER_UID = 'other-user-uid';
const ADMIN_UID = 'admin-user-uid';
const ADMIN_EMAIL = 'admin@doctornect.com';
const PDF_BYTES = new Uint8Array([0x25, 0x50, 0x44, 0x46]);

const PROVIDER_CASES = [
  {
    label: 'pharmacy',
    kycPath: 'pharmacies/store-kyc-1/licenses/drug.pdf',
    firestoreCollection: 'medical_stores',
    profileId: 'store-kyc-1',
    ownerField: 'ownerUid',
    ownerValue: OWNER_UID,
  },
  {
    label: 'lab',
    kycPath: 'labs/lab-kyc-1/certificates/nabl.pdf',
    firestoreCollection: 'labs',
    profileId: 'lab-kyc-1',
    ownerField: 'ownerUid',
    ownerValue: OWNER_UID,
  },
  {
    label: 'ambulance',
    kycPath: 'ambulances/amb-kyc-1/permits/rc.pdf',
    firestoreCollection: 'ambulances',
    profileId: 'amb-kyc-1',
    ownerField: 'authUid',
    ownerValue: OWNER_UID,
  },
];

let testEnv;

if (!process.env.FIREBASE_STORAGE_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
  test('storage provider kyc rules tests (skipped: emulator not running; run npm run test:storage-rules)', { skip: 'Storage/Firestore emulator not running' }, () => {});
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
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seedOwner(caseConfig) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection(caseConfig.firestoreCollection).doc(caseConfig.profileId).set({
      [caseConfig.ownerField]: caseConfig.ownerValue,
      verified: false,
    });
  });
}

async function seedExistingKyc(kycPath) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.storage().ref(kycPath).put(PDF_BYTES, {
      contentType: 'application/pdf',
    });
  });
}

for (const caseConfig of PROVIDER_CASES) {
  test(`super admin can read ${caseConfig.label} KYC documents`, async () => {
    await seedOwner(caseConfig);
    await seedExistingKyc(caseConfig.kycPath);

    const adminCtx = testEnv.authenticatedContext(ADMIN_UID, { email: ADMIN_EMAIL });
    await assertSucceeds(adminCtx.storage().ref(caseConfig.kycPath).getMetadata());
  });

  test(`${caseConfig.label} owner can upload KYC but cannot read it back`, async () => {
    await seedOwner(caseConfig);

    const ownerCtx = testEnv.authenticatedContext(OWNER_UID, { email: 'owner@provider.com' });
    await assertSucceeds(
      ownerCtx.storage().ref(caseConfig.kycPath).put(PDF_BYTES, { contentType: 'application/pdf' }),
    );
    await assertFails(ownerCtx.storage().ref(caseConfig.kycPath).getMetadata());
  });

  test(`unrelated signed-in user cannot read or write ${caseConfig.label} KYC`, async () => {
    await seedOwner(caseConfig);
    await seedExistingKyc(caseConfig.kycPath);

    const otherCtx = testEnv.authenticatedContext(OTHER_UID, { email: 'other@example.com' });
    await assertFails(otherCtx.storage().ref(caseConfig.kycPath).getMetadata());
    await assertFails(
      otherCtx.storage().ref(caseConfig.kycPath).put(PDF_BYTES, { contentType: 'application/pdf' }),
    );
  });
}
