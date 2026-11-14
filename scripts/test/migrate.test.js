'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  applySingleMigration,
  parseMigrationCliArgs,
  assertPendingMigrationsInOrder,
  loadAppliedMigrationsMap,
} = require('../db/migrate');

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

test('parseMigrationCliArgs: --execute with --dry-run or --dry-run-all forces dry-run (no execute)', () => {
  assert.deepEqual(parseMigrationCliArgs(['--execute', '--dry-run']), {
    isExecute: false,
    isDryRun: true,
    isDryRunAll: false,
    allowOutOfOrder: false,
  });
  assert.deepEqual(parseMigrationCliArgs(['--execute', '--dry-run-all']), {
    isExecute: false,
    isDryRun: true,
    isDryRunAll: true,
    allowOutOfOrder: false,
  });
  assert.deepEqual(parseMigrationCliArgs(['--execute']), {
    isExecute: true,
    isDryRun: false,
    isDryRunAll: false,
    allowOutOfOrder: false,
  });
});

test('loadAppliedMigrationsMap: isExecute=false skips CREATE TABLE (dry-run path)', async () => {
  const executed = [];
  const mockClient = {
    query: async (sql) => {
      executed.push(String(sql));
      if (sql.includes("table_name = '_schema_migrations'")) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  };
  const { appliedMap, supabaseMigExists } = await loadAppliedMigrationsMap(mockClient, false);
  assert.equal(appliedMap.size, 0);
  assert.equal(supabaseMigExists, false);
  assert.ok(!executed.some((q) => q.includes('CREATE TABLE IF NOT EXISTS public._schema_migrations')));
  assert.ok(!executed.some((q) => q.includes('supabase_migrations')));
});

test('loadAppliedMigrationsMap: supabase_migrations sync failure is logged and rethrown', async () => {
  const mockClient = {
    query: async (sql) => {
      if (sql.includes('CREATE TABLE IF NOT EXISTS public._schema_migrations')) {
        return { rows: [] };
      }
      if (sql.includes("table_schema = 'supabase_migrations'")) {
        return { rows: [{ '?column?': 1 }] };
      }
      if (sql.includes('INSERT INTO public._schema_migrations')) {
        throw new Error('permission denied for schema supabase_migrations');
      }
      if (sql.includes('SELECT version, checksum FROM public._schema_migrations')) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  };
  await assert.rejects(
    () => loadAppliedMigrationsMap(mockClient, true),
    /permission denied for schema supabase_migrations/,
  );
});

test('assertPendingMigrationsInOrder: rejects older pending on production/rehearsal', () => {
  const appliedMap = new Map([
    ['20261001000001', 'abc'],
    ['20261001000003', 'def'],
  ]);
  const files = [
    '20261001000001_first.sql',
    '20261001000002_gap.sql',
    '20261001000003_third.sql',
  ];
  assert.throws(
    () =>
      assertPendingMigrationsInOrder({
        files,
        appliedMap,
        target: 'production',
        allowOutOfOrder: false,
      }),
    /Out-of-order pending migration.*20261001000002_gap/,
  );
  assert.doesNotThrow(() =>
    assertPendingMigrationsInOrder({
      files,
      appliedMap,
      target: 'production',
      allowOutOfOrder: true,
    }),
  );
  assert.doesNotThrow(() =>
    assertPendingMigrationsInOrder({
      files,
      appliedMap,
      target: 'staging',
      allowOutOfOrder: false,
    }),
  );
});

test('migrate: computeChecksum normalizes CRLF and LF to identical SHA-256 digest', () => {
  const { computeChecksum } = require('../db/migrate');
  const {
    computeLegacyRawChecksum,
    ledgerChecksumMatches,
  } = require('../lib/migration_checksum');
  const lfContent = '-- migration\nSELECT 1;\nSELECT 2;\n';
  const crlfContent = '-- migration\r\nSELECT 1;\r\nSELECT 2;\r\n';

  const lfChecksum = computeChecksum(lfContent);
  const crlfChecksum = computeChecksum(crlfContent);

  assert.equal(typeof lfChecksum, 'string');
  assert.equal(lfChecksum.length, 64);
  assert.equal(crlfChecksum, lfChecksum, 'CRLF and LF must produce byte-identical SHA-256 hashes');

  const legacyCrlf = computeLegacyRawChecksum(crlfContent);
  assert.notEqual(legacyCrlf, lfChecksum, 'legacy raw CRLF hash must differ from normalized hash');
  assert.ok(ledgerChecksumMatches(crlfContent, lfChecksum), 'ledger accepts normalized checksum');
  assert.ok(ledgerChecksumMatches(crlfContent, legacyCrlf), 'ledger accepts legacy raw-byte checksum');
  assert.ok(!ledgerChecksumMatches(crlfContent, '0'.repeat(64)), 'rejects unrelated checksum');
});


