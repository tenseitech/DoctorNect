'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  RESET_SQL,
  assertAllAppTablesEmpty,
  evaluateSeedSystemConfigAllowance,
  MIGRATION_SEED_SYSTEM_CONFIG_KEYS,
} = require('../db/prod_rds_reset_empty');

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

test('evaluateSeedSystemConfigAllowance accepts exact migration seed keys only', () => {
  assert.deepEqual(
    evaluateSeedSystemConfigAllowance(['demo_accounts', 'promoted_ads']),
    { onlySeed: true, keys: ['demo_accounts', 'promoted_ads'] },
  );
  assert.equal(evaluateSeedSystemConfigAllowance(['patient_module_status']).onlySeed, false);
  assert.equal(evaluateSeedSystemConfigAllowance([]).onlySeed, false);
  assert.equal(MIGRATION_SEED_SYSTEM_CONFIG_KEYS.has('demo_accounts'), true);
});

test('assertAllAppTablesEmpty allow-seed bypass only for system_config seed keys', async () => {
  const mock = {
    query: async (sql) => {
      if (sql.includes('pg_class')) {
        return {
          rows: [
            { schema_name: 'public', table_name: 'system_config' },
            { schema_name: 'public', table_name: 'users' },
          ],
        };
      }
      if (sql.includes('config_key')) {
        return { rows: [{ config_key: 'demo_accounts' }, { config_key: 'promoted_ads' }] };
      }
      if (sql.includes('system_config')) {
        return { rows: [{ n: '2' }] };
      }
      if (sql.includes('users')) {
        return { rows: [{ n: '0' }] };
      }
      return { rows: [] };
    },
  };
  const res = await assertAllAppTablesEmpty(mock, { allowSeedSystemConfig: true });
  assert.equal(res.violations.length, 0);
});