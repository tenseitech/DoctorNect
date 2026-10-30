'use strict';

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

const TARGET_FUNCTION_NAMES = [
  'reschedule_appointment_atomic',
  'cancel_ambulance_broadcast',
  'get_ambulance_trip_location',
  'update_ambulance_location',
  'complete_ambulance_trip',
  'accept_ambulance_request',
  'update_lab_booking_status',
  'update_lab_order_status',
  'update_pharmacy_delivery_status',
  'book_appointment_atomic',
  'create_prescription_atomic',
  'get_ambulance_trip_contact',
  'trg_lock_ambulance_broadcast_status',
  'trg_users_guard_insert',
  'trg_domain_profile_guard_insert',
  'trg_domain_profile_guard_update',
  'trg_ambulance_broadcast_contact_guard',
  'deactivate_provider_profile',
  'reactivate_provider_profile',
  'claim_ambulance_driver',
];

async function runPlpgsqlCheck() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    throw new Error('STAGING_SUPABASE_DB_URL is not set.');
  }

  assertDatabaseGuard({
    targetKind: 'staging',
    operationName: 'Run plpgsql_check',
    allowDestructive: false,
  });

  const client = new Client({ connectionString: dbUrl });
  await client.connect();

  console.log('\n======================================================');
  console.log('plpgsql_check Static Analysis (Target: STAGING)');
  console.log('======================================================\n');

  try {
    // Attempt to create extension if not present
    try {
      await client.query('CREATE EXTENSION IF NOT EXISTS plpgsql_check;');
      console.log('✔ Extension plpgsql_check is installed and available.\n');
    } catch (extErr) {
      console.warn(`[NOTICE] CREATE EXTENSION plpgsql_check: ${extErr.message}`);
    }

    // Verify extension existence
    const extCheck = await client.query("SELECT 1 FROM pg_extension WHERE extname = 'plpgsql_check';");
    if (extCheck.rows.length === 0) {
      console.error('[ERROR] plpgsql_check extension is NOT installed in target database.');
      return;
    }

    let totalChecked = 0;
    let totalWarnings = 0;

    for (const name of TARGET_FUNCTION_NAMES) {
      const procRes = await client.query(`
        SELECT p.oid, p.proname, n.nspname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.proname = $1 AND n.nspname IN ('public', 'private');
      `, [name]);

      if (procRes.rows.length === 0) {
        console.warn(`[NOT FOUND] Function/Trigger: ${name}`);
        continue;
      }

      for (const proc of procRes.rows) {
        totalChecked++;
        const sig = `${proc.nspname}.${proc.proname}(${proc.args})`;
        try {
          let checkRes;
          if (proc.proname === 'trg_lock_ambulance_broadcast_status' || proc.proname === 'trg_ambulance_broadcast_contact_guard') {
            checkRes = await client.query("SELECT * FROM plpgsql_check_function_tb($1::regprocedure, 'public.ambulance_broadcasts'::regclass);", [proc.oid]);
          } else if (proc.proname === 'trg_users_guard_insert') {
            checkRes = await client.query("SELECT * FROM plpgsql_check_function_tb($1::regprocedure, 'public.users'::regclass);", [proc.oid]);
          } else if (proc.proname === 'trg_domain_profile_guard_insert' || proc.proname === 'trg_domain_profile_guard_update') {
            const domainTables = ['public.patients', 'public.doctors', 'public.medical_stores', 'public.labs', 'public.ambulances'];
            let combinedRows = [];
            for (const dt of domainTables) {
              const dtRes = await client.query("SELECT * FROM plpgsql_check_function_tb($1::regprocedure, $2::regclass);", [proc.oid, dt]);
              if (dtRes.rows.length === 0) {
                console.log(`[PASS] ${sig} on ${dt}: 0 warnings/errors`);
              } else {
                console.warn(`[WARN/FAIL] ${sig} on ${dt} (${dtRes.rows.length} issues):`);
                for (const r of dtRes.rows) {
                  console.warn(`  - [${r.sqlstate || 'WARN'}] ${r.message || JSON.stringify(r)}`);
                  totalWarnings++;
                }
                combinedRows.push(...dtRes.rows);
              }
            }
            continue; // Already printed results for each domain table
          } else {
            checkRes = await client.query('SELECT * FROM plpgsql_check_function_tb($1::regprocedure);', [proc.oid]);
          }

          if (checkRes.rows.length === 0) {
            console.log(`[PASS] ${sig}: 0 warnings/errors`);
          } else {
            console.warn(`[WARN/FAIL] ${sig} (${checkRes.rows.length} issues):`);
            for (const r of checkRes.rows) {
              console.warn(`  - [${r.sqlstate || 'WARN'}] ${r.message || JSON.stringify(r)}`);
              totalWarnings++;
            }
          }
        } catch (checkErr) {
          console.error(`[ERROR] plpgsql_check_function_tb on ${sig}: ${checkErr.message}`);
          totalWarnings++;
        }
      }
    }

    console.log(`\n=== plpgsql_check SUMMARY ===`);
    console.log(`Functions checked: ${totalChecked} | Total warnings/errors: ${totalWarnings}`);
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  runPlpgsqlCheck().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { runPlpgsqlCheck, TARGET_FUNCTION_NAMES };
