'use strict';

const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

async function main() {
  bootstrapMutatingScript('scripts/db/grant_admin_audit_logs_staging.js');
  if (!process.argv.includes('--execute')) {
    console.log('Dry-run: would GRANT SELECT, INSERT ON public.admin_audit_logs TO authenticated');
    console.log('Re-run with --confirm-live-data --execute');
    return;
  }

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) throw new Error('STAGING_SUPABASE_DB_URL missing');
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();
  try {
    await client.query('GRANT SELECT, INSERT ON public.admin_audit_logs TO authenticated;');
    console.log('✔ GRANT SELECT, INSERT on public.admin_audit_logs applied (staging).');
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
