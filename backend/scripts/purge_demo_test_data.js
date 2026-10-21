/**
 * DoctorNect: Production Database Demo & Test Data Purge Script
 *
 * SAFETY INVARIANTS:
 * 1. Default mode is STRICTLY DRY-RUN. Zero database mutations occur without explicit confirmation.
 * 2. Live purge requires:
 *      --confirm-prod-purge=doctornect-production
 * 3. Never auto-runs; must be manually invoked by an authorized database administrator.
 * 4. All live deletions run inside a single PostgreSQL transaction (atomic commit or full rollback).
 * 5. Respects foreign key topological order to prevent constraint violations.
 * 6. Phone targets are loaded dynamically from environment or gitignored config; zero hardcoded phones.
 *
 * Usage:
 *   # Dry run audit (safe, non-mutating preview):
 *   node backend/scripts/purge_demo_test_data.js --dry-run
 *
 *   # Live purge:
 *   node backend/scripts/purge_demo_test_data.js --confirm-prod-purge=doctornect-production
 */

require('./load_env').loadEnv();
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

function loadDemoPhones() {
  // 1. Check DEMO_PHONES env (comma-separated list)
  if (process.env.DEMO_PHONES) {
    return process.env.DEMO_PHONES.split(',').map((p) => p.trim()).filter(Boolean);
  }

  // 2. Check DEMO_PHONES_CONFIG env (path to json file or inline JSON)
  if (process.env.DEMO_PHONES_CONFIG) {
    try {
      const configPath = path.resolve(process.cwd(), process.env.DEMO_PHONES_CONFIG);
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf8');
        const parsed = JSON.parse(raw);
        const phones = parsed.demo_phones || parsed.phones || parsed;
        if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
      }
      const inline = JSON.parse(process.env.DEMO_PHONES_CONFIG);
      const phones = inline.demo_phones || inline.phones || inline;
      if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
    } catch (e) {
      console.warn(`Warning: failed to parse DEMO_PHONES_CONFIG: ${e.message}`);
    }
  }

  // 3. Check gitignored local config files
  const candidatePaths = [
    path.join(__dirname, 'demo_phones.json'),
    path.join(__dirname, '../demo_phones.json'),
    path.join(process.cwd(), 'demo_phones.json'),
  ];
  for (const candidate of candidatePaths) {
    if (fs.existsSync(candidate)) {
      try {
        const raw = fs.readFileSync(candidate, 'utf8');
        const parsed = JSON.parse(raw);
        const phones = parsed.demo_phones || parsed.phones || parsed;
        if (Array.isArray(phones)) return phones.map((p) => String(p).trim()).filter(Boolean);
      } catch (e) {
        console.warn(`Warning: failed to read ${candidate}: ${e.message}`);
      }
    }
  }

  return [];
}

const DEMO_PHONES = loadDemoPhones();
const REQUIRED_CONFIRM_TOKEN = 'doctornect-production';

// Parse command line arguments
const args = process.argv.slice(2);
const hasLiveFlag = args.includes('--live') || args.some((a) => a.startsWith('--confirm-prod-purge='));
const confirmArg = args.find((a) => a.startsWith('--confirm-prod-purge='));
const confirmToken = confirmArg ? confirmArg.split('=')[1] : null;

const isLive = hasLiveFlag && confirmToken === REQUIRED_CONFIRM_TOKEN;
const isDryRun = !isLive;

if (hasLiveFlag && confirmToken !== REQUIRED_CONFIRM_TOKEN) {
  console.error('================================================================');
  console.error('FATAL: Purge rejected.');
  console.error(`Live purge requires: --confirm-prod-purge=${REQUIRED_CONFIRM_TOKEN}`);
  console.error('Run with --dry-run to audit targets without modifying data.');
  console.error('================================================================');
  process.exit(1);
}

const connectionString =
  process.env.SUPABASE_DB_URL ||
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL;

if (!connectionString) {
  console.error('FATAL: Database connection string missing in environment (SUPABASE_DB_URL / DATABASE_URL).');
  process.exit(1);
}

