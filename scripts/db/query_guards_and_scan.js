'use strict';

const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

async function main() {
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'Query Guards & Scan' });
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();

  try {
    console.log('\n======================================================');
    console.log('1. DEPLOYED FUNCTION DEFINITION: private.trg_users_guard_insert()');
    console.log('======================================================\n');
    const resUsers = await client.query(`
      SELECT pg_get_functiondef(p.oid) as def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'private' AND p.proname = 'trg_users_guard_insert';
    `);
    if (resUsers.rows.length > 0) {
      console.log(resUsers.rows[0].def);
    } else {
      console.log('NOT FOUND');
    }

    console.log('\n======================================================');
    console.log('2. DEPLOYED FUNCTION DEFINITION: private.trg_domain_profile_guard_insert()');
    console.log('======================================================\n');
    const resDomain = await client.query(`
      SELECT pg_get_functiondef(p.oid) as def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'private' AND p.proname = 'trg_domain_profile_guard_insert';
    `);
    if (resDomain.rows.length > 0) {
      console.log(resDomain.rows[0].def);
    } else {
      console.log('NOT FOUND');
    }

    console.log('\n======================================================');
    console.log('3. SCAN OF ALL SECURITY DEFINER FUNCTIONS ON STAGING');
    console.log('   Checking for: current_user, session_user, current_firebase_uid() IS NULL');
    console.log('======================================================\n');
    const secdefFuncs = await client.query(`
      SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args, pg_get_functiondef(p.oid) as def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE p.prosecdef = true AND n.nspname IN ('public', 'private')
      ORDER BY n.nspname, p.proname;
    `);

    let hitCount = 0;
    for (const row of secdefFuncs.rows) {
      const def = row.def;
      const lines = def.split('\n');
      lines.forEach((line, idx) => {
        const lineNum = idx + 1;
        const hasCurrentUser = /\bcurrent_user\b/i.test(line);
        const hasSessionUser = /\bsession_user\b/i.test(line);
        const hasNullUid = /current_firebase_uid\s*\(\s*\)\s+IS\s+NULL/i.test(line);

        if (hasCurrentUser || hasSessionUser || hasNullUid) {
          hitCount++;
          console.log(`[HIT] ${row.nspname}.${row.proname}(${row.args}):Line ${lineNum}: ${line.trim()}`);
        }
      });
    }

    if (hitCount === 0) {
      console.log('✔ ZERO occurrences of current_user, session_user, or current_firebase_uid() IS NULL found in any SECURITY DEFINER function in public or private schemas.');
    } else {
      console.log(`\nFound ${hitCount} total occurrences.`);
    }

  } finally {
    client.release();
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

