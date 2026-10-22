'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { supabaseCompatibleCustomClaims } = require('../registration_otp');

process.env.USE_SUPABASE_DB_DOCTOR_PATIENT = 'true';

// Mock Firebase Admin Auth
function createMockAuth() {
  const users = new Map();
  return {
    users,
    async createUser({ uid, email }) {
      const record = { uid, email, customClaims: {} };
      users.set(uid, record);
      return record;
    },
    async setCustomUserClaims(uid, claims) {
      const user = users.get(uid);
      if (!user) throw new Error(`User ${uid} not found`);
      user.customClaims = { ...claims };
    },
    async getUser(uid) {
      const user = users.get(uid);
      if (!user) throw new Error(`User ${uid} not found`);
      return user;
    },
    async createCustomToken(uid, developerClaims) {
      return `mock_token_for_${uid}_claims_${JSON.stringify(developerClaims)}`;
    },
  };
}

test('Claims: brand-new user created with flag ON receives Supabase-compatible claims without Firestore trigger', async () => {
  const mockAuth = createMockAuth();
  const newUid = 'patient_brand_new_123';
  const role = 'patient';

  // 1. Create brand new user in Auth
  await mockAuth.createUser({ uid: newUid, email: 'newpatient@example.com' });

  // 2. Set claims using the server registration/approval logic
  const targetClaims = supabaseCompatibleCustomClaims(role);
  assert.deepEqual(targetClaims, {
    role: 'authenticated',
    app_role: 'patient',
    user_role: 'patient',
  });

  await mockAuth.setCustomUserClaims(newUid, targetClaims);

  // 3. Verify user record carries the custom claims immediately
  const userRecord = await mockAuth.getUser(newUid);
  assert.equal(userRecord.customClaims.role, 'authenticated');
  assert.equal(userRecord.customClaims.app_role, 'patient');

  // 4. Force token refresh: mint new token with claims
  const customToken = await mockAuth.createCustomToken(newUid, userRecord.customClaims);
  assert.ok(customToken.includes('"role":"authenticated"'));
  assert.ok(customToken.includes('"app_role":"patient"'));
});

test('Claims: doctor approval sets verified=true in claims and keeps role=authenticated', async () => {
  const mockAuth = createMockAuth();
  const doctorUid = 'doc_approved_456';
  await mockAuth.createUser({ uid: doctorUid, email: 'doctor@example.com' });

  const doctorApprovedClaims = supabaseCompatibleCustomClaims('doctor', { verified: true });
  assert.equal(doctorApprovedClaims.role, 'authenticated');
  assert.equal(doctorApprovedClaims.app_role, 'doctor');
  assert.equal(doctorApprovedClaims.verified, true);

  await mockAuth.setCustomUserClaims(doctorUid, doctorApprovedClaims);

  const updatedRecord = await mockAuth.getUser(doctorUid);
  assert.equal(updatedRecord.customClaims.verified, true);
  assert.equal(updatedRecord.customClaims.role, 'authenticated');
});
