'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { assertStagingOnlyTarget, buildPlan } = require('./seed_staging_demo_accounts');

const STAGING = 'postgresql://postgres.abcd:pw@aws-0-ap-south-1.pooler.supabase.com:6543/postgres';
const refused = (fn) => assert.throws(fn, (e) => e.code === 'DEMO_SEED_REFUSED');

test('accepts the staging Supabase pooler / db host', () => {
  assert.equal(assertStagingOnlyTarget(STAGING, {}), 'aws-0-ap-south-1.pooler.supabase.com');
  assert.ok(assertStagingOnlyTarget('postgresql://postgres:pw@db.abcd.supabase.co:5432/postgres', {}));
});

test('hard-refuses production and RDS in every form', () => {
  refused(() => assertStagingOnlyTarget(STAGING, { APP_ENV: 'production' }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@doctornect.abc.ap-south-1.rds.amazonaws.com:5432/app', {}));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@db.internal:5432/app', { PROD_RDS_HOST: 'db.internal' }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@db.internal:5432/app', { PROD_RDS_CONNECT_HOST: 'db.internal:5432' }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@api.doctornect.com:5432/app', { PROD_GATEWAY_URL: 'https://api.doctornect.com' }));
  refused(() => assertStagingOnlyTarget(STAGING, { DATABASE_URL: STAGING }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@some-other-host.example:5432/app', {}));
  refused(() => assertStagingOnlyTarget('', {}));
});

test('loopback only with --allow-local', () => {
  refused(() => assertStagingOnlyTarget('postgresql://postgres:pw@127.0.0.1:5542/postgres', {}));
  assert.equal(assertStagingOnlyTarget('postgresql://postgres:pw@127.0.0.1:5542/postgres', {}, { allowLocal: true }), '127.0.0.1');
});

test('demo phones are pre-registered login users, one per role, from REVIEW_*_PHONES', () => {
  const plan = buildPlan({ REVIEW_DOCTOR_PHONES: '+91 98765 43210, 9000000000' });
  assert.deepEqual(plan.map((p) => p.role), ['patient', 'doctor', 'medicalStore', 'lab', 'ambulance']);
  const doc = plan.find((p) => p.role === 'doctor');
  assert.equal(doc.mobile, '+919876543210');
  assert.equal(doc.user.id, doc.uid);
  assert.equal(doc.user.firebase_uid, doc.uid);
  assert.equal(doc.user.profile_id, doc.profile.id);
  assert.ok(!doc.mobileMasked.includes('43210'));
});
