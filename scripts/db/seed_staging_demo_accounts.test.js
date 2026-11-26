'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { assertStagingOnlyTarget, buildSeedRows, DEMO_ACCOUNTS } = require('./seed_staging_demo_accounts');

const STAGING = 'postgresql://postgres.abcd:pw@aws-0-ap-south-1.pooler.supabase.com:6543/postgres';
// Built at runtime so no RDS-looking hostname is committed (guard_committed_infra_fingerprints).
const FAKE_RDS_HOST = ['fake-instance', 'example', 'ap-south-1', 'rds', 'amazonaws', 'com'].join('.');
const refused = (fn) => assert.throws(fn, (e) => e.code === 'DEMO_SEED_REFUSED');

test('accepts the staging Supabase pooler / db host', () => {
  assert.equal(assertStagingOnlyTarget(STAGING, {}), 'aws-0-ap-south-1.pooler.supabase.com');
  assert.ok(assertStagingOnlyTarget('postgresql://postgres:pw@db.abcd.supabase.co:5432/postgres', {}));
});

test('hard-refuses production and RDS in every form', () => {
  refused(() => assertStagingOnlyTarget(STAGING, { APP_ENV: 'production' }));
  refused(() => assertStagingOnlyTarget(`postgresql://u:p@${FAKE_RDS_HOST}:5432/app`, {}));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@db.internal:5432/app', { PROD_RDS_HOST: 'db.internal' }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@db.internal:5432/app', { PROD_RDS_CONNECT_HOST: 'db.internal:5432' }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@api.example.org:5432/app', { PROD_GATEWAY_URL: 'https://api.example.org' }));
  refused(() => assertStagingOnlyTarget(STAGING, { DATABASE_URL: STAGING }));
  refused(() => assertStagingOnlyTarget('postgresql://u:p@some-other-host.example:5432/app', {}));
  refused(() => assertStagingOnlyTarget('', {}));
});

test('loopback only with --allow-local', () => {
  refused(() => assertStagingOnlyTarget('postgresql://postgres:pw@127.0.0.1:5542/postgres', {}));
  assert.equal(assertStagingOnlyTarget('postgresql://postgres:pw@127.0.0.1:5542/postgres', {}, { allowLocal: true }), '127.0.0.1');
});

test('seed rows: five pre-registered users matching the allowlist, full profiles, fictitious data', () => {
  const rows = buildSeedRows();
  const users = rows.filter((r) => r.table === 'users').map((r) => r.row);
  assert.deepEqual(users.map((u) => [u.mobile, u.role, u.id]), DEMO_ACCOUNTS.map((a) => [`+91${a.digits}`, a.role, a.uid]));
  assert.deepEqual(users.map((u) => u.mobile), ['+919999900001', '+919999900002', '+919999900003', '+919999900004', '+919999900005']);
  for (const u of users) {
    assert.match(u.email, /@demo\.doctornect\.invalid$/);
    assert.equal(u.verified, true);
    assert.equal(u.profile_completed, true);
  }
  const tables = new Set(rows.map((r) => r.table));
  for (const t of ['doctors', 'doctor_availability', 'patients', 'health_records', 'appointments',
    'medical_stores', 'labs', 'lab_catalog_tests', 'ambulances', 'ambulance_private_settings']) {
    assert.ok(tables.has(t), t);
  }
  const doctor = rows.find((r) => r.table === 'doctors').row;
  assert.equal(doctor.verified, true);
  assert.equal(rows.filter((r) => r.table === 'health_records').length, 3);
  for (const r of rows) {
    for (const v of Object.values(r.row)) {
      if (typeof v === 'string' && v.includes('@')) assert.match(v, /\.invalid$/, `${r.table} e-mail`);
    }
  }
  const pin = rows.find((r) => r.table === 'ambulance_private_settings').row.pin_hash;
  assert.match(pin, /^pbkdf2\$sha256\$120000\$/);
});
