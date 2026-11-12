'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { ALLOWLIST_TABLES, probeSql } = require('./anon_surface_audit');

test('ALLOWLIST_TABLES includes review_public and doctor_directory', () => {
  assert.ok(ALLOWLIST_TABLES.has('review_public'));
  assert.ok(ALLOWLIST_TABLES.has('doctor_directory'));
});

test('probeSql treats 42501 as expected failure', async () => {
  const client = {
    async query(sql) {
      if (sql.startsWith('SAVEPOINT')) return {};
      if (sql.startsWith('SELECT 1 FROM public.secret')) {
        const err = new Error('permission denied');
        err.code = '42501';
        throw err;
      }
      if (sql.startsWith('ROLLBACK TO SAVEPOINT')) return {};
      if (sql.startsWith('RELEASE SAVEPOINT')) return {};
      return { rows: [], rowCount: 0 };
    },
  };

  const result = await probeSql(client, 'SELECT 1 FROM public.secret_table LIMIT 0;', {
    expectSuccess: false,
    allowedErrorCodes: ['42501'],
  });
  assert.equal(result.ok, true);
  assert.equal(result.code, '42501');
});
