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

const DEMO_PHONES = [
  '7666892394', // Doctor
  '7058809803', // Patient
  '9359503874', // Pharmacy / Medical Store
  '9409858233', // Lab
  '9307583929', // Ambulance
  '9999988888', // Super Admin
];

const REQUIRED_CONFIRM_TOKEN = 'doctornect-production';

// Parse command line arguments
const args = process.argv.slice(2);
const hasLiveFlag = args.includes('--live') || args.some(a => a.startsWith('--confirm-prod-purge='));
const confirmArg = args.find(a => a.startsWith('--confirm-prod-purge='));
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
    ssl: connectionString.includes('localhost') ? false : { rejectUnauthorized: false },
  });

  await client.connect();
  console.log('================================================================');
  console.log('DOCTORNECT: PRODUCTION DEMO & TEST DATA PURGE');
  console.log(`MODE: ${isDryRun ? 'DRY-RUN (Audit only — zero mutations)' : '*** LIVE PURGE ***'}`);
  console.log(`TARGET DEMO PHONES: ${DEMO_PHONES.join(', ')}`);
  console.log('================================================================\n');

  try {
    if (!isDryRun) {
      await client.query('BEGIN');
    }

    // 1. Identify Demo & Synthetic User IDs
    const userQuery = `
      SELECT id, role, profile_id FROM public.users
      WHERE mobile = ANY($1)
         OR id LIKE 'demo_%'
         OR id LIKE 'fb_uid_%'
         OR id LIKE 'test_%'
         OR email LIKE '%@test.com'
         OR email LIKE '%.demo@doctornect.com'
         OR email LIKE 'demo.%@doctornect.com'
    `;
    const userRes = await client.query(userQuery, [DEMO_PHONES]);
    const demoUids = userRes.rows.map(r => r.id);
    const demoProfileIds = userRes.rows.map(r => r.profile_id).filter(Boolean);

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
        query: `DELETE FROM public.doctor_private WHERE doctor_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.doctor_private WHERE doctor_id = ANY($1) OR owner_uid = ANY($2)`,
        params: [demoProfileIds, demoUids],
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
        query: `DELETE FROM public.ambulances WHERE ambulance_id = ANY($1) OR owner_uid = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.ambulances WHERE ambulance_id = ANY($1) OR owner_uid = ANY($2)`,
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

    console.log('--- PURGE BREAKDOWN BY TABLE ---');
    for (const step of purgeSteps) {
      const countRes = await client.query(step.countQuery, step.params);
      const rowCount = parseInt(countRes.rows[0].count, 10);
      if (isDryRun) {
        console.log(`[DRY-RUN] ${step.table.padEnd(28)} : ${rowCount} matching rows`);
      } else {
        const delRes = await client.query(step.query, step.params);
        console.log(`[PURGED]  ${step.table.padEnd(28)} : ${delRes.rowCount} rows deleted`);
      }
    }

    if (!isDryRun) {
      await client.query('COMMIT');
      console.log('\n================================================================');
      console.log('PURGE COMMITTED SUCCESSFULLY. Production database cleaned.');
      console.log('================================================================');
    } else {
      console.log('\n================================================================');
      console.log('DRY-RUN COMPLETE. Zero rows were altered.');
      console.log(`To execute live: node backend/scripts/purge_demo_test_data.js --confirm-prod-purge=${REQUIRED_CONFIRM_TOKEN}`);
      console.log('================================================================');
    }
  } catch (err) {
    if (!isDryRun) {
      await client.query('ROLLBACK');
      console.error('\nPURGE FAILED. Transaction rolled back cleanly.');
    }
    console.error('Error details:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

runPurge();
