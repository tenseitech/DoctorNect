'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  findDuplicateEnvKeysInContent,
  isProductionRelatedEnvKey,
  assertNoProductionDuplicateKeys,
  assertNoDuplicateEnvKeys,
} = require('../lib/env_duplicate_keys');
const { parseEnvFile } = require('../lib/parse_env_file');

test('findDuplicateEnvKeysInContent reports line numbers', () => {
  const content = `# comment
FOO=1
BAR=two

PROD_RDS_HOST=a.example.com
PROD_RDS_HOST=b.example.com
PROD_RDS_PORT=5433
PROD_RDS_PORT=5432
`;
  const dups = findDuplicateEnvKeysInContent(content);
  assert.strictEqual(dups.length, 2);
  assert.deepStrictEqual(dups[0], { key: 'PROD_RDS_HOST', lines: [5, 6] });
  assert.deepStrictEqual(dups[1], { key: 'PROD_RDS_PORT', lines: [7, 8] });
});

test('isProductionRelatedEnvKey', () => {
  assert.strictEqual(isProductionRelatedEnvKey('PROD_RDS_DB'), true);
  assert.strictEqual(isProductionRelatedEnvKey('REPLAY_DB_URL'), true);
  assert.strictEqual(isProductionRelatedEnvKey('STAGING_SUPABASE_URL'), false);
});

test('assertNoDuplicateEnvKeys fails on any duplicate', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'env-dup-'));
  const file = path.join(dir, '.env');
  fs.writeFileSync(file, 'APP_ENV=staging\nAPP_ENV=production\n', 'utf8');
  assert.throws(() => assertNoDuplicateEnvKeys(file), (err) => {
    assert.match(err.message, /Duplicate env key/);
    assert.match(err.message, /APP_ENV/);
    assert.match(err.message, /lines 1, 2/);
    return true;
  });
});

test('assertNoProductionDuplicateKeys allows duplicate non-prod keys', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'env-dup-'));
  const file = path.join(dir, '.env');
  fs.writeFileSync(file, 'APP_ENV=staging\nAPP_ENV=production\n', 'utf8');
  assert.doesNotThrow(() => assertNoProductionDuplicateKeys(file));
});

test('parseEnvFile throws on duplicate PROD_ keys', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'env-dup-'));
  const file = path.join(dir, '.env');
  fs.writeFileSync(
    file,
    'PROD_RDS_DB=postgres\nPROD_RDS_DB=doctornect\n',
    'utf8',
  );
  assert.throws(
    () => parseEnvFile(file),
    (err) => {
      assert.strictEqual(err.code, 'ENV_DUPLICATE_PRODUCTION_KEY');
      assert.match(err.message, /PROD_RDS_DB/);
      assert.match(err.message, /lines 1, 2/);
      return true;
    },
  );
});

test('parseEnvFile can skip production duplicate check', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'env-dup-'));
  const file = path.join(dir, '.env');
  fs.writeFileSync(
    file,
    'PROD_RDS_DB=postgres\nPROD_RDS_DB=doctornect\n',
    'utf8',
  );
  const env = parseEnvFile(file, { failOnProductionDuplicateKeys: false });
  assert.strictEqual(env.PROD_RDS_DB, 'doctornect');
});
