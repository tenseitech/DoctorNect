'use strict';

/**
 * Identity mapping helpers (Firebase UID -> public.users row / UUID).
 * The Firestore -> Postgres user sync bridge (cross_role_sync.js) was removed with Firestore;
 * these tests keep coverage for the pure helpers that remain in use.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildUserSupabasePayload, normalizeRole } = require('../user_supabase_payload');
const { toUserUuid } = require('../user_id_bridge');

test('normalizeRole maps variants to schema-supported canonical roles', () => {
  assert.equal(normalizeRole('patient'), 'patient');
  assert.equal(normalizeRole('doctor'), 'doctor');
  assert.equal(normalizeRole('medical'), 'medicalStore');
  assert.equal(normalizeRole('medicalStore'), 'medicalStore');
  assert.equal(normalizeRole('pharmacy'), 'medicalStore');
  assert.equal(normalizeRole('lab'), 'lab');
  assert.equal(normalizeRole('ambulance'), 'ambulance');
  assert.equal(normalizeRole('super_admin'), 'superAdmin');
  assert.equal(normalizeRole('superadmin'), 'superAdmin');
  assert.equal(normalizeRole('admin'), 'admin');
});

test('buildUserSupabasePayload builds valid public.users row', () => {
  const payload = buildUserSupabasePayload('fb_uid_123', {
    role: 'medical',
    profileId: 'store_456',
    displayName: 'City Pharmacy',
    mobile: '+91 9876543210',
    email: 'test@pharmacy.com',
    profileCompleted: true,
    verified: true,
    status: 'approved',
    createdAt: '2026-01-01T10:00:00.000Z',
    updatedAt: '2026-01-01T10:00:00.000Z',
  });

  assert.equal(payload.skip, false);
  assert.equal(payload.row.firebase_uid, 'fb_uid_123');
  assert.equal(payload.row.role, 'medicalStore');
  assert.equal(payload.row.profile_id, 'store_456');
  assert.equal(payload.row.display_name, 'City Pharmacy');
  assert.equal(payload.row.email, 'test@pharmacy.com');
  assert.equal(payload.row.mobile, '9876543210');
  assert.equal(payload.row.profile_completed, true);
  assert.equal(payload.row.verified, true);
  assert.equal(payload.row.status, 'approved');
});

test('User ID Bridge: toUserUuid produces deterministic RFC 4122 v5 UUID', () => {
  const uid1 = 'sample_firebase_uid_12345';
  const uuid1 = toUserUuid(uid1);
  assert.equal(uuid1, toUserUuid(uid1), 'Repeated calls with same uid must produce identical UUID');
  assert.match(
    uuid1,
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    'Must be valid RFC 4122 UUID v5 (version 5, variant 1)',
  );
  assert.equal(toUserUuid(''), null);
  assert.equal(toUserUuid(null), null);
  assert.equal(toUserUuid(undefined), null);
});
