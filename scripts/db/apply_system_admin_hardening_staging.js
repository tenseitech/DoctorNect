'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

const MIGRATIONS = [
  '20261112000001_protect_system_admin_user.sql',
  '20261112000002_protect_system_admin_delete_and_audit_grants.sql',
  '20261112000003_super_admin_jwt_email_allowlist.sql',
  '20261112000004_admin_audit_logs_rls_fixup.sql',
  '20261112000005_admin_audit_logs_client_insert_revoke.sql',
];

async function main() {
  bootstrapMutatingScript('scripts/db/apply_system_admin_hardening_staging.js');
  if (!process.argv.includes('--execute')) {
    console.log('Dry-run: would apply migrations:', MIGRATIONS.join(', '));
    console.log('Re-run with --confirm-live-data --execute');
    return;
  }

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) throw new Error('STAGING_SUPABASE_DB_URL missing');
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();
  try {
    for (const file of MIGRATIONS) {
      const sqlPath = path.join(__dirname, '..', '..', 'db', 'migrations', file);
      const sql = fs.readFileSync(sqlPath, 'utf8');
      console.log(`Applying ${file}...`);
      await client.query(sql);
      console.log(`✔ ${file}`);
    }
    await client.query("NOTIFY pgrst, 'reload schema';");
    console.log('✔ PostgREST schema reload notified');
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
