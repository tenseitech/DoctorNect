'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  compareInfraCatalogs,
  filterComparableExtensions,
  mergeCatalogDiffs,
  SUPABASE_ONLY_EXTENSIONS,
} = require('../db/schema_diff');

test('schema_diff: filterComparableExtensions drops Supabase-only names', () => {
  const rows = [
    { extname: 'pgcrypto', extversion: '1.3' },
    { extname: 'pg_graphql', extversion: '1.0' },
    { extname: 'uuid-ossp', extversion: '1.1' },
  ];
  const filtered = filterComparableExtensions(rows);
  assert.deepEqual(
    filtered.map((r) => r.extname),
    ['pgcrypto', 'uuid-ossp'],
  );
  assert.ok(SUPABASE_ONLY_EXTENSIONS.has('pg_graphql'));
});

test('schema_diff: compareInfraCatalogs flags missing auth.uid on RDS', () => {
  const staging = {
    authFunctions: [
      { proname: 'jwt', def_hash: 'aaa' },
      { proname: 'uid', def_hash: 'bbb' },
      { proname: 'role', def_hash: 'ccc' },
    ],
    roles: [{ rolname: 'anon', rolcanlogin: false }],
    authSchemaGrants: [{ grantee: 'PUBLIC', privilege_type: 'USAGE' }],
    authFunctionGrants: [],
  };
  const target = {
    authFunctions: [{ proname: 'jwt', def_hash: 'aaa' }],
    roles: [{ rolname: 'anon', rolcanlogin: false }],
    authSchemaGrants: [],
    authFunctionGrants: [],
  };
  const diffs = compareInfraCatalogs(staging, target, 'rehearsal');
  assert.ok(diffs.some((d) => d.category === 'AUTH_SHIM_MISSING' && d.key === 'auth.uid()'));
  assert.ok(diffs.some((d) => d.category === 'AUTH_GRANT_MISSING'));
});

test('schema_diff: mergeCatalogDiffs combines public and infra checks', () => {
  const stagingCat = { columns: [], policies: [], functions: [], constraints: [], triggers: [], grants: [], extensions: [] };
  const targetCat = { columns: [], policies: [], functions: [], constraints: [], triggers: [], grants: [], extensions: [] };
  const stagingInfra = {
    authFunctions: [{ proname: 'jwt', def_hash: '1' }, { proname: 'uid', def_hash: '2' }, { proname: 'role', def_hash: '3' }],
    roles: [{ rolname: 'anon', rolcanlogin: false }, { rolname: 'authenticated', rolcanlogin: false }, { rolname: 'service_role', rolcanlogin: false }, { rolname: 'authenticator', rolcanlogin: true }],
    authSchemaGrants: [],
    authFunctionGrants: [],
  };
  const targetInfra = { ...stagingInfra, authFunctions: stagingInfra.authFunctions.slice(0, 3) };
  const diffs = mergeCatalogDiffs(stagingCat, targetCat, stagingInfra, targetInfra, 'rehearsal');
  assert.equal(diffs.length, 0);
});