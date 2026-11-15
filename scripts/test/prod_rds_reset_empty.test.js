'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { RESET_SQL, assertAllAppTablesEmpty } = require('../db/prod_rds_reset_empty');

test('RESET_SQL drops and recreates app schemas only', () => {
  assert.ok(RESET_SQL.some((l) => l.includes('DROP SCHEMA IF EXISTS public CASCADE')));
  assert.ok(RESET_SQL.some((l) => l.includes('CREATE SCHEMA public')));
  assert.equal(RESET_SQL.filter((l) => l.includes('DROP ROLE')).length, 0);
});

test('assertAllAppTablesEmpty aborts when rows present', async () => {
  const mock = {
    query: async (sql) => {
      if (sql.includes('pg_class')) {
        return { rows: [{ schema_name: 'public', table_name: 'users' }] };
      }
      if (sql.includes('count(*)')) {
        return { rows: [{ n: '3' }] };
      }
      return { rows: [] };
    },
  };
  const res = await assertAllAppTablesEmpty(mock);
  assert.equal(res.violations.length, 1);
  assert.equal(res.totalRows, 3);
});