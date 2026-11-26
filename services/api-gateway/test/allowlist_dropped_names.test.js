'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const config = require('../src/config');

// Tables / RPCs that no longer exist in the Postgres schema must not stay reachable through the
// gateway allowlists (PROJECT_ANALYSIS.md L2).
const DROPPED_TABLES = ['lab_catalog', 'medicine_suggestions'];
const DROPPED_RPCS = ['delete_my_account'];

test('dropped tables are not allowlisted for clients or the service role', () => {
  for (const t of DROPPED_TABLES) {
    assert.equal(config.clientAllowedTables.includes(t), false, `client: ${t}`);
    assert.equal(config.serviceRoleAllowedTables.includes(t), false, `service: ${t}`);
  }
});

test('dropped RPCs are not allowlisted', () => {
  for (const r of DROPPED_RPCS) {
    assert.equal(config.allowedRpcs.includes(r), false, r);
    assert.equal(config.serviceRoleAllowedRpcs.includes(r), false, r);
  }
});
