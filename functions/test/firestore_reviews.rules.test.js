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

const PROJECT_ID = 'demo-doctornect-reviews';
const REVIEW_ID = 'p1234567890_d9876543210';
const DOCTOR_ID = 'd9876543210';

let testEnv;

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

async function seedReviewDocs() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('reviews').doc(REVIEW_ID).set({
      patientId: 'p1234567890',
      doctorId: DOCTOR_ID,
      rating: 5,
      comment: 'Great doctor',
      patientName: 'Jane Doe',
      appointmentId: 'appt-1',
    });
    await context.firestore().collection('review_public').doc(REVIEW_ID).set({
      doctorId: DOCTOR_ID,
      rating: 5,
      comment: 'Great doctor',
      maskedName: 'J. D.',
      helpfulCount: 0,
    });
  });
}

test('anonymous reader can read public review projection without patientId', async () => {
  await seedReviewDocs();

  const anonCtx = testEnv.unauthenticatedContext();
  const snap = await assertSucceeds(
    anonCtx.firestore().collection('review_public').doc(REVIEW_ID).get(),
  );

  assert.equal(snap.exists, true);
  const data = snap.data();
  assert.equal(data.doctorId, DOCTOR_ID);
  assert.equal(data.rating, 5);
  assert.equal(data.maskedName, 'J. D.');
  assert.equal(Object.prototype.hasOwnProperty.call(data, 'patientId'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(data, 'appointmentId'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(data, 'patientName'), false);
});

test('anonymous reader cannot read private reviews collection', async () => {
  await seedReviewDocs();

  const anonCtx = testEnv.unauthenticatedContext();
  await assertFails(
    anonCtx.firestore().collection('reviews').doc(REVIEW_ID).get(),
  );
});
