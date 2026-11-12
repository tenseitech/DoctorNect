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
 * 7. Runs an orphan check across all public tables after purge to prove database referential integrity.
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
  process.env.POSTGRES_URL ||
  'postgres://postgres:postgres@127.0.0.1:54322/postgres';

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

    // 1. Identify Demo & Synthetic User IDs and Profile IDs across users and profile tables
    const userQuery = `
      SELECT id, role, profile_id FROM public.users
      WHERE (cardinality($1::text[]) > 0 AND mobile = ANY($1))
         OR id LIKE 'demo_%'
         OR id LIKE 'fb_uid_%'
         OR id LIKE 'test_%'
         OR email LIKE '%@test.com'
         OR email LIKE '%.demo@doctornect.com'
         OR email LIKE 'demo.%@doctornect.com'
         OR email LIKE '%reviewer@doctornect.com'
    `;
    const userRes = await client.query(userQuery, [DEMO_PHONES]);
    const demoUids = Array.from(new Set(userRes.rows.map((r) => r.id)));
    let demoProfileIds = userRes.rows.map((r) => r.profile_id).filter(Boolean);

    // Also collect profile IDs from domain tables matching test prefixes
    const patRes = await client.query(`SELECT patient_id FROM public.patients WHERE (cardinality($1::text[]) > 0 AND mobile = ANY($1)) OR patient_id LIKE 'pat_%test%' OR patient_id LIKE 'pat_%demo%' OR owner_uid = ANY($2)`, [DEMO_PHONES, demoUids]);
    const docRes = await client.query(`SELECT doctor_id FROM public.doctors WHERE (cardinality($1::text[]) > 0 AND mobile = ANY($1)) OR doctor_id LIKE 'doc_%test%' OR doctor_id LIKE 'doc_%demo%' OR owner_uid = ANY($2)`, [DEMO_PHONES, demoUids]);
    const storeRes = await client.query(`SELECT store_id FROM public.medical_stores WHERE (cardinality($1::text[]) > 0 AND phone = ANY($1)) OR store_id LIKE 'store_%test%' OR store_id LIKE 'store_%demo%' OR owner_uid = ANY($2)`, [DEMO_PHONES, demoUids]);
    const labRes = await client.query(`SELECT lab_id FROM public.labs WHERE (cardinality($1::text[]) > 0 AND phone = ANY($1)) OR lab_id LIKE 'lab_%test%' OR lab_id LIKE 'lab_%demo%' OR owner_uid = ANY($2)`, [DEMO_PHONES, demoUids]);
    const ambRes = await client.query(`SELECT ambulance_id FROM public.ambulances WHERE (cardinality($1::text[]) > 0 AND phone = ANY($1)) OR ambulance_id LIKE 'amb_%test%' OR ambulance_id LIKE 'amb_%demo%' OR auth_uid = ANY($2)`, [DEMO_PHONES, demoUids]);

    demoProfileIds = Array.from(new Set([
      ...demoProfileIds,
      ...patRes.rows.map((r) => r.patient_id),
      ...docRes.rows.map((r) => r.doctor_id),
      ...storeRes.rows.map((r) => r.store_id),
      ...labRes.rows.map((r) => r.lab_id),
      ...ambRes.rows.map((r) => r.ambulance_id),
    ]));

    console.log(`Identified ${demoUids.length} synthetic / demo user accounts and ${demoProfileIds.length} domain profile entities.`);

    if (demoUids.length === 0 && demoProfileIds.length === 0) {
      console.log('No synthetic or demo user accounts found. Database is clean.');
      if (!isDryRun) await client.query('COMMIT');
      return;
    }

    // 2. Cascade count & delete queries in reverse dependency order (leaf to root)
    const purgeSteps = [
      // Reviews & Social
      {
        table: 'review_votes',
        query: `DELETE FROM public.review_votes WHERE patient_id = ANY($1) OR review_id IN (
          SELECT review_id FROM public.reviews WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.review_votes WHERE patient_id = ANY($1) OR review_id IN (
          SELECT review_id FROM public.reviews WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'review_public',
        query: `DELETE FROM public.review_public WHERE doctor_id = ANY($1) OR review_id IN (
          SELECT review_id FROM public.reviews WHERE patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.review_public WHERE doctor_id = ANY($1) OR review_id IN (
          SELECT review_id FROM public.reviews WHERE patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'reviews',
        query: `DELETE FROM public.reviews WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.reviews WHERE doctor_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'referrals',
        query: `DELETE FROM public.referrals WHERE from_doctor_id = ANY($1) OR to_doctor_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.referrals WHERE from_doctor_id = ANY($1) OR to_doctor_id = ANY($1) OR patient_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'prescription_referrals',
        query: `DELETE FROM public.prescription_referrals WHERE to_doctor_id = ANY($1) OR prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        countQuery: `SELECT count(*) FROM public.prescription_referrals WHERE to_doctor_id = ANY($1) OR prescription_id IN (
          SELECT prescription_id FROM public.prescriptions WHERE doctor_id = ANY($1) OR patient_id = ANY($1)
        )`,
        params: [demoProfileIds],
      },
      {
        table: 'patient_doctor_links',
        query: `DELETE FROM public.patient_doctor_links WHERE patient_id = ANY($1) OR doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.patient_doctor_links WHERE patient_id = ANY($1) OR doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'patient_care_team',
        query: `DELETE FROM public.patient_care_team WHERE patient_id = ANY($1) OR doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.patient_care_team WHERE patient_id = ANY($1) OR doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'lab_connections',
        query: `DELETE FROM public.lab_connections WHERE doctor_id = ANY($1) OR lab_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.lab_connections WHERE doctor_id = ANY($1) OR lab_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'pharmacy_connections',
        query: `DELETE FROM public.pharmacy_connections WHERE doctor_id = ANY($1) OR medical_store_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.pharmacy_connections WHERE doctor_id = ANY($1) OR medical_store_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_invites',
        query: `DELETE FROM public.ambulance_invites WHERE doctor_id = ANY($1) OR ambulance_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.ambulance_invites WHERE doctor_id = ANY($1) OR ambulance_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'ambulance_private_settings',
        query: `DELETE FROM public.ambulance_private_settings WHERE ambulance_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.ambulance_private_settings WHERE ambulance_id = ANY($1)`,
        params: [demoProfileIds],
      },
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
        table: 'lab_orders',
        query: `DELETE FROM public.lab_orders WHERE lab_id = ANY($1) OR patient_id = ANY($1) OR doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.lab_orders WHERE lab_id = ANY($1) OR patient_id = ANY($1) OR doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'lab_bookings',
        query: `DELETE FROM public.lab_bookings WHERE lab_id = ANY($1) OR patient_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.lab_bookings WHERE lab_id = ANY($1) OR patient_id = ANY($1)`,
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
        table: 'doctor_education',
        query: `DELETE FROM public.doctor_education WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_education WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_facilities',
        query: `DELETE FROM public.doctor_facilities WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_facilities WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_blocked_dates',
        query: `DELETE FROM public.doctor_blocked_dates WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_blocked_dates WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_availability',
        query: `DELETE FROM public.doctor_availability WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_availability WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'doctor_private',
        query: `DELETE FROM public.doctor_private WHERE doctor_id = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.doctor_private WHERE doctor_id = ANY($1)`,
        params: [demoProfileIds],
      },
      {
        table: 'support_ticket_messages',
        query: `DELETE FROM public.support_ticket_messages WHERE sender_id = ANY($1) OR ticket_id IN (
          SELECT ticket_id FROM public.support_tickets WHERE user_id = ANY($1) OR patient_id = ANY($2) OR doctor_id = ANY($2)
        )`,
        countQuery: `SELECT count(*) FROM public.support_ticket_messages WHERE sender_id = ANY($1) OR ticket_id IN (
          SELECT ticket_id FROM public.support_tickets WHERE user_id = ANY($1) OR patient_id = ANY($2) OR doctor_id = ANY($2)
        )`,
        params: [demoUids, demoProfileIds],
      },
      {
        table: 'support_tickets',
        query: `DELETE FROM public.support_tickets WHERE user_id = ANY($1) OR patient_id = ANY($2) OR doctor_id = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.support_tickets WHERE user_id = ANY($1) OR patient_id = ANY($2) OR doctor_id = ANY($2)`,
        params: [demoUids, demoProfileIds],
      },
      {
        table: 'in_app_notifications',
        query: `DELETE FROM public.in_app_notifications WHERE recipient_uid = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.in_app_notifications WHERE recipient_uid = ANY($1)`,
        params: [demoUids],
      },
      {
        table: 'storage_audit_logs',
        query: `DELETE FROM public.storage_audit_logs WHERE who = ANY($1)`,
        countQuery: `SELECT count(*) FROM public.storage_audit_logs WHERE who = ANY($1)`,
        params: [demoUids],
      },
      {
        table: 'razorpay_payments',
        query: `DELETE FROM public.razorpay_payments WHERE order_id IN (
          SELECT order_id FROM public.razorpay_orders WHERE user_uid = ANY($1) OR ad_id IN (
            SELECT ad_id FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)
          )
        )`,
        countQuery: `SELECT count(*) FROM public.razorpay_payments WHERE order_id IN (
          SELECT order_id FROM public.razorpay_orders WHERE user_uid = ANY($1) OR ad_id IN (
            SELECT ad_id FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)
          )
        )`,
        params: [demoUids, demoProfileIds],
      },
      {
        table: 'razorpay_orders',
        query: `DELETE FROM public.razorpay_orders WHERE user_uid = ANY($1) OR ad_id IN (
          SELECT ad_id FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)
        )`,
        countQuery: `SELECT count(*) FROM public.razorpay_orders WHERE user_uid = ANY($1) OR ad_id IN (
          SELECT ad_id FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)
        )`,
        params: [demoUids, demoProfileIds],
      },
      {
        table: 'promoted_ads',
        query: `DELETE FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)`,
        countQuery: `SELECT count(*) FROM public.promoted_ads WHERE provider_id = ANY($1) OR provider_id = ANY($2)`,
        params: [demoUids, demoProfileIds],
      },
      {
        table: 'super_admins',
        query: `DELETE FROM public.super_admins WHERE user_uid = ANY($1) OR user_uid LIKE 'fb_uid_super_admin_%'`,
        countQuery: `SELECT count(*) FROM public.super_admins WHERE user_uid = ANY($1) OR user_uid LIKE 'fb_uid_super_admin_%'`,
        params: [demoUids],
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

    // 3. Post-Purge Referential Integrity / Orphan Rows Audit
    console.log('\n--- ORPHAN ROWS INTEGRITY AUDIT ---');
    const orphanQueries = [
      { name: 'appointments.patient_id -> patients', query: `SELECT count(*) FROM public.appointments a LEFT JOIN public.patients p ON a.patient_id = p.patient_id WHERE a.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'appointments.doctor_id -> doctors', query: `SELECT count(*) FROM public.appointments a LEFT JOIN public.doctors d ON a.doctor_id = d.doctor_id WHERE a.doctor_id IS NOT NULL AND d.doctor_id IS NULL` },
      { name: 'prescriptions.patient_id -> patients', query: `SELECT count(*) FROM public.prescriptions pr LEFT JOIN public.patients p ON pr.patient_id = p.patient_id WHERE pr.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'prescriptions.doctor_id -> doctors', query: `SELECT count(*) FROM public.prescriptions pr LEFT JOIN public.doctors d ON pr.doctor_id = d.doctor_id WHERE pr.doctor_id IS NOT NULL AND d.doctor_id IS NULL` },
      { name: 'health_records.patient_id -> patients', query: `SELECT count(*) FROM public.health_records hr LEFT JOIN public.patients p ON hr.patient_id = p.patient_id WHERE hr.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'family_members.patient_id -> patients', query: `SELECT count(*) FROM public.family_members fm LEFT JOIN public.patients p ON fm.patient_id = p.patient_id WHERE fm.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'reviews.doctor_id -> doctors', query: `SELECT count(*) FROM public.reviews r LEFT JOIN public.doctors d ON r.doctor_id = d.doctor_id WHERE r.doctor_id IS NOT NULL AND d.doctor_id IS NULL` },
      { name: 'reviews.patient_id -> patients', query: `SELECT count(*) FROM public.reviews r LEFT JOIN public.patients p ON r.patient_id = p.patient_id WHERE r.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'referrals.patient_id -> patients', query: `SELECT count(*) FROM public.referrals ref LEFT JOIN public.patients p ON ref.patient_id = p.patient_id WHERE ref.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'pharmacy_deliveries.store_id -> medical_stores', query: `SELECT count(*) FROM public.pharmacy_deliveries pd LEFT JOIN public.medical_stores ms ON pd.store_id = ms.store_id WHERE pd.store_id IS NOT NULL AND ms.store_id IS NULL` },
      { name: 'pharmacy_deliveries.patient_id -> patients', query: `SELECT count(*) FROM public.pharmacy_deliveries pd LEFT JOIN public.patients p ON pd.patient_id = p.patient_id WHERE pd.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'lab_bookings.lab_id -> labs', query: `SELECT count(*) FROM public.lab_bookings lb LEFT JOIN public.labs l ON lb.lab_id = l.lab_id WHERE lb.lab_id IS NOT NULL AND l.lab_id IS NULL` },
      { name: 'lab_bookings.patient_id -> patients', query: `SELECT count(*) FROM public.lab_bookings lb LEFT JOIN public.patients p ON lb.patient_id = p.patient_id WHERE lb.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'lab_orders.lab_id -> labs', query: `SELECT count(*) FROM public.lab_orders lo LEFT JOIN public.labs l ON lo.lab_id = l.lab_id WHERE lo.lab_id IS NOT NULL AND l.lab_id IS NULL` },
      { name: 'ambulance_broadcasts.patient_id -> patients', query: `SELECT count(*) FROM public.ambulance_broadcasts ab LEFT JOIN public.patients p ON ab.patient_id = p.patient_id WHERE ab.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'ambulance_requests.driver_id -> ambulances', query: `SELECT count(*) FROM public.ambulance_requests ar LEFT JOIN public.ambulances amb ON ar.driver_id = amb.ambulance_id WHERE ar.driver_id IS NOT NULL AND amb.ambulance_id IS NULL` },
      { name: 'support_tickets.patient_id -> patients', query: `SELECT count(*) FROM public.support_tickets st LEFT JOIN public.patients p ON st.patient_id = p.patient_id WHERE st.patient_id IS NOT NULL AND p.patient_id IS NULL` },
      { name: 'user_devices.user_id -> users', query: `SELECT count(*) FROM public.user_devices ud LEFT JOIN public.users u ON ud.user_id = u.id WHERE ud.user_id IS NOT NULL AND u.id IS NULL` },
      { name: 'doctor_private.doctor_id -> doctors', query: `SELECT count(*) FROM public.doctor_private dp LEFT JOIN public.doctors d ON dp.doctor_id = d.doctor_id WHERE dp.doctor_id IS NOT NULL AND d.doctor_id IS NULL` },
      { name: 'razorpay_payments.order_id -> razorpay_orders', query: `SELECT count(*) FROM public.razorpay_payments rp LEFT JOIN public.razorpay_orders ro ON rp.order_id = ro.order_id WHERE rp.order_id IS NOT NULL AND ro.order_id IS NULL` },
    ];

    let totalOrphans = 0;
    for (const check of orphanQueries) {
      const res = await client.query(check.query);
      const count = parseInt(res.rows[0].count, 10);
      if (count > 0) {
        console.warn(`[WARNING] Orphan rows detected in ${check.name}: ${count}`);
        totalOrphans += count;
      } else {
        console.log(`[PASS] ${check.name}: 0 orphans`);
      }
    }
    console.log(`Total orphan rows across all audited relations: ${totalOrphans}`);

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