async function runPurge() {
  const client = new Client({
    connectionString,
    ssl: connectionString.includes('localhost') || connectionString.includes('127.0.0.1') ? false : { rejectUnauthorized: false },
  });

  await client.connect();
  console.log('================================================================');
  console.log('DOCTORNECT: PRODUCTION DEMO & TEST DATA PURGE');
  console.log(`MODE: ${isDryRun ? 'DRY-RUN (Audit only — zero mutations)' : '*** LIVE PURGE ***'}`);
  console.log(`TARGET DEMO PHONES: ${DEMO_PHONES.length > 0 ? DEMO_PHONES.join(', ') : '(None configured — matching synthetic IDs and test email patterns only)'}`);
  console.log('================================================================\n');

  try {
    if (!isDryRun) {
      await client.query('BEGIN');
    }

    // 1. Identify Demo & Synthetic User IDs
    const userQuery = `
      SELECT id, role, profile_id FROM public.users
      WHERE (cardinality($1::text[]) > 0 AND mobile = ANY($1))
         OR id LIKE 'demo_%'
         OR id LIKE 'fb_uid_%'
         OR id LIKE 'test_%'
         OR email LIKE '%@test.com'
         OR email LIKE '%.demo@doctornect.com'
         OR email LIKE 'demo.%@doctornect.com'
    `;
    const userRes = await client.query(userQuery, [DEMO_PHONES]);
    const demoUids = userRes.rows.map((r) => r.id);
    const demoProfileIds = userRes.rows.map((r) => r.profile_id).filter(Boolean);

    console.log(`Identified ${demoUids.length} synthetic / demo user accounts.`);

    if (demoUids.length === 0) {
      console.log('No synthetic or demo user accounts found. Database is clean.');
      if (!isDryRun) await client.query('COMMIT');
      return;
    }

    // 2. Cascade count & delete queries in reverse dependency order
    const purgeSteps = [
      {
        table: 'ambulance_location_updates',
        query: `DELETE FROM public.ambulance_location_updates WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.ambulance_location_updates WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_locations',
        query: `DELETE FROM public.ambulance_locations WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.ambulance_locations WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_trip_contacts',
        query: `DELETE FROM public.ambulance_trip_contacts WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.ambulance_trip_contacts WHERE broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_requests',
        query: `DELETE FROM public.ambulance_requests WHERE driver_id = ANY($1) OR broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.ambulance_requests WHERE driver_id = ANY($1) OR broadcast_id IN (
          SELECT broadcast_id FROM public.ambulance_broadcasts WHERE patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_broadcasts',
        query: `DELETE FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.ambulance_broadcasts WHERE patient_id = ANY($1) OR accepted_driver_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'pharmacy_delivery_medicines',
        query: `DELETE FROM public.pharmacy_delivery_medicines WHERE delivery_id IN (
          SELECT delivery_id FROM public.pharmacy_deliveries WHERE store_id = ANY($1) OR patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.pharmacy_delivery_medicines WHERE delivery_id IN (
          SELECT delivery_id FROM public.pharmacy_deliveries WHERE store_id = ANY($1) OR patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'pharmacy_deliveries',
        query: `DELETE FROM public.pharmacy_deliveries WHERE store_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.pharmacy_deliveries WHERE store_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'lab_bookings',
        query: `DELETE FROM public.lab_bookings WHERE lab_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.lab_bookings WHERE lab_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'lab_orders',
        query: `DELETE FROM public.lab_orders WHERE lab_id = ANY($1) OR patient_id = ANY($1) OR doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.lab_orders WHERE lab_id = ANY($1) OR patient_id = ANY($1) OR doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'prescription_medicines',
        query: `DELETE FROM public.prescription_medicines WHERE prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.prescription_medicines WHERE prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'prescription_investigations',
        query: `DELETE FROM public.prescription_investigations WHERE prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.prescription_investigations WHERE prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'prescriptions',
        query: `DELETE FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'appointments',
        query: `DELETE FROM public.appointments WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.appointments WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'health_records',
        query: `DELETE FROM public.health_records WHERE patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.health_records WHERE patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'family_members',
        query: `DELETE FROM public.family_members WHERE patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.family_members WHERE patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_private',
        query: `DELETE FROM public.doctor_private WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_private WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_availability',
        query: `DELETE FROM public.doctor_availability WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_availability WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_blocked_dates',
        query: `DELETE FROM public.doctor_blocked_dates WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_blocked_dates WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulances',
        query: `DELETE FROM public.ambulances WHERE ambulance_id = ANY($1) OR auth_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.ambulances WHERE ambulance_id = ANY($1) OR auth_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
      },
      {
        table: 'medical_stores',
        query: `DELETE FROM public.medical_stores WHERE store_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.medical_stores WHERE store_id = ANY($1) OR owner_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
      },
      {
        table: 'labs',
        query: `DELETE FROM public.labs WHERE lab_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.labs WHERE lab_id = ANY($1) OR owner_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
      },
      {
        table: 'doctors',
        query: `DELETE FROM public.doctors WHERE doctor_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.doctors WHERE doctor_id = ANY($1) OR owner_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
      },
      {
        table: 'patients',
        query: `DELETE FROM public.patients WHERE patient_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.patients WHERE patient_id = ANY($1) OR owner_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
      },
      {
        table: 'user_devices',
        query: `DELETE FROM public.user_devices WHERE user_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.user_devices WHERE user_id = ANY($1)`,
        params: [demoUids],
      },
      {
        table: 'users',
        query: `DELETE FROM public.users WHERE id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.users WHERE id = ANY($1)`,
        params: [demoUids],
      },
    ];

    console.log('--- PURGE AUDIT BREAKDOWN ---');
    for (const step of purgeSteps) {
      const countRes = await client.query(step.countQuery, step.params);
      const rowCount = parseInt(countRes.rows[0].count, 10);
      console.log(`[${step.table}] Target rows to remove: ${rowCount}`);

      if (!isDryRun && rowCount > 0) {
        const delRes = await client.query(step.query, step.params);
        console.log(`  -> DELETED ${delRes.rowCount} rows from ${step.table}`);
      }
    }

    if (!isDryRun) {
      await client.query('COMMIT');
      console.log('\n================================================================');
      console.log('SUCCESS: Production database purged of all test and demo data.');
      console.log('Transaction committed successfully.');
      console.log('================================================================');
    } else {
      console.log('\n================================================================');
      console.log('DRY-RUN COMPLETE: Zero database mutations occurred.');
      console.log('To execute live purge, run with:');
      console.log(`  node backend/scripts/purge_demo_test_data.js --confirm-prod-purge=${REQUIRED_CONFIRM_TOKEN}`);
      console.log('================================================================');
    }
  } catch (err) {
    if (!isDryRun) {
      try {
        await client.query('ROLLBACK');
        console.error('Transaction rolled back successfully.');
      } catch (rbErr) {
        console.error('Failed to rollback transaction:', rbErr.message);
      }
    }
    console.error('Purge script failed with error:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

runPurge();
