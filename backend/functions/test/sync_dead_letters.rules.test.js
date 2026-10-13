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

const PROJECT_ID = 'demo-doctornect-deadletters-rules';

let testEnv;

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('syncDeadLetters rules tests (skipped: FIRESTORE_EMULATOR_HOST not set)', { skip: 'FIRESTORE_EMULATOR_HOST not set' }, () => {});
  return;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });

  // Seed fixture data with rules disabled
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // 1. Existing dead letter document
    await db.collection('syncDeadLetters').doc('dl-test-1').set({
      direction: 'supabase_to_firestore',
      entityType: 'appointments',
      entityId: 'apt-seed-1',
      reason: 'firestore_doc_missing',
      changedFields: ['doctorStatus'],
      attempts: 1,
      createdAt: new Date(),
    });

    // 2. User docs
    await db.collection('users').doc('uid-patient').set({
      uid: 'uid-patient',
      role: 'patient',
      profileId: 'pat-1',
    });

    await db.collection('users').doc('uid-doctor').set({
      uid: 'uid-doctor',
      role: 'doctor',
      profileId: 'doc-1',
    });

    await db.collection('users').doc('uid-pharmacy').set({
      uid: 'uid-pharmacy',
      role: 'pharmacy',
      profileId: 'pharm-1',
    });

    await db.collection('users').doc('uid-admin').set({
      uid: 'uid-admin',
      role: 'superAdmin',
    });
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test('syncDeadLetters Rules: Anonymous user denied read', async () => {
  const anonDb = testEnv.unauthenticatedContext().firestore();
  await assertFails(anonDb.collection('syncDeadLetters').doc('dl-test-1').get());
  await assertFails(anonDb.collection('syncDeadLetters').get());
});

test('syncDeadLetters Rules: Patient denied read', async () => {
  const patientDb = testEnv.authenticatedContext('uid-patient').firestore();
  await assertFails(patientDb.collection('syncDeadLetters').doc('dl-test-1').get());
  await assertFails(patientDb.collection('syncDeadLetters').get());
});

test('syncDeadLetters Rules: Doctor denied read', async () => {
  const doctorDb = testEnv.authenticatedContext('uid-doctor').firestore();
  await assertFails(doctorDb.collection('syncDeadLetters').doc('dl-test-1').get());
  await assertFails(doctorDb.collection('syncDeadLetters').get());
});

test('syncDeadLetters Rules: Provider (Pharmacy/Lab/Ambulance) denied read', async () => {
  const providerDb = testEnv.authenticatedContext('uid-pharmacy').firestore();
  await assertFails(providerDb.collection('syncDeadLetters').doc('dl-test-1').get());
  await assertFails(providerDb.collection('syncDeadLetters').get());
});

test('syncDeadLetters Rules: Super Admin read allowed', async () => {
  const adminDb = testEnv.authenticatedContext('uid-admin').firestore();
  await assertSucceeds(adminDb.collection('syncDeadLetters').doc('dl-test-1').get());
  await assertSucceeds(adminDb.collection('syncDeadLetters').get());
});

test('syncDeadLetters Rules: All writes denied for all clients including Super Admin', async () => {
  const anonDb = testEnv.unauthenticatedContext().firestore();
  const patientDb = testEnv.authenticatedContext('uid-patient').firestore();
  const doctorDb = testEnv.authenticatedContext('uid-doctor').firestore();
  const providerDb = testEnv.authenticatedContext('uid-pharmacy').firestore();
  const adminDb = testEnv.authenticatedContext('uid-admin').firestore();

  const newDoc = {
    direction: 'supabase_to_firestore',
    entityType: 'appointments',
    entityId: 'apt-client-write',
    reason: 'terminal_state',
    attempts: 1,
  };

  // Create denied
  await assertFails(anonDb.collection('syncDeadLetters').doc('dl-new-anon').set(newDoc));
  await assertFails(patientDb.collection('syncDeadLetters').doc('dl-new-pat').set(newDoc));
  await assertFails(doctorDb.collection('syncDeadLetters').doc('dl-new-doc').set(newDoc));
  await assertFails(providerDb.collection('syncDeadLetters').doc('dl-new-prov').set(newDoc));
  await assertFails(adminDb.collection('syncDeadLetters').doc('dl-new-admin').set(newDoc));

  // Update denied
  await assertFails(anonDb.collection('syncDeadLetters').doc('dl-test-1').update({ attempts: 2 }));
  await assertFails(patientDb.collection('syncDeadLetters').doc('dl-test-1').update({ attempts: 2 }));
  await assertFails(doctorDb.collection('syncDeadLetters').doc('dl-test-1').update({ attempts: 2 }));
  await assertFails(providerDb.collection('syncDeadLetters').doc('dl-test-1').update({ attempts: 2 }));
  await assertFails(adminDb.collection('syncDeadLetters').doc('dl-test-1').update({ attempts: 2 }));

  // Delete denied
  await assertFails(anonDb.collection('syncDeadLetters').doc('dl-test-1').delete());
  await assertFails(patientDb.collection('syncDeadLetters').doc('dl-test-1').delete());
  await assertFails(doctorDb.collection('syncDeadLetters').doc('dl-test-1').delete());
  await assertFails(providerDb.collection('syncDeadLetters').doc('dl-test-1').delete());
  await assertFails(adminDb.collection('syncDeadLetters').doc('dl-test-1').delete());
});
