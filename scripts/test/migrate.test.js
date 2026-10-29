'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { applySingleMigration } = require('../db/migrate');

test('migrate: applySingleMigration succeeds without supabase_migrations schema', async () => {
  const executedQueries = [];
  const mockClient = {
    query: async (sql, params) => {
      executedQueries.push({ sql: sql.trim(), params });
      if (sql.includes('SELECT version, checksum FROM public._schema_migrations')) {
        return { rows: [{ version: '20261029000001', checksum: 'abc123mock' }] };
      }
      if (sql.includes('COMMIT')) {
        return { command: 'COMMIT' };
      }
      return { rows: [], command: 'OK' };
    },
  };

  const ok = await applySingleMigration({
    client: mockClient,
    version: '20261029000001',
    file: '20261029000001_guard_and_drift_fixes.sql',
    sqlContent: 'SELECT 1;',
    checksum: 'abc123mock',
    supabaseMigExists: false,
  });

  assert.equal(ok, true);
  // Ensure NO queries touched supabase_migrations
  const touchedSupabase = executedQueries.some(q => q.sql.includes('supabase_migrations'));
  assert.equal(touchedSupabase, false, 'Should not execute any query touching supabase_migrations when schema does not exist');

  // Verify sequence: BEGIN -> sqlContent -> INSERT ledger -> COMMIT -> SELECT verify
  assert.equal(executedQueries[0].sql, 'BEGIN');
  assert.equal(executedQueries[1].sql, 'SELECT 1;');
  assert.ok(executedQueries[2].sql.includes('INSERT INTO public._schema_migrations'));
  assert.equal(executedQueries[3].sql, 'COMMIT');
  assert.ok(executedQueries[4].sql.includes('SELECT version, checksum FROM public._schema_migrations'));
});

test('migrate: applySingleMigration uses SAVEPOINT for supabase_migrations when present', async () => {
  const executedQueries = [];
  const mockClient = {
    query: async (sql, params) => {
      executedQueries.push({ sql: sql.trim(), params });
      if (sql.includes('SELECT version, checksum FROM public._schema_migrations')) {
        return { rows: [{ version: '20261029000001', checksum: 'abc123mock' }] };
      }
      if (sql.includes('COMMIT')) {
        return { command: 'COMMIT' };
      }
      return { rows: [], command: 'OK' };
    },
  };

  const ok = await applySingleMigration({
    client: mockClient,
    version: '20261029000001',
    file: '20261029000001_guard_and_drift_fixes.sql',
    sqlContent: 'SELECT 1;',
    checksum: 'abc123mock',
    supabaseMigExists: true,
  });

  assert.equal(ok, true);
  const savepointIdx = executedQueries.findIndex(q => q.sql.includes('SAVEPOINT sp_supamig'));
  assert.ok(savepointIdx > -1, 'Must use savepoint for supabase_migrations insert');
});

test('migrate: applySingleMigration throws if COMMIT returns unexpected command tag', async () => {
  const mockClient = {
    query: async (sql) => {
      if (sql.includes('COMMIT')) {
        return { command: 'ROLLBACK' };
      }
      return { rows: [], command: 'OK' };
    },
  };

  await assert.rejects(
    async () => {
      await applySingleMigration({
        client: mockClient,
        version: '20261029000001',
        file: '20261029000001_guard_and_drift_fixes.sql',
        sqlContent: 'SELECT 1;',
        checksum: 'abc123mock',
        supabaseMigExists: false,
      });
    },
    /COMMIT returned unexpected command tag: "ROLLBACK"/
  );
});

test('migrate: applySingleMigration throws if ledger verification row is absent post-commit', async () => {
  const mockClient = {
    query: async (sql) => {
      if (sql.includes('SELECT version, checksum FROM public._schema_migrations')) {
        return { rows: [] }; // Absent!
      }
      if (sql.includes('COMMIT')) {
        return { command: 'COMMIT' };
      }
      return { rows: [], command: 'OK' };
    },
  };

  await assert.rejects(
    async () => {
      await applySingleMigration({
        client: mockClient,
        version: '20261029000001',
        file: '20261029000001_guard_and_drift_fixes.sql',
        sqlContent: 'SELECT 1;',
        checksum: 'abc123mock',
        supabaseMigExists: false,
      });
    },
    /FATAL: Migration ledger check failed/
  );
});

