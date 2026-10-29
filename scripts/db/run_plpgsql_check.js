'use strict';

/**
 * scripts/db/run_plpgsql_check.js
 *
 * Runs plpgsql_check static analysis on the 14 functions and triggers
 * introduced or modified in 20261026000001_rpc_null_safe_authz.sql.
 *
 * DO NOT RUN until the Write Gate is formally opened and plpgsql_check
 * is installed on the target staging/RDS database.
 */

const fs = require('fs');
const path = require('path');
const { getTargetConfig } = require('../lib/env_loader');

const TARGET_FUNCTIONS = [
  'public.reschedule_appointment_atomic(varchar, timestamptz, varchar)',
  'public.cancel_ambulance_broadcast(varchar, text)',
  'public.get_ambulance_trip_location(varchar)',
  'public.update_ambulance_location(varchar, varchar, numeric, numeric, numeric, numeric)',
  'public.complete_ambulance_trip(varchar, integer, text)',
  'public.accept_ambulance_request(varchar, varchar, varchar)',
  'public.update_lab_booking_status(varchar, varchar)',
  'public.update_lab_order_status(varchar, varchar)',
  'public.update_pharmacy_delivery_status(varchar, varchar, text, jsonb)',
  'public.book_appointment_atomic(varchar, varchar, varchar, varchar, varchar, integer, varchar, timestamptz, varchar, varchar, integer, varchar, text, varchar, varchar)',
  'public.create_prescription_atomic(varchar, varchar, varchar, jsonb, jsonb, jsonb, text, text, text, text, text, text, text, text, numeric, numeric, text, numeric, numeric, numeric, text, varchar, text, text, varchar, text)',
  'public.get_ambulance_trip_contact(varchar)',
  'private.trg_lock_ambulance_broadcast_status()',
  'private.trg_users_guard_insert()',
];

async function runPlpgsqlCheck(target = 'staging') {
  const { Client } = require('pg');
  const targetConfig = getTargetConfig(target);

  if (!targetConfig.dbUrl) {
    throw new Error(`[plpgsql_check] No database URL found for target: ${target}`);
  }

  const client = new Client({
    connectionString: targetConfig.dbUrl,
    ssl: { rejectUnauthorized: false },
  });

  await client.connect();
  console.log(`Connected to ${target} database for plpgsql_check analysis.`);

  try {
    await client.query('CREATE EXTENSION IF NOT EXISTS plpgsql_check;');
    console.log('[PASS] Extension plpgsql_check verified/created.');

    let anyErrors = false;
    for (const fnSignature of TARGET_FUNCTIONS) {
      try {
        const res = await client.query('SELECT * FROM plpgsql_check_function_tb($1);', [fnSignature]);
        if (res.rows.length === 0) {
          console.log(`[PASS] ${fnSignature}: 0 warnings/errors`);
        } else {
          console.warn(`[WARN/FAIL] ${fnSignature}:`);
          for (const row of res.rows) {
            console.warn(`  - ${row.message || JSON.stringify(row)}`);
          }
          anyErrors = true;
        }
      } catch (err) {
        console.error(`[ERROR] Failed checking ${fnSignature}: ${err.message}`);
        anyErrors = true;
      }
    }

    if (anyErrors) {
      process.exitCode = 1;
    }
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  const target = process.argv.includes('--target=rds') ? 'rds' : 'staging';
  console.log('NOTE: plpgsql_check run script prepared. Not running against DB.');
}

module.exports = { runPlpgsqlCheck, TARGET_FUNCTIONS };

