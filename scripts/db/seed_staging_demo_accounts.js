#!/usr/bin/env node
'use strict';

/**
 * Seed (or reset) the five DoctorNect demo / store-reviewer accounts in the STAGING
 * Supabase database ONLY.
 *
 *   9999900001 doctor   9999900002 patient   9999900003 pharmacy
 *   9999900004 lab      9999900005 ambulance
 * (numbers, roles and Firebase UIDs come from scripts/lib/demo_accounts.js)
 *
 * Demo numbers are pre-registered users: reviewers take the normal unified phone step
 * (OTP -> existing account -> signed in), never registration. Every account gets a fully
 * populated, verified profile plus a little module data so each home screen works.
 * Only fictitious names, addresses and identifiers; e-mails use the reserved .invalid TLD.
 *
 *   node scripts/db/seed_staging_demo_accounts.js                    # dry run: prints the plan
 *   DEMO_SEED_TARGET=staging node scripts/db/seed_staging_demo_accounts.js --execute
 *   DEMO_SEED_TARGET=staging node scripts/db/seed_staging_demo_accounts.js --reset
 *
 * --execute is create-only and idempotent (existing rows are left alone).
 * --reset deletes ONLY the demo accounts' rows (demo UIDs, demo profile ids, rows that use a
 * demo number, demo_* sample rows) and seeds them again: use it to restore a clean state.
 *
 * Connection: STAGING_SUPABASE_DB_URL (or --db-url=...), read from the environment or the
 * repo-root .env; it is never printed.
 *
 * Hard refusals (no flag overrides them): APP_ENV=production, any *.rds.amazonaws.com host,
 * the PROD_RDS_HOST / PROD_RDS_CONNECT_HOST / PROD_GATEWAY_URL hosts, a URL equal to
 * DATABASE_URL / PROD_RDS_DATABASE_URL, and any host that is not a Supabase host (loopback is
 * allowed only with --allow-local, for scratch databases).
 */

const crypto = require('crypto');
const { URL } = require('url');
const { DEMO_ACCOUNTS } = require('../lib/demo_accounts');

const EMAIL_DOMAIN = 'demo.doctornect.invalid';
const IDS = {
  doctor: DEMO_ACCOUNTS.find((a) => a.role === 'doctor').profileId,
  patient: DEMO_ACCOUNTS.find((a) => a.role === 'patient').profileId,
};

