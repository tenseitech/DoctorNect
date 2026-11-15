'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeRdsMigrationSql,
  shouldNormalizeRdsSql,
} = require('../lib/rds_migration_sql_normalize');

const env0 = { ...process.env };

afterEach(() => {
  process.env = { ...env0 };
});

test('normalizes OWNER TO postgres on production target', () => {
  process.env.PROD_RDS_USER = 'doctornect_admin';
  const sql = 'ALTER VIEW public.patient_safe OWNER TO postgres;';
  const out = normalizeRdsMigrationSql(sql, 'production');
  assert.match(out, /OWNER TO doctornect_admin/i);
});

test('strips postgres from GRANT list', () => {
  const sql = 'GRANT ALL ON TABLE public.otp_challenges TO postgres, service_role;';
  const out = normalizeRdsMigrationSql(sql, 'production');
  assert.doesNotMatch(out, /postgres/i);
  assert.match(out, /service_role/);
});

test('staging target unchanged', () => {
  assert.equal(shouldNormalizeRdsSql('staging'), false);
  const sql = 'ALTER VIEW x OWNER TO postgres;';
  assert.equal(normalizeRdsMigrationSql(sql, 'staging'), sql);
});