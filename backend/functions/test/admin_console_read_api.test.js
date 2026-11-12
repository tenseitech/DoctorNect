'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');

const {
  assertSuperAdminDbRecord,
  parseLimit,
  assertUserId,
  isDirectoryExcludedRow,
  allowedCorsOrigins,
  assertCorsOrigin,
  resetRateLimitsForTests,
} = require('../admin_console_read_security');
const { buildUserSummary } = require('../admin_console_read_api');

test('parseLimit caps oversized values', () => {
  assert.equal(parseLimit('9999'), 200);
  assert.equal(parseLimit('0'), 100);
  assert.equal(parseLimit('50'), 50);
});

test('assertUserId rejects injection-style ids', () => {
  assert.throws(() => assertUserId("x');drop table users;--"), HttpsError);
  assert.equal(assertUserId('wfT7vh7pakYR64scZkXrFcOefDZ2'), 'wfT7vh7pakYR64scZkXrFcOefDZ2');
});

test('assertSuperAdminDbRecord requires super_admin role in DB', () => {
  assert.throws(
    () =>
      assertSuperAdminDbRecord(
        { email: 'admin@doctornect.com', email_verified: true },
        { id: '1', email: 'admin@doctornect.com', role: 'doctor' },
      ),
    (e) => e instanceof HttpsError && e.code === 'permission-denied',
  );
});

test('assertSuperAdminDbRecord rejects token/db email mismatch', () => {
  assert.throws(
    () =>
      assertSuperAdminDbRecord(
        { email: 'other@doctornect.com', email_verified: true },
        { id: '1', email: 'admin@doctornect.com', role: 'super_admin', is_system_admin: true },
      ),
    (e) => e instanceof HttpsError,
  );
});

test('isDirectoryExcludedRow removes system admin', () => {
  assert.equal(
    isDirectoryExcludedRow({ email: 'admin@doctornect.com', role: 'super_admin', is_system_admin: true }),
    true,
  );
  assert.equal(isDirectoryExcludedRow({ email: 'doc@x.com', role: 'doctor' }), false);
});

test('buildUserSummary excludes platform system admin from counts', async () => {
  const supabase = {
    from() {
      return {
        select: async () => ({
          data: [
            { role: 'doctor', deactivated: false, status: 'approved', email: 'a@b.com' },
            { role: 'super_admin', is_system_admin: true, email: 'admin@doctornect.com', deactivated: false },
          ],
          error: null,
        }),
      };
    },
  };
  const summary = await buildUserSummary(supabase);
  assert.equal(summary.totalDirectory, 1);
  assert.equal(summary.byRole.doctor, 1);
  assert.equal(summary.byRole.super_admin, undefined);
});

test('CORS allow-list never includes wildcard', () => {
  const prev = process.env.ADMIN_CONSOLE_CORS_ORIGINS;
  process.env.ADMIN_CONSOLE_CORS_ORIGINS = '*,https://evil.com';
  const list = allowedCorsOrigins();
  assert.equal(list.includes('*'), false);
  if (prev === undefined) delete process.env.ADMIN_CONSOLE_CORS_ORIGINS;
  else process.env.ADMIN_CONSOLE_CORS_ORIGINS = prev;
});

test('assertCorsOrigin blocks unknown origins', () => {
  const prev = process.env.ADMIN_CONSOLE_CORS_ORIGINS_STAGING;
  process.env.ADMIN_CONSOLE_CORS_ORIGINS_STAGING = 'https://admin.example.com';
  assert.throws(
    () =>
      assertCorsOrigin({
        method: 'GET',
        headers: { origin: 'https://evil.example.com' },
      }),
    HttpsError,
  );
  if (prev === undefined) delete process.env.ADMIN_CONSOLE_CORS_ORIGINS_STAGING;
  else process.env.ADMIN_CONSOLE_CORS_ORIGINS_STAGING = prev;
});

test.after(() => {
  resetRateLimitsForTests();
});
