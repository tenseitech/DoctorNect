'use strict';

const fs = require('fs');
const path = require('path');

const BOOTSTRAP_PRE_MIGRATE = [
  '01_roles_and_extensions.sql',
  '02_auth_shim.sql',
  '03_legacy_compat.sql',
];

const SCRATCH_DB_PATTERN = /^migrate_scratch_\d+$/;

function assertScratchDatabaseName(dbName) {
  if (!dbName || !SCRATCH_DB_PATTERN.test(dbName)) {
    throw Object.assign(
      new Error(
        `[SCRATCH BOOTSTRAP REFUSED] current_database() must match migrate_scratch_<timestamp>, got: ${dbName || '<unknown>'}`,
      ),
      { code: 'SCRATCH_DB_GUARD' },
    );
  }
}

/**
 * Apply RDS bootstrap 01–03 to an isolated scratch DB only (never on production doctornect).
 */
async function applyBootstrapToScratchDatabase(client) {
  const dbRes = await client.query('SELECT current_database() AS db');
  const dbName = dbRes.rows[0].db;
  assertScratchDatabaseName(dbName);

  const bootstrapDir = path.resolve(__dirname, '../../db/rds_bootstrap');
  console.log(`\n[SCRATCH BOOTSTRAP] Applying 01–03 to ${dbName} (pre dry-run-all)...`);

  for (const file of BOOTSTRAP_PRE_MIGRATE) {
    const filePath = path.join(bootstrapDir, file);
    if (!fs.existsSync(filePath)) {
      throw new Error(`[SCRATCH BOOTSTRAP] missing ${filePath}`);
    }
    const sql = fs.readFileSync(filePath, 'utf8');
    await client.query(sql);
    console.log(`[SCRATCH BOOTSTRAP] ✔ ${file}`);
  }

  const check = await client.query(`
    SELECT
      to_regclass('auth.users') IS NOT NULL AS has_auth_users,
      EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'auth' AND p.proname = 'jwt') AS has_auth_jwt
  `);
  const row = check.rows[0] || {};
  if (!row.has_auth_users || !row.has_auth_jwt) {
    throw new Error('[SCRATCH BOOTSTRAP] verify failed: auth.users stub or auth.jwt() missing after 01–03');
  }
  console.log('[SCRATCH BOOTSTRAP] verify OK (auth.users + auth.jwt)\n');
}

module.exports = {
  applyBootstrapToScratchDatabase,
  assertScratchDatabaseName,
  SCRATCH_DB_PATTERN,
  BOOTSTRAP_PRE_MIGRATE,
};