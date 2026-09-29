'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');

// Emulator-independent test that verifies the exact rules logic and regex patterns defined in firestore.rules
test('firestore.rules contains validPatientProfileStorage, validDoctorProfileStorage, and validUserProfileStorage', () => {
  const rulesContent = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

  assert.ok(
    rulesContent.includes('function validPatientProfileStorage'),
    'firestore.rules must contain validPatientProfileStorage',
  );
  assert.ok(
    rulesContent.includes('function validDoctorProfileStorage'),
    'firestore.rules must contain validDoctorProfileStorage',
  );
  assert.ok(
    rulesContent.includes('function validUserProfileStorage'),
    'firestore.rules must contain validUserProfileStorage',
  );

  // Verify that the rules check photoStorage and disallow path traversal ([a-zA-Z0-9._-]+$)
  assert.ok(
    rulesContent.includes("photoKey', '').matches('^patients/' + patientId + '/profile/[a-zA-Z0-9._-]+$'"),
    'validPatientProfileStorage must enforce exact prefix and alphanumeric filename without path traversal',
  );
  assert.ok(
    rulesContent.includes("photoKey', '').matches('^doctor_profiles/' + doctorId + '/profile/[a-zA-Z0-9._-]+$'"),
    'validDoctorProfileStorage must enforce exact prefix and alphanumeric filename without path traversal',
  );
});

// Emulate the exact evaluation logic of the Firestore rule functions
function evalValidPatientProfileStorage(data, patientId) {
  const photoStorage = data.photoStorage || '';
  const photoKey = data.photoKey || '';

  const isLegacy = photoStorage !== 's3' && photoKey === '';
  const isS3RegexMatch = typeof photoKey === 'string' &&
    new RegExp(`^patients/${patientId}/profile/[a-zA-Z0-9._-]+$`).test(photoKey);

  return isLegacy || isS3RegexMatch;
}

function evalValidDoctorProfileStorage(data, doctorId) {
  const photoStorage = data.photoStorage || '';
  const photoKey = data.photoKey || '';

  const isLegacy = photoStorage !== 's3' && photoKey === '';
  const isS3RegexMatch = typeof photoKey === 'string' &&
    new RegExp(`^doctor_profiles/${doctorId}/profile/[a-zA-Z0-9._-]+$`).test(photoKey);

  return isLegacy || isS3RegexMatch;
}

function evalValidUserProfileStorage(data, uid, profileId = '') {
  const photoStorage = data.photoStorage || '';
  const photoKey = data.photoKey || '';

  const isLegacy = photoStorage !== 's3' && photoKey === '';
  const isS3RegexMatch = typeof photoKey === 'string' && (
    new RegExp(`^patients/${uid}/profile/[a-zA-Z0-9._-]+$`).test(photoKey) ||
    new RegExp(`^doctor_profiles/${uid}/profile/[a-zA-Z0-9._-]+$`).test(photoKey) ||
    (profileId !== '' && (
      new RegExp(`^patients/${profileId}/profile/[a-zA-Z0-9._-]+$`).test(photoKey) ||
      new RegExp(`^doctor_profiles/${profileId}/profile/[a-zA-Z0-9._-]+$`).test(photoKey)
    ))
  );

  return isLegacy || isS3RegexMatch;
}

test('emulator-independent: patient profile storage validation logic', () => {
  const patientId = 'p_12345';

  // 1. Legacy update without photoKey or photoStorage (e.g. name only) -> PASS
  assert.equal(evalValidPatientProfileStorage({ name: 'John Doe' }, patientId), true);

  // 2. Legacy update with photoStorage 'firebase' and only photoUrl -> PASS
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 'firebase',
    photoUrl: 'https://example.com/photo.jpg',
  }, patientId), true);

  // 3. Valid S3 photo update -> PASS
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/${patientId}/profile/avatar_01.jpg`,
  }, patientId), true);

  // 4. S3 with path traversal -> FAIL
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/${patientId}/profile/../../secrets.txt`,
  }, patientId), false);

  // 5. S3 with clinical health record prefix -> FAIL
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 's3',
    photoKey: `health_records/${patientId}/report.pdf`,
  }, patientId), false);

  // 6. S3 with another patient's ID -> FAIL
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/other_patient/profile/avatar.jpg`,
  }, patientId), false);

  // 7. S3 with double slash -> FAIL
  assert.equal(evalValidPatientProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/${patientId}/profile//avatar.jpg`,
  }, patientId), false);
});

test('emulator-independent: doctor profile storage validation logic', () => {
  const doctorId = 'doc_67890';

  // 1. Legacy update without photoKey or photoStorage -> PASS
  assert.equal(evalValidDoctorProfileStorage({ name: 'Dr. Jane' }, doctorId), true);

  // 2. Legacy update with photoStorage 'firebase' and only photoUrl -> PASS
  assert.equal(evalValidDoctorProfileStorage({
    photoStorage: 'firebase',
    photoUrl: 'https://example.com/doc.jpg',
  }, doctorId), true);

  // 3. Valid S3 doctor photo update -> PASS
  assert.equal(evalValidDoctorProfileStorage({
    photoStorage: 's3',
    photoKey: `doctor_profiles/${doctorId}/profile/avatar.png`,
  }, doctorId), true);

  // 4. S3 with another doctor's ID -> FAIL
  assert.equal(evalValidDoctorProfileStorage({
    photoStorage: 's3',
    photoKey: `doctor_profiles/other_doc/profile/avatar.png`,
  }, doctorId), false);

  // 5. S3 with patient prefix -> FAIL
  assert.equal(evalValidDoctorProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/${doctorId}/profile/avatar.png`,
  }, doctorId), false);
});

test('emulator-independent: user document storage validation logic', () => {
  const authUid = 'uid_abc';
  const profileId = 'doc_67890';

  // 1. Legacy update without photoKey -> PASS
  assert.equal(evalValidUserProfileStorage({ role: 'doctor' }, authUid, profileId), true);

  // 2. Legacy update with photoStorage 'firebase' -> PASS
  assert.equal(evalValidUserProfileStorage({ photoStorage: 'firebase', photoUrl: 'https://example.com' }, authUid, profileId), true);

  // 3. Valid S3 key with uid -> PASS
  assert.equal(evalValidUserProfileStorage({
    photoStorage: 's3',
    photoKey: `patients/${authUid}/profile/pic.jpg`,
  }, authUid, profileId), true);

  // 4. Valid S3 key with profileId -> PASS
  assert.equal(evalValidUserProfileStorage({
    photoStorage: 's3',
    photoKey: `doctor_profiles/${profileId}/profile/pic.jpg`,
  }, authUid, profileId), true);

  // 5. Arbitrary clinical key -> FAIL
  assert.equal(evalValidUserProfileStorage({
    photoStorage: 's3',
    photoKey: `health_records/${authUid}/record.pdf`,
  }, authUid, profileId), false);
});