function hostOf(value) {
  const s = String(value || '').trim();
  if (!s) return '';
  try {
    return new URL(/^[a-z]+:\/\//i.test(s) ? s.replace(/^postgres:\/\//i, 'postgresql://') : `x://${s}`).hostname.toLowerCase();
  } catch (_) {
    return s.toLowerCase();
  }
}

/** Throws unless dbUrl is unmistakably the staging Supabase database. Pure; unit tested. */
function assertStagingOnlyTarget(dbUrl, env = process.env, { allowLocal = false } = {}) {
  const refuse = (why) => {
    const err = new Error(`[seed_staging_demo_accounts] REFUSED: ${why}`);
    err.code = 'DEMO_SEED_REFUSED';
    throw err;
  };
  if (!dbUrl) refuse('no database URL (set STAGING_SUPABASE_DB_URL).');
  if (String(env.APP_ENV || '').trim().toLowerCase() === 'production') refuse('APP_ENV=production.');
  const host = hostOf(dbUrl);
  if (!host) refuse('cannot parse database host.');
  if (/\.rds\.amazonaws\.com$/.test(host) || host.includes('.rds.')) refuse('target is an AWS RDS host.');
  for (const key of ['PROD_RDS_HOST', 'PROD_RDS_CONNECT_HOST', 'PROD_GATEWAY_URL']) {
    if (env[key] && hostOf(env[key]) === host) refuse(`target host equals ${key}.`);
  }
  for (const key of ['DATABASE_URL', 'PROD_RDS_DATABASE_URL']) {
    if (env[key] && String(env[key]).trim() === String(dbUrl).trim()) refuse(`target equals ${key} (production database).`);
  }
  const isLoopback = ['127.0.0.1', 'localhost', '::1'].includes(host);
  const isSupabase = /(^|\.)supabase\.(co|com)$/.test(host) || /\.pooler\.supabase\.com$/.test(host);
  if (isLoopback && !allowLocal) refuse('loopback target requires --allow-local (scratch testing only).');
  if (!isLoopback && !isSupabase) refuse(`host ${host} is not a Supabase staging host.`);
  return host;
}

const now = () => new Date().toISOString();
const inDays = (d, hour = 10) => {
  const t = new Date();
  t.setUTCDate(t.getUTCDate() + d);
  t.setUTCHours(hour - 5, 30, 0, 0); // hour:00 IST
  return t.toISOString();
};

/** An unusable random PIN hash in the backend's pbkdf2 format (ambulance login uses OTP). */
function unusablePinHash() {
  const salt = crypto.randomBytes(16);
  const pin = crypto.randomBytes(24).toString('hex');
  const hash = crypto.pbkdf2Sync(pin, salt, 120000, 32, 'sha256');
  return `pbkdf2$sha256$120000$${salt.toString('hex')}$${hash.toString('hex')}`;
}

/**
 * Ordered list of rows to create: { table, pk: [...], row }.
 * Pure (no DB access) so it can be tested and printed in a dry run.
 */
function buildSeedRows() {
  const rows = [];
  const add = (table, pk, row) => rows.push({ table, pk, row });
  const ts = now();
  const common = { created_at: ts, updated_at: ts };

  for (const a of DEMO_ACCOUNTS) {
    const names = {
      doctor: 'Dr. Asha Demo',
      patient: 'Ravi Demo',
      medicalStore: 'DoctorNect Demo Pharmacy',
      lab: 'DoctorNect Demo Diagnostics',
      ambulance: 'DoctorNect Demo Ambulance',
    };
    add('users', ['id'], {
      id: a.uid,
      firebase_uid: a.uid,
      role: a.role,
      profile_id: a.profileId,
      display_name: names[a.role],
      email: `${a.uid}@${EMAIL_DOMAIN}`,
      mobile: `+91${a.digits}`,
      profile_completed: true,
      verified: true,
      verified_at: ts,
      deactivated: false,
      status: 'active',
      is_system_admin: false,
      ...common,
    });
  }

  const acct = (role) => DEMO_ACCOUNTS.find((a) => a.role === role);
  const address = { city: 'Pune', state: 'Maharashtra', country: 'India', pincode: '411001' };

  const d = acct('doctor');
  add('doctors', ['doctor_id'], {
    doctor_id: d.profileId, owner_uid: d.uid, name: 'Dr. Asha Demo',
    email: `${d.uid}@${EMAIL_DOMAIN}`, mobile: `+91${d.digits}`,
    specialization: 'General Physician', qualification: 'MBBS, MD (Demo)', experience_years: 8,
    consultation_fee: 300, clinic_name: 'DoctorNect Demo Clinic', area: 'Demo Nagar',
    address_line1: '1 Demo Street', state_council: 'Demo Medical Council', council_number: 'DEMO-0001',
    about: 'Fictitious demo doctor for app review. Not a real person.', languages: ['English', 'Hindi'],
    rating: 4.6, review_count: 0, profile_completed: true, verified: true, verified_at: ts,
    deactivated: false, ...address, ...common,
  });
  add('doctor_availability', ['doctor_id'], {
    doctor_id: d.profileId, working_days: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    morning_start: '09:00', morning_end: '13:00', evening_enabled: true, evening_start: '17:00',
    evening_end: '20:00', slot_duration_mins: 15, max_patients_per_day: 30,
    break_enabled: false, updated_at: ts,
  });

  const p = acct('patient');
  add('patients', ['patient_id'], {
    patient_id: p.profileId, owner_uid: p.uid, name: 'Ravi Demo', email: `${p.uid}@${EMAIL_DOMAIN}`,
    mobile: `+91${p.digits}`, age: 34, gender: 'Male', blood_group: 'O+', height: '172', weight: '70',
    address: '2 Demo Street, Pune 411001', share_records_with_doctors: true,
    primary_doctor_id: d.profileId, care_team_doctor_ids: [d.profileId],
    profile_completed: true, verified: true, ...common,
  });
  add('patient_doctor_links', ['patient_id', 'doctor_id'], {
    patient_id: p.profileId, doctor_id: d.profileId, source: 'manual', created_at: ts,
  });
  const records = [
    ['demo_hr_001', 'Annual health check (sample)', 'labReport', 'labGenerated', -40],
    ['demo_hr_002', 'Fever prescription (sample)', 'prescription', 'doctorPrescribed', -12],
    ['demo_hr_003', 'Vaccination certificate (sample)', 'vaccination', 'selfUploaded', -90],
  ];
  for (const [id, title, type, source, day] of records) {
    add('health_records', ['record_id'], {
      record_id: id, patient_id: p.profileId, title, type, date: inDays(day), source,
      file_name: `${id}.pdf`, doctor_name: 'Dr. Asha Demo', is_image: false,
      notes: 'Sample record for the demo account. No real patient data.',
      shared_with_doctors: true, file_storage: 'none', ...common,
    });
  }
  add('appointments', ['appointment_id'], {
    appointment_id: 'demo_appt_001', doctor_id: d.profileId, patient_id: p.profileId,
    doctor_name: 'Dr. Asha Demo', specialization: 'General Physician', patient_name: 'Ravi Demo',
    patient_age: 34, patient_gender: 'Male', date_time: inDays(2), slot_label: '10:00 AM',
    token_number: 1, visit_type: 'newVisit', patient_status: 'confirmed', doctor_status: 'confirmed',
    clinic_name: 'DoctorNect Demo Clinic', clinic_address: '1 Demo Street, Pune', source: 'app',
    booked_by_uid: p.uid, ...common,
  });
  add('appointments', ['appointment_id'], {
    appointment_id: 'demo_appt_002', doctor_id: d.profileId, patient_id: p.profileId,
    doctor_name: 'Dr. Asha Demo', specialization: 'General Physician', patient_name: 'Ravi Demo',
    patient_age: 34, patient_gender: 'Male', date_time: inDays(-12), slot_label: '10:00 AM',
    token_number: 1, visit_type: 'newVisit', patient_status: 'completed', doctor_status: 'completed',
    clinic_name: 'DoctorNect Demo Clinic', clinic_address: '1 Demo Street, Pune', source: 'app',
    diagnosis: 'Viral fever (sample)', booked_by_uid: p.uid, ...common,
  });

  const m = acct('medicalStore');
  add('medical_stores', ['store_id'], {
    store_id: m.profileId, owner_uid: m.uid, store_name: 'DoctorNect Demo Pharmacy',
    owner_name: 'Meera Demo', drug_license_number: 'DEMO-DL-0003', phone: `+91${m.digits}`,
    email: `${m.uid}@${EMAIL_DOMAIN}`, address_line1: '3 Demo Street', profile_completed: true,
    verified: true, verified_at: ts, deactivated: false, ...address, ...common,
  });

  const l = acct('lab');
  add('labs', ['lab_id'], {
    lab_id: l.profileId, owner_uid: l.uid, lab_name: 'DoctorNect Demo Diagnostics',
    license_number: 'DEMO-LAB-0004', phone: `+91${l.digits}`, email: `${l.uid}@${EMAIL_DOMAIN}`,
    rating: 4.5, area: 'Demo Nagar', address_line1: '4 Demo Street', profile_completed: true,
    verified: true, verified_at: ts, deactivated: false, ...address, ...common,
  });
  for (const [id, name, sample, hours, category] of [
    ['demo_test_cbc', 'Complete Blood Count (demo)', 'blood', 12, 'Haematology'],
    ['demo_test_lft', 'Liver Function Test (demo)', 'blood', 24, 'Biochemistry'],
    ['demo_test_urine', 'Urine Routine (demo)', 'urine', 8, 'Pathology'],
  ]) {
    add('lab_catalog_tests', ['test_id'], {
      test_id: id, name, parameters: ['Sample parameter'], fasting_required: false,
      sample_type: sample, report_hours: hours, popular: true, category,
    });
  }

  const am = acct('ambulance');
  add('ambulances', ['ambulance_id'], {
    ambulance_id: am.profileId, auth_uid: am.uid, service_name: 'DoctorNect Demo Ambulance',
    owner_name: 'Kiran Demo', driver_name: 'Kiran Demo', phone: `+91${am.digits}`,
    vehicle_number: 'MH12DM0005', ambulance_type: 'bls', username: 'demo_ambulance',
    city: 'Pune', base_address: '5 Demo Street, Pune', has_oxygen: true, has_ventilator: false,
    has_stretcher: true, is_24x7: true, rate_per_km: 20, total_rating: 0, rating_count: 0,
    is_available: true, profile_completed: true, verified: true, address_line1: '5 Demo Street',
    state: 'Maharashtra', country: 'India', pincode: '411001', service_areas: ['Pune'], ...common,
  });
  add('ambulance_private_settings', ['ambulance_id'], {
    ambulance_id: am.profileId, pin_hash: unusablePinHash(), updated_at: ts,
  });
  return rows;
}

/** Deletes demo-owned rows only, children first. */
const RESET_SQL = [
  ['ambulance_private_settings', 'ambulance_id = ANY($1)'],
  ['ambulance_broadcasts', 'patient_id = ANY($1) OR accepted_driver_id = ANY($1)'],
  ['ambulances', 'ambulance_id = ANY($1) OR auth_uid = ANY($2)'],
  ['appointments', "appointment_id LIKE 'demo\\_appt\\_%' OR doctor_id = ANY($1) OR patient_id = ANY($1)"],
  ['health_records', 'patient_id = ANY($1)'],
  ['prescriptions', 'patient_id = ANY($1) OR doctor_id = ANY($1)'],
  ['lab_bookings', 'patient_id = ANY($1) OR lab_id = ANY($1)'],
  ['lab_orders', 'patient_id = ANY($1) OR lab_id = ANY($1) OR doctor_id = ANY($1)'],
  ['pharmacy_deliveries', 'patient_id = ANY($1) OR doctor_id = ANY($1) OR store_id = ANY($1)'],
  ['patient_doctor_links', 'patient_id = ANY($1) OR doctor_id = ANY($1)'],
  ['doctor_availability', 'doctor_id = ANY($1)'],
  ['lab_catalog_tests', "test_id LIKE 'demo\\_test\\_%'"],
  ['patients', 'patient_id = ANY($1) OR owner_uid = ANY($2)'],
  ['doctors', 'doctor_id = ANY($1) OR owner_uid = ANY($2)'],
  ['medical_stores', 'store_id = ANY($1) OR owner_uid = ANY($2)'],
  ['labs', 'lab_id = ANY($1) OR owner_uid = ANY($2)'],
  ['users', 'id = ANY($2) OR mobile = ANY($3)'],
];

function mobileVariants() {
  return DEMO_ACCOUNTS.flatMap((a) => [a.digits, `+91${a.digits}`, `91${a.digits}`, `0${a.digits}`]);
}

async function tableExists(client, table) {
  const { rows } = await client.query('SELECT to_regclass($1) AS t', [`public.${table}`]);
  return rows[0].t !== null;
}

async function resetDemoData(client) {
  // Profile ids owned by any user row that is a demo UID or uses a demo number.
  const { rows } = await client.query(
    'SELECT profile_id FROM public.users WHERE id = ANY($1) OR mobile = ANY($2)',
    [DEMO_ACCOUNTS.map((a) => a.uid), mobileVariants()],
  );
  const profileIds = [...new Set([...DEMO_ACCOUNTS.map((a) => a.profileId), ...rows.map((r) => r.profile_id).filter(Boolean)])];
  const uids = DEMO_ACCOUNTS.map((a) => a.uid);
  const counts = {};
  for (const [table, where] of RESET_SQL) {
    if (!(await tableExists(client, table))) continue;
    const all = [profileIds, uids, mobileVariants()];
    // Pass only the arrays this statement uses, renumbered $1..$n (Postgres cannot type unused params).
    const used = [1, 2, 3].filter((n) => where.includes(`$${n}`));
    const sqlWhere = used.reduce((w, n, i) => w.split(`$${n}`).join(`$__${i + 1}`), where).replace(/\$__/g, '$');
    const res = await client.query(`DELETE FROM public.${table} WHERE ${sqlWhere}`, used.map((n) => all[n - 1]));
    counts[table] = res.rowCount;
  }
  return counts;
}

async function insertIfMissing(client, { table, pk, row }) {
  const keys = Object.keys(row);
  const sql = `INSERT INTO public.${table} (${keys.map((k) => `"${k}"`).join(', ')})
               VALUES (${keys.map((_, i) => `$${i + 1}`).join(', ')})
               ON CONFLICT (${pk.map((k) => `"${k}"`).join(', ')}) DO NOTHING`;
  const res = await client.query(sql, keys.map((k) => row[k]));
  return res.rowCount;
}

async function seedDemoData(client) {
  // Refuse to touch a demo number that already belongs to a non-demo user.
  const { rows } = await client.query('SELECT id FROM public.users WHERE mobile = ANY($1)', [mobileVariants()]);
  const uids = new Set(DEMO_ACCOUNTS.map((a) => a.uid));
  const foreign = rows.filter((r) => !uids.has(r.id));
  if (foreign.length) {
    throw new Error(`${foreign.length} non-demo user row(s) use a demo number; run --reset to clean them up.`);
  }
  // A demo UID that holds another demo number (old mapping) also needs --reset.
  const { rows: mismatched } = await client.query(
    'SELECT id, mobile, role FROM public.users WHERE id = ANY($1)', [[...uids]],
  );
  for (const r of mismatched) {
    const a = DEMO_ACCOUNTS.find((x) => x.uid === r.id);
    if (String(r.mobile || '').replace(/\D/g, '').slice(-10) !== a.digits || r.role !== a.role) {
      throw new Error(`demo user ${r.id} has an outdated number/role mapping; run --reset.`);
    }
  }
  const created = {};
  for (const item of buildSeedRows()) {
    created[item.table] = (created[item.table] || 0) + (await insertIfMissing(client, item));
  }
  return created;
}

async function main() {
  const args = process.argv.slice(2);
  const reset = args.includes('--reset');
  const execute = args.includes('--execute') || reset;
  const allowLocal = args.includes('--allow-local');
  const urlArg = (args.find((a) => a.startsWith('--db-url=')) || '').slice('--db-url='.length);
  try { require('../lib/bootstrap_root_env').loadRootEnv(); } catch (_) {}
  const dbUrl = urlArg || process.env.STAGING_SUPABASE_DB_URL || '';

  const host = assertStagingOnlyTarget(dbUrl, process.env, { allowLocal });
  console.log(`Target host: ${host}`);
  for (const a of DEMO_ACCOUNTS) {
    console.log(`  ${a.role.padEnd(13)} +91${a.digits.slice(0, 3)}*****${a.digits.slice(-2)}  uid=${a.uid}  profile=${a.profileId}`);
  }
  const plan = buildSeedRows();
  const byTable = plan.reduce((m, r) => ({ ...m, [r.table]: (m[r.table] || 0) + 1 }), {});
  console.log('Rows:', JSON.stringify(byTable));
  if (!execute) {
    console.log('\nDry run. Add --execute (create-only) or --reset (restore clean demo data) with DEMO_SEED_TARGET=staging.');
    return;
  }
  if (String(process.env.DEMO_SEED_TARGET || '') !== 'staging') {
    throw new Error('[seed_staging_demo_accounts] REFUSED: set DEMO_SEED_TARGET=staging to write.');
  }

  const { Client } = require('pg');
  const local = allowLocal && ['127.0.0.1', 'localhost', '::1'].includes(host);
  const client = new Client({ connectionString: dbUrl, ssl: local ? false : { rejectUnauthorized: true } });
  await client.connect();
  try {
    await client.query('BEGIN');
    if (reset) console.log('Deleted:', JSON.stringify(await resetDemoData(client)));
    console.log('Created:', JSON.stringify(await seedDemoData(client)));
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}

module.exports = { assertStagingOnlyTarget, buildSeedRows, resetDemoData, seedDemoData, DEMO_ACCOUNTS };
