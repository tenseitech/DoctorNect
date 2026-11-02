'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  lookupMobileRegistration,
  postOtpAccountFieldsFromSearch,
  resolveMobileLookupConflict,
} = require('../registration_otp');

let origLegacy;

test.beforeEach(() => {
  origLegacy = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
  try {
    const { _resetRemoteConfigCache } = require('../sync_flags');
    _resetRemoteConfigCache();
  } catch (_) {}
});

test.afterEach(() => {
  if (origLegacy === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
  else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacy;
});

function emptyFirestoreDb() {
  const emptySnap = { empty: true, docs: [] };
  const chain = {
    where: () => chain,
    limit: () => ({ get: async () => emptySnap }),
    doc: () => ({ get: async () => ({ exists: false }) }),
  };
  return { collection: () => chain };
}

test('resolveMobileLookupConflict — existing patient login with matching role is allowed', () => {
  assert.equal(
    resolveMobileLookupConflict({
      found: true,
      registeredRole: 'patient',
      requestedRole: 'patient',
      intent: 'login',
    }),
    false,
  );
});

test('postOtpAccountFieldsFromSearch — maps findUserByMobileDigits shape', () => {
  assert.deepEqual(postOtpAccountFieldsFromSearch({ found: false }), {
    exists: false,
    role: null,
  });
  assert.deepEqual(postOtpAccountFieldsFromSearch({ found: true, role: 'patient' }), {
    exists: true,
    role: 'patient',
  });
});

test('lookupMobileRegistration — unauthenticated lookup stays conflict-only (no exists/role)', async () => {
  const res = await lookupMobileRegistration(emptyFirestoreDb(), {
    mobile: '9876543210',
    intent: 'login',
    role: 'patient',
  });
  assert.equal(res.ok, true);
  assert.ok(Object.prototype.hasOwnProperty.call(res, 'conflict'));
  assert.equal(Object.prototype.hasOwnProperty.call(res, 'exists'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(res, 'role'), false);
});
