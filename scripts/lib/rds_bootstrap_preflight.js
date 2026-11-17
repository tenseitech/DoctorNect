'use strict';

/**
 * Ensure pre-migrate RDS bootstrap (auth.users stub + auth.uid shim) exists before apply migrations.
 */
async function assertRdsPreMigrateBootstrap(client) {
  const res = await client.query(`
    SELECT
      to_regclass('auth.users') IS NOT NULL AS has_auth_users,
      EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'auth' AND p.proname = 'uid'
      ) AS has_auth_uid
  `);
  const row = res.rows[0] || {};
  if (!row.has_auth_users || !row.has_auth_uid) {
    throw new Error(
      '[BOOTSTRAP MISSING] auth.users and auth.uid() must exist before migrate.\n' +
        '  Production: node scripts/db/rds_bootstrap_apply.js --target=production --execute --pre-migrate-only --confirm-live-data --confirm-db=doctornect\n' +
        '  Local rdslike: node scripts/db/rdslike_apply_bootstrap.js\n' +
        '  (Apply after schema reset; bootstrap is not part of migrate.js — see db/rds_bootstrap/03_legacy_compat.sql)',
    );
  }
}

module.exports = { assertRdsPreMigrateBootstrap };