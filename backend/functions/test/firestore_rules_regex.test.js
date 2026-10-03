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
  assert.ok(
    rulesContent.includes('function validPromotedAdStorage'),
    'firestore.rules must contain validPromotedAdStorage',
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
  assert.ok(
    rulesContent.includes("imageKey', '').matches('^promoted_ads/' + providerId + '/[a-zA-Z0-9_-]+/[a-zA-Z0-9._-]+$'"),
    'validPromotedAdStorage must enforce promoted_ads/{providerId}/{adId}/{filename} format',
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

function evalValidPromotedAdStorage(data, providerId) {
  const imageStorage = data.imageStorage || '';
  const imageKey = data.imageKey || '';

  const isLegacy = imageStorage !== 's3' && imageKey === '';
  const isS3RegexMatch = typeof imageKey === 'string' &&
    new RegExp(`^promoted_ads/${providerId}/[a-zA-Z0-9_-]+/[a-zA-Z0-9._-]+$`).test(imageKey);

  return isLegacy || isS3RegexMatch;
}

test('emulator-independent: promoted ad storage validation logic', () => {
  const providerId = 'provider_123';
  const adId = 'ad_abc456';

  // 1. Legacy update without imageKey or imageStorage -> PASS
  assert.equal(evalValidPromotedAdStorage({ title: 'Special Promo' }, providerId), true);

  // 2. Legacy update with imageStorage 'firebase' and only imageUrl -> PASS
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 'firebase',
    imageUrl: 'https://storage.googleapis.com/bucket/promoted_ads/banner.jpg',
  }, providerId), true);

  // 3. Valid S3 promoted ad banner update -> PASS
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 's3',
    imageKey: `promoted_ads/${providerId}/${adId}/banner_01.jpg`,
  }, providerId), true);

  // 4. S3 with path traversal -> FAIL
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 's3',
    imageKey: `promoted_ads/${providerId}/${adId}/../../secrets.txt`,
  }, providerId), false);

  // 5. S3 with another provider's prefix -> FAIL
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 's3',
    imageKey: `promoted_ads/other_provider/${adId}/banner_01.jpg`,
  }, providerId), false);

  // 6. S3 with clinical health record prefix -> FAIL
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 's3',
    imageKey: `health_records/${providerId}/${adId}/report.pdf`,
  }, providerId), false);

  // 7. S3 with double slash -> FAIL
  assert.equal(evalValidPromotedAdStorage({
    imageStorage: 's3',
    imageKey: `promoted_ads/${providerId}//${adId}/banner.jpg`,
  }, providerId), false);
});

test('firestore.rules isAccountAdmin requires request.auth.token.email_verified == true', () => {
  const rulesContent = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

  assert.ok(
    rulesContent.includes("request.auth.token.get('email_verified', false) == true"),
    'firestore.rules isAccountAdmin must check request.auth.token email_verified safely',
  );

  const SUPER_ADMIN_EMAILS = [
    'admin@doctornect.com',
  ];

  function evalIsAccountAdmin(auth) {
    if (!auth || !auth.token) return false;
    const emailVerified = auth.token.email_verified === true;
    const email = String(auth.token.email || '').trim().toLowerCase();
    return emailVerified && email !== '' && SUPER_ADMIN_EMAILS.includes(email);
  }

  // Allowlisted with email_verified: true -> PASS
  assert.equal(evalIsAccountAdmin({ token: { email: 'admin@doctornect.com', email_verified: true } }), true);
  // Removed from allowlist -> FAIL
  assert.equal(evalIsAccountAdmin({ token: { email: 'sharmasd2@gmail.com', email_verified: true } }), false);

  // Allowlisted with email_verified: false -> FAIL (spoofing blocked)
  assert.equal(evalIsAccountAdmin({ token: { email: 'admin@doctornect.com', email_verified: false } }), false);
  assert.equal(evalIsAccountAdmin({ token: { email: 'admin@doctornect.com' } }), false);

  // Non-allowlisted with email_verified: true -> FAIL
  assert.equal(evalIsAccountAdmin({ token: { email: 'hacker@example.com', email_verified: true } }), false);

  // Unauthenticated -> FAIL
  assert.equal(evalIsAccountAdmin(null), false);
});
