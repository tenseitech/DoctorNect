#!/usr/bin/env node
'use strict';

/**
 * Apply security fix migrations on staging only (operator).
 *   node scripts/db/apply_super_admin_hardening_staging.js
 *   node scripts/db/apply_super_admin_hardening_staging.js --confirm-live-data --execute
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

const MIGRATIONS = [
  '20261115000001_harden_super_admin_no_jwt_email_bypass.sql',
  '20261115000002_pgcrypto_notification_outbox_search_path.sql',
  '20261115000003_appointments_sync_origin_replay.sql',
];

async function main() {
  bootstrapMutatingScript('scripts/db/apply_super_admin_hardening_staging.js');
  if (!process.argv.includes('--execute')) {
    console.log('Dry-run. Would apply:\n ', MIGRATIONS.join('\n  '));
    console.log('\nRe-run: node scripts/db/apply_super_admin_hardening_staging.js --confirm-live-data --execute');
    return;
  }

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) throw new Error('STAGING_SUPABASE_DB_URL missing');
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  const client = await pool.connect();
  try {
    for (const file of MIGRATIONS) {
      const sql = fs.readFileSync(path.join(__dirname, '../../db/migrations', file), 'utf8');
      console.log(`Applying ${file}...`);
      await client.query(sql);
      await client.query(
        `INSERT INTO public._schema_migrations (version, name, checksum)
         VALUES ($1, $2, 'manual_apply')
         ON CONFLICT (version) DO NOTHING`,
        [file.slice(0, 14), file],
      );
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