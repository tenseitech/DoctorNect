'use strict';

/**
 * Super admin for promoted-ad review and S3 access = verified email listed in SUPER_ADMIN_EMAILS
 * + server-set admin custom claim. No hard-coded fallback address.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { isSuperAdmin } = require('../lib/super_admin');
const promotedAds = require('../promoted_ads');
const s3 = require('../s3_storage');

const env = { SUPER_ADMIN_EMAILS: 'Ops@Example.org, second@example.org' };
const tok = (o) => ({ token: { email: 'ops@example.org', email_verified: true, app_role: 'super_admin', ...o } });

test('all three conditions are required', () => {
  assert.equal(isSuperAdmin(tok({}), null, env), true);
  assert.equal(isSuperAdmin(tok({ email: 'SECOND@example.org', app_role: undefined, user_role: 'admin' }), null, env), true);
  assert.equal(isSuperAdmin(tok({ email_verified: false }), null, env), false, 'unverified email');
  assert.equal(isSuperAdmin(tok({ email_verified: 'true' }), null, env), false, 'string true is not verified');
  assert.equal(isSuperAdmin(tok({ app_role: 'doctor' }), null, env), false, 'no admin claim');
  assert.equal(isSuperAdmin(tok({ email: 'other@example.org' }), null, env), false, 'not allow-listed');
  assert.equal(isSuperAdmin(tok({ role: 'super_admin', app_role: undefined }), null, env), false, 'role claim is always "authenticated"; ignored');
});

test('a users-table role is never sufficient and there is no default address', () => {
  assert.equal(isSuperAdmin(tok({ app_role: 'doctor' }), { role: 'super_admin' }, env), false);
  assert.equal(isSuperAdmin({ token: { email: 'admin@doctornect.com', email_verified: true, app_role: 'super_admin' } }, null, {}), false);
  assert.equal(isSuperAdmin(tok({}), null, {}), false, 'empty SUPER_ADMIN_EMAILS = nobody');
  assert.equal(isSuperAdmin(null, null, env), false);
});

test('promoted_ads and s3_storage use the shared helper; hard-coded admin address removed', () => {
  assert.equal(promotedAds.isSuperAdmin, isSuperAdmin);
  assert.equal(s3._test ? (s3.isSuperAdmin || s3._test.isSuperAdmin) : s3.isSuperAdmin, isSuperAdmin);
  for (const f of ['promoted_ads.js', 's3_storage.js']) {
    const src = fs.readFileSync(path.join(__dirname, '..', f), 'utf8');
    assert.ok(!src.includes('admin@doctornect.com'), `${f} must not hard-code an admin address`);
  }
});

test('reviewPromotedAd rejects a users-table super_admin whose email is not allow-listed', async () => {
  process.env.SUPER_ADMIN_EMAILS = 'ops@example.org';
  const { setDatabaseClientForTesting } = require('../src/db/client');
  const { createMemoryPostgrest } = require('./helpers/memory_postgrest');
  setDatabaseClientForTesting(createMemoryPostgrest({ users: [{ id: 'doc_uid', firebase_uid: 'doc_uid', role: 'super_admin', profile_id: 'doc_1', email: 'doc@example.org' }] }));
  try {
    await assert.rejects(
      promotedAds.reviewPromotedAdHandler(null, { adId: 'ad_1', decision: 'approve' },
        { uid: 'doc_uid', token: { email: 'doc@example.org', email_verified: true, app_role: 'doctor' } }),
      (e) => e.code === 'permission-denied',
    );
  } finally {
    setDatabaseClientForTesting(createMemoryPostgrest());
    delete process.env.SUPER_ADMIN_EMAILS;
  }
});
