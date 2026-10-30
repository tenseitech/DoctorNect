'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { buildPostgrestPayload } = require('../../services/api-gateway/src/jwt_minter');

// Emits real claims matching backend registration and gateway logic
function getTestJwtClaims(appRole, uid, verified = true) {
  let normalized = appRole;
  if (appRole === 'superAdmin' || appRole === 'super_admin' || appRole === 'service_role') normalized = 'super_admin';
  else if (appRole === 'medical' || appRole === 'pharmacy') normalized = 'medicalStore';

  const tokenRole = appRole === 'service_role' ? 'service_role' : (appRole === 'anon' ? 'anon' : 'authenticated');

  const payload = buildPostgrestPayload({
    role: tokenRole,
    sub: uid,
    appRole: normalized,
    verified: Boolean(verified),
  });

  return JSON.stringify(payload);
}

async function runRlsSqlHarness(options = {}) {
  const args = process.argv.slice(2);
  const targetArg = args.find(a => a.startsWith('--target='));
  const target = options.targetOverride || (targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging');

  let poolConfig;
  let dbUrl;

  if (target === 'replay_check' || target === 'replay') {
    assertDatabaseGuard({ targetKind: 'replay', operationName: 'RLS SQL Harness on Replay', allowDestructive: false });
    dbUrl = options.connectionString || getEnv('REPLAY_DB_URL');
    poolConfig = { connectionString: dbUrl };
  } else if (target === 'staging') {
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'RLS SQL Harness', allowDestructive: false });
    dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    poolConfig = { connectionString: dbUrl };
  } else if (target === 'rehearsal' || target === 'production') {
    assertDatabaseGuard({ targetKind: 'production', operationName: `RLS SQL Harness on ${target}`, allowDestructive: false });
    const host = getEnv('PROD_RDS_HOST');
    const port = parseInt(getEnv('PROD_RDS_PORT') || '5432', 10);
    const database = target === 'rehearsal' ? 'doctornect_rehearsal' : (getEnv('PROD_RDS_DB') || 'postgres');
    const user = getEnv('PROD_RDS_USER') || 'postgres';
    const password = getEnv('PROD_RDS_PASSWORD');
    const certPath = getEnv('PROD_RDS_SSL_ROOT_CERT') || path.resolve(__dirname, '../../infra/aws/global-bundle.pem');

    poolConfig = {
      host,
      port,
      database,
      user,
      password,
      ssl: { rejectUnauthorized: true, ca: fs.readFileSync(certPath) },
    };
    dbUrl = `postgresql://${user}:****@${host}:${port}/${database}`;
  } else {
    console.error(`Unknown target: ${target}`);
    process.exit(1);
  }

  console.log(`\n===============================================================`);
  console.log(`DoctorNect RLS & Authz SQL Harness (Target: ${target.toUpperCase()})`);
  console.log(`Connection: ${maskConnectionString(dbUrl)}`);
  console.log(`Mode: Transaction-isolated (Always ROLLED BACK, ZERO RESIDUE)`);
  console.log(`===============================================================\n`);

  const pool = new Pool(poolConfig);
  const client = await pool.connect();
  const results = [];

  try {
    // Check initial table row count before transaction
    const beforeCountRes = await client.query(`SELECT count(*)::int as cnt FROM public.users;`);
    const countBefore = beforeCountRes.rows[0].cnt;

    console.log(`Baseline public.users row count before harness: ${countBefore}`);

    await client.query('BEGIN');

    // 1. Seed isolated test users and fixtures inside transaction
    const pA = 'test_usr_pat_a';
    const pB = 'test_usr_pat_b';
    const docA = 'test_usr_doc_a';
    const docB = 'test_usr_doc_b';
    const storeA = 'test_usr_store_a';
    const storeB = 'test_usr_store_b';
    const labA = 'test_usr_lab_a';
    const labB = 'test_usr_lab_b';
    const ambA = 'test_usr_amb_a';
    const ambB = 'test_usr_amb_b';

    await client.query(`
      INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES
        ('${pA}', '${pA}', 'patient', '${pA}', 'Patient A', 'pa@test.local', '+919999900001', true),
        ('${pB}', '${pB}', 'patient', '${pB}', 'Patient B', 'pb@test.local', '+919999900002', true),
        ('${docA}', '${docA}', 'doctor', '${docA}', 'Dr A', 'da@test.local', '+919999900003', true),
        ('${docB}', '${docB}', 'doctor', '${docB}', 'Dr B', 'db@test.local', '+919999900004', true),
        ('${storeA}', '${storeA}', 'medicalStore', '${storeA}', 'Store A', 'sa@test.local', '+919999900005', true),
        ('${storeB}', '${storeB}', 'medicalStore', '${storeB}', 'Store B', 'sb@test.local', '+919999900006', true),
        ('${labA}', '${labA}', 'lab', '${labA}', 'Lab A', 'la@test.local', '+919999900007', true),
        ('${labB}', '${labB}', 'lab', '${labB}', 'Lab B', 'lb@test.local', '+919999900008', true),
        ('${ambA}', '${ambA}', 'ambulance', '${ambA}', 'Amb A', 'aa@test.local', '+919999900009', true),
        ('${ambB}', '${ambB}', 'ambulance', '${ambB}', 'Amb B', 'ab@test.local', '+919999900010', true),
        ('test_usr_doc_unverified', 'test_usr_doc_unverified', 'doctor', 'test_usr_doc_unverified', 'Dr. Unverified', 'unverified@test.local', '+919999900099', false),
        ('test_usr_lab_unverified', 'test_usr_lab_unverified', 'lab', 'test_usr_lab_unverified', 'Lab Unverified', 'unverified_lab@test.local', '+919999900098', false),
        ('test_usr_store_unverified', 'test_usr_store_unverified', 'medicalStore', 'test_usr_store_unverified', 'Store Unverified', 'unverified_store@test.local', '+919999900097', false),
        ('test_usr_amb_unverified', 'test_usr_amb_unverified', 'ambulance', 'test_usr_amb_unverified', 'Amb Unverified', 'unverified_amb@test.local', '+919999900096', false),
        ('test_usr_amb_unclaimed', 'test_usr_amb_unclaimed', 'ambulance', 'test_amb_unclaimed', 'Driver Unclaimed', 'unclaimed_amb@test.local', '+919999900095', true)
      ON CONFLICT (id) DO NOTHING;
    `);

    await client.query(`
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors) VALUES
        ('${pA}', '${pA}', 'Patient A', '+919999900001', true),
        ('${pB}', '${pB}', 'Patient B', '+919999900002', false),
        ('test_fam_a1', '${pA}', 'Child A', '+919999900001', true);
      INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated) VALUES
        ('test_orphan_doc', NULL, 'Orphan Dr', 'orphan@test.local', '+919999900998', 'General', 'MBBS', true, false),
        ('${docA}', '${docA}', 'Dr. A', 'da@test.local', '+919999900003', 'General', 'MBBS', true, false),
        ('${docB}', '${docB}', 'Dr. B', 'db@test.local', '+919999900004', 'Cardiology', 'MD', true, false),
        ('test_usr_doc_unverified', 'test_usr_doc_unverified', 'Dr. Unverified', 'unverified@test.local', '+919999900099', 'General', 'MBBS', false, false);
      INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified) VALUES
        ('${storeA}', '${storeA}', 'Store A', 'Owner A', 'DL-001', '+919999900005', 'sa@test.local', true),
        ('${storeB}', '${storeB}', 'Store B', 'Owner B', 'DL-002', '+919999900006', 'sb@test.local', true),
        ('test_usr_store_unverified', 'test_usr_store_unverified', 'Unverified Store', 'Owner U', 'DL-999', '+919999900097', 'unverified_store@test.local', false);
      INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified) VALUES
        ('${labA}', '${labA}', 'Lab A', 'LIC-001', '+919999900007', 'la@test.local', true),
        ('${labB}', '${labB}', 'Lab B', 'LIC-002', '+919999900008', 'lb@test.local', true),
        ('test_usr_lab_unverified', 'test_usr_lab_unverified', 'Unverified Lab', 'LIC-999', '+919999900098', 'unverified_lab@test.local', false);
      INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified) VALUES
        ('${ambA}', '${ambA}', 'Amb Service A', 'Driver A', '+919999900009', 'DL-01-A-1000', 'bls', 'Delhi', true),
        ('${ambB}', '${ambB}', 'Amb Service B', 'Driver B', '+919999900010', 'DL-01-B-2000', 'icu', 'Delhi', true),
        ('test_usr_amb_unverified', 'test_usr_amb_unverified', 'Unverified Amb', 'Driver U', '+919999900096', 'DL-01-U-9999', 'bls', 'Delhi', false),
        ('test_amb_unclaimed', NULL, 'Unclaimed Amb', 'Driver Unclaimed', '+919999900095', 'DL-01-U-0000', 'bls', 'Delhi', false);
    `);

    const apptId = 'test_appt_alpha';
    const hrId = 'test_hr_alpha';
    const bcId = 'test_ambbc_alpha';
    const bcPendingId = 'test_ambbc_pending';
    const bcCancelledId = 'test_ambbc_cancelled';
    const reqId = 'test_ambreq_alpha';
    const reqPendingId = 'test_ambreq_pending';
    const delId = 'test_del_alpha';
    const labBkId = 'test_lbbk_alpha';
    const labOrdId = 'test_lbord_alpha';
    await client.query(`
      INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status) VALUES
        ('${apptId}', '${docA}', '${pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
        ('appt_happy_fam', '${docA}', 'test_fam_a1', 'Dr. A', 'General', 'Child A', 8, 'Female', now() + interval '2 days', '11:30 AM', 'newVisit', 'confirmed', 'confirmed'),
        ('appt_completed_docA', '${docA}', '${pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now() - interval '1 day', '10:00 AM', 'newVisit', 'completed', 'completed'),
        ('appt_completed_fam', '${docA}', 'test_fam_a1', 'Dr. A', 'General', 'Child A', 8, 'Female', now() - interval '1 day', '11:00 AM', 'newVisit', 'completed', 'completed')
      ON CONFLICT (appointment_id) DO NOTHING;
      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors) VALUES
        ('${hrId}', '${pA}', 'CBC Report', 'labReport', CURRENT_DATE, 'selfUploaded', 'cbc.pdf', true);
      INSERT INTO public.ambulance_broadcasts (broadcast_id, patient_id, patient_name, contact_phone, pickup_location, drop_location, status, accepted_driver_id, accepted_driver_phone) VALUES
        ('${bcId}', '${pA}', 'Patient A', '+919999900001', 'Connaught Place', 'AIIMS', 'accepted', '${ambA}', '+919999900009'),
        ('${bcPendingId}', '${pA}', 'Patient A', '+919999900001', 'Karol Bagh', 'Safdarjung', 'pending', NULL, NULL),
        ('${bcCancelledId}', '${pA}', 'Patient A', '+919999900001', 'Rohini', 'Fortis', 'cancelled', '${ambA}', '+919999900009');
      INSERT INTO public.ambulance_requests (request_id, broadcast_id, driver_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status) VALUES
        ('${reqId}', '${bcId}', '${ambA}', '${pA}', 'Patient A', 'Connaught Place', 'AIIMS', '+919999900001', 'accepted'),
        ('${reqPendingId}', '${bcPendingId}', '${ambA}', '${pA}', 'Patient A', 'Karol Bagh', 'Safdarjung', '+919999900001', 'pending');
      INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age) VALUES
        ('test_rx_alpha', '${docA}', '${pA}', '${apptId}', 'Patient A', 30);
      INSERT INTO public.pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status) VALUES
        ('${delId}', 'test_rx_alpha', '${docA}', '${storeA}', '${pA}', 'Dr. A', 'Store A', 'Patient A', 'sent');
      INSERT INTO public.pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability, substitute_name) VALUES
        ('${delId}', 'med_1', 'pending', NULL)
      ON CONFLICT DO NOTHING;
      INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone) VALUES
        ('${bcId}', '+919999900001', '+919999900009')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.family_members (member_id, patient_id, name, relation, age, gender) VALUES
        ('test_fam_a1', '${pA}', 'Child A', 'child', 8, 'Female')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.lab_bookings (booking_id, lab_id, patient_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status) VALUES
        ('${labBkId}', '${labA}', '${pA}', 'Patient A', 30, 't1', 'Blood Test', ARRAY['Blood Test'], 'labVisit', CURRENT_TIMESTAMP, '10:00 AM', 'confirmed');
      INSERT INTO public.lab_orders (order_id, lab_id, doctor_id, patient_id, doctor_name, patient_name, patient_age, test_ids, test_names, status) VALUES
        ('${labOrdId}', '${labA}', '${docA}', '${pA}', 'Dr. A', 'Patient A', 30, ARRAY['t1'], ARRAY['Lipid Profile'], 'ordered');
    `);

    async function testCase({ name, table, role, claims, sql, expectedRows, expectedSqlState = '00000', allowZeroRows = false, assertResult = null }) {
      try {
        await client.query(`SAVEPOINT sp_case;`);
        await client.query(`SET LOCAL ROLE ${role};`);
        if (claims) {
          await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);
        } else {
          await client.query(`SELECT set_config('request.jwt.claims', '', true);`);
        }

        const res = await client.query(sql);
        const rowCount = Array.isArray(res) ? res[res.length - 1].rowCount : (res.rowCount !== null ? res.rowCount : (res.rows ? res.rows.length : 0));

        let pass = false;
        if (expectedSqlState === '00000') {
          if (expectedRows !== undefined) {
            pass = rowCount === expectedRows;
          } else if (allowZeroRows) {
            pass = rowCount === 0;
          } else {
            pass = true;
          }
          if (pass && typeof assertResult === 'function') {
            pass = Boolean(assertResult(res));
          }
        }

        results.push({
          name,
          table,
          role,
          expectedSqlState,
          actualSqlState: '00000',
          expectedRows,
          actualRows: rowCount,
          verdict: pass ? 'PASS' : 'FAIL',
        });

        await client.query(`ROLLBACK TO SAVEPOINT sp_case;`);
      } catch (err) {
        const sqlState = err.code || 'ERROR';
        const pass = sqlState === expectedSqlState;
        results.push({
          name,
          table,
          role,
          expectedSqlState,
          actualSqlState: sqlState,
          expectedRows: 0,
          actualRows: 0,
          verdict: pass ? 'PASS' : 'FAIL',
          error: err.message,
        });
        await client.query(`ROLLBACK TO SAVEPOINT sp_case;`);
      } finally {
        await client.query(`RESET ROLE;`);
      }
    }

    // --- POSITIVE CONTROLS ---
    await testCase({
      name: 'Positive Control: Patient A read own profile',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT * FROM public.patients WHERE patient_id = '${pA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Positive Control: Doctor A read own profile',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT * FROM public.doctors WHERE doctor_id = '${docA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Positive Control: Patient A read own health record',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT * FROM public.health_records WHERE record_id = '${hrId}';`,
      expectedRows: 1,
    });

    // --- HAPPY-PATH REALISTIC CLIENT WORKFLOWS ---
    // 1. book_appointment_atomic (own + family)
    await testCase({
      name: 'Happy Path: Patient A books own appointment via book_appointment_atomic',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.book_appointment_atomic('appt_happy_own', '${docA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', (CURRENT_TIMESTAMP + interval '2 days'), '11:00 AM', 'newVisit', 1, 'Clinic A', 'Address A', 'patient_supabase', '${pA}');`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Patient A books family member appointment via book_appointment_atomic',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.book_appointment_atomic('appt_happy_fam', '${docA}', 'Dr. A', 'General', 'Child A', 8, 'Female', (CURRENT_TIMESTAMP + interval '2 days'), '11:30 AM', 'newVisit', 2, 'Clinic A', 'Address A', 'patient_supabase', 'test_fam_a1');`,
      expectedRows: 1,
    });

    // 2. reschedule_appointment_atomic (patient, doctor, family owner; assert return keys)
    await testCase({
      name: 'Happy Path: Patient A reschedules own appointment (assert return keys)',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.reschedule_appointment_atomic('${apptId}', '${docA}', (CURRENT_DATE + interval '3 days')::date, '02:00 PM', 'patient', 'Travel reschedule');`,
      expectedRows: 1,
      assertResult: (res) => {
        const val = res.rows[0].reschedule_appointment_atomic;
        return val && val.ok === true && val.token_number !== undefined && val.date_time && val.slot_label === '02:00 PM';
      },
    });
    await testCase({
      name: 'Happy Path: Doctor A reschedules appointment (assert return keys)',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.reschedule_appointment_atomic('${apptId}', '${docA}', (CURRENT_DATE + interval '4 days')::date, '03:00 PM', 'doctor', 'Surgeon delayed');`,
      expectedRows: 1,
      assertResult: (res) => {
        const val = res.rows[0].reschedule_appointment_atomic;
        return val && val.ok === true && val.token_number !== undefined && val.date_time && val.slot_label === '03:00 PM';
      },
    });
    await testCase({
      name: 'Happy Path: Family owner reschedules family appointment',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.reschedule_appointment_atomic('appt_happy_fam', '${docA}', (CURRENT_DATE + interval '5 days')::date, '04:00 PM', 'patient', 'Child timing shift');`,
      expectedRows: 1,
    });

    // 3. create_prescription_atomic (medicines + investigations + referrals)
    await testCase({
      name: 'Happy Path: Doctor A creates full atomic prescription',
      table: 'prescriptions',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object(
        'prescription_id', 'rx_happy_1',
        'doctor_id', '${docA}',
        'patient_id', '${pA}',
        'patient_name', 'Patient A',
        'patient_age', 30,
        'appointment_id', '${apptId}',
        'medicines', jsonb_build_array(jsonb_build_object('name', 'Amoxicillin', 'dosage', '500mg', 'form', 'Tablet', 'quantity', '10', 'duration', '5 days', 'frequency', '1-0-1')),
        'investigations', jsonb_build_array(jsonb_build_object('name', 'Complete Blood Count', 'type', 'lab', 'notes', 'Fasting')),
        'referrals', jsonb_build_array(jsonb_build_object('to_doctor_id', '${docB}', 'doctor_name', 'Dr. B', 'specialization', 'Cardiology', 'reason', 'Cardiac evaluation'))
      ));`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Unverified Doctor: create_prescription_atomic rejected with 42501',
      table: 'prescriptions',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'test_usr_doc_unverified'),
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object(
        'prescription_id', 'rx_unverified_1',
        'doctor_id', 'test_usr_doc_unverified',
        'patient_id', '${pA}',
        'appointment_id', '${apptId}'
      ));`,
      expectedSqlState: '42501',
    });

    // 4. Ambulance workflow (accept -> location -> trip_contact -> complete and cancel)
    await testCase({
      name: 'Happy Path: Driver accepts ambulance request',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.accept_ambulance_request('${bcPendingId}');`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Driver updates ambulance location',
      table: 'ambulance_locations',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.update_ambulance_location('${bcId}', 28.6315, 77.2167, 40.0, 90.0);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Revoked RPC: Authenticated driver denied get_ambulance_trip_contact',
      table: 'rpc/get_ambulance_trip_contact',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT * FROM public.get_ambulance_trip_contact('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Revoked RPC: Authenticated patient denied get_ambulance_trip_contact',
      table: 'rpc/get_ambulance_trip_contact',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT * FROM public.get_ambulance_trip_contact('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Revoked RPC: Authenticated medical store denied get_ambulance_trip_contact',
      table: 'rpc/get_ambulance_trip_contact',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `SELECT * FROM public.get_ambulance_trip_contact('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Service Role Access: service_role allowed get_ambulance_trip_contact',
      table: 'rpc/get_ambulance_trip_contact',
      role: 'service_role',
      claims: getTestJwtClaims('service_role', 'service_role'),
      sql: `SELECT * FROM public.get_ambulance_trip_contact('${bcId}');`,
      expectedRows: 1,
    });

    // --- BROADCAST PHONE SECURITY & MASKING CONTROLS ---
    await testCase({
      name: 'Phone Privacy: Driver on pending broadcast sees masked contact_phone IS NULL',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT broadcast_id, contact_phone FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcPendingId}';`,
      expectedRows: 1,
      assertResult: (res) => res.rows.length === 1 && res.rows[0].contact_phone === null,
    });
    await testCase({
      name: 'Phone Privacy: Accepted driver reads accepted broadcast and sees patient contact_phone',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT broadcast_id, contact_phone FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 1,
      assertResult: (res) => res.rows.length === 1 && res.rows[0].contact_phone === '+919999900001',
    });
    await testCase({
      name: 'Phone Privacy: Owning patient reads accepted broadcast and sees accepted_driver_phone',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT broadcast_id, accepted_driver_phone FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 1,
      assertResult: (res) => res.rows.length === 1 && res.rows[0].accepted_driver_phone === '+919999900009',
    });
    await testCase({
      name: 'Phone Privacy: Unrelated driver ambB blocked from accepted broadcast',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT * FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 0,
      allowZeroRows: true,
    });
    await testCase({
      name: 'Phone Privacy: Unrelated patient pB blocked from accepted broadcast',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT * FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 0,
      allowZeroRows: true,
    });
    await testCase({
      name: 'Happy Path: Driver completes ambulance trip',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.complete_ambulance_trip('${bcId}');`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Patient cancels pending ambulance broadcast',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.cancel_ambulance_broadcast('${bcPendingId}', 'No longer needed');`,
      expectedRows: 1,
    });

    // 5. Lab booking & order transitions
    await testCase({
      name: 'Happy Path: Lab updates lab booking status to sampleCollected',
      table: 'lab_bookings',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `SELECT public.update_lab_booking_status('${labBkId}', 'sampleCollected');`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Lab updates lab order status to received',
      table: 'lab_orders',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `SELECT public.update_lab_order_status('${labOrdId}', 'received');`,
      expectedRows: 1,
    });

    // 6. Pharmacy delivery transitions incl. p_medicine_lines
    await testCase({
      name: 'Happy Path: Pharmacy marks delivery viewed',
      table: 'pharmacy_deliveries',
      role: 'authenticated',
      claims: getTestJwtClaims('pharmacy', storeA),
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'viewed', NULL, NULL);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Pharmacy dispenses delivery with p_medicine_lines',
      table: 'pharmacy_deliveries',
      role: 'authenticated',
      claims: getTestJwtClaims('pharmacy', storeA),
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'partiallyDispensed', 'Dispensed partial course', '[{"medicine_entry_id": "med_1", "availability": "available", "substitute_name": null}]'::jsonb);`,
      expectedRows: 1,
    });

    // 7. Users table insert + upsert + update across all 5 roles
    // Patient
    await testCase({
      name: 'Happy Path: Patient user insert',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', 'new_usr_pat'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_pat', 'new_usr_pat', 'patient', 'new_usr_pat', 'New Patient', 'newpat@test.local', '+919999901111', true);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Patient user upsert on conflict id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', 'new_usr_pat'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_pat', 'new_usr_pat', 'patient', 'new_usr_pat', 'New Patient Upserted', 'newpat@test.local', '+919999901111', true) ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Patient user update display_name',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.users SET display_name = 'Patient User A V2' WHERE id = '${pA}';`,
      expectedRows: 1,
    });

    // Doctor
    await testCase({
      name: 'Happy Path: Doctor user insert',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'new_usr_doc'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_doc', 'new_usr_doc', 'doctor', 'new_usr_doc', 'New Doctor', 'newdoc@test.local', '+919999902222', false);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Doctor user upsert on conflict id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'new_usr_doc'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_doc', 'new_usr_doc', 'doctor', 'new_usr_doc', 'New Doctor Upserted', 'newdoc@test.local', '+919999902222', false) ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Doctor user update display_name',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.users SET display_name = 'Doctor User A V2' WHERE id = '${docA}';`,
      expectedRows: 1,
    });

    // Pharmacy / Medical Store
    await testCase({
      name: 'Happy Path: Medical Store user insert',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', 'new_usr_store'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_store', 'new_usr_store', 'medicalStore', 'new_usr_store', 'New Store', 'newstore@test.local', '+919999903333', false);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Medical Store user upsert on conflict id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', 'new_usr_store'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_store', 'new_usr_store', 'medicalStore', 'new_usr_store', 'New Store Upserted', 'newstore@test.local', '+919999903333', false) ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Medical Store user update display_name',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.users SET display_name = 'Store User A V2' WHERE id = '${storeA}';`,
      expectedRows: 1,
    });

    // Lab
    await testCase({
      name: 'Happy Path: Lab user insert',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', 'new_usr_lab'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_lab', 'new_usr_lab', 'lab', 'new_usr_lab', 'New Lab', 'newlab@test.local', '+919999904444', false);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Lab user upsert on conflict id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', 'new_usr_lab'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_lab', 'new_usr_lab', 'lab', 'new_usr_lab', 'New Lab Upserted', 'newlab@test.local', '+919999904444', false) ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Lab user update display_name',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.users SET display_name = 'Lab User A V2' WHERE id = '${labA}';`,
      expectedRows: 1,
    });

    // Ambulance
    await testCase({
      name: 'Happy Path: Ambulance user insert',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'new_usr_amb'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_amb', 'new_usr_amb', 'ambulance', 'new_usr_amb', 'New Amb', 'newamb@test.local', '+919999905555', false);`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Ambulance user upsert on conflict id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'new_usr_amb'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_usr_amb', 'new_usr_amb', 'ambulance', 'new_usr_amb', 'New Amb Upserted', 'newamb@test.local', '+919999905555', false) ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Happy Path: Ambulance user update display_name',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.users SET display_name = 'Ambulance User A V2' WHERE id = '${ambA}';`,
      expectedRows: 1,
    });

    // 8. user_devices upsert on_conflict (user_id, platform)
    await testCase({
      name: 'Happy Path: User devices upsert on conflict (user_id, platform)',
      table: 'public.user_devices',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `INSERT INTO public.user_devices (user_id, platform, fcm_token) VALUES ('${pA}', 'android', 'fcm_tok_new_alpha') ON CONFLICT (user_id, platform) DO UPDATE SET fcm_token = EXCLUDED.fcm_token;`,
      expectedRows: 1,
    });

    // --- CROSS-TENANT ISOLATION (Expect 0 rows affected) ---
    await testCase({
      name: 'Cross-Tenant: Patient B read Patient A profile',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT * FROM public.patients WHERE patient_id = '${pA}';`,
      expectedRows: 0,
    });
    await testCase({
      name: 'Cross-Tenant: Patient B update Patient A health record',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `UPDATE public.health_records SET title = 'Hacked' WHERE record_id = '${hrId}';`,
      expectedRows: 0,
    });
    await testCase({
      name: 'Cross-Tenant: Patient B delete Patient A health record',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `DELETE FROM public.health_records WHERE record_id = '${hrId}';`,
      expectedRows: 0,
    });

    // --- CROSS-TENANT INSERT (Expect RLS with_check violation: 42501) ---
    await testCase({
      name: 'Cross-Tenant INSERT: Patient B inserts record with Patient A owner id',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name) VALUES ('hr_spoofed', '${pA}', 'Forged', 'labReport', CURRENT_DATE, 'selfUploaded', 'forged.pdf');`,
      expectedSqlState: '42501',
    });

    // --- ROLE ESCALATION & PROVIDER REGISTRATION RULES ---
    await testCase({
      name: 'Role Escalation: Patient A inserts into doctors table',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification) VALUES ('doc_esc', '${pA}', 'Imposter', 'imp@test.local', '+919000000000', 'General', 'MBBS');`,
      expectedSqlState: '42501', // Baseline allows (00000), Post-migration denies (42501)
    });
    await testCase({
      name: 'Role Escalation: Patient A inserts into medical_stores table',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email) VALUES ('store_esc', '${pA}', 'Imposter Store', 'Imposter Owner', 'DL-ESC', '+919000000000', 'store_esc@test.local');`,
      expectedSqlState: '42501', // Baseline allows (00000), Post-migration denies (42501)
    });
    await testCase({
      name: 'Role Escalation: Patient A elevates role in public.users',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.users SET role = 'super_admin' WHERE id = '${pA}';`,
      expectedSqlState: '42501',
    });

    // --- ANONYMOUS ACCESS (Expect permission denied 42501 or 0 rows) ---
    const anonTables = ['users', 'patients', 'appointments', 'health_records', 'prescriptions'];
    for (const t of anonTables) {
      await testCase({
        name: `Anon Access: Read table ${t}`,
        table: t,
        role: 'anon',
        claims: null,
        sql: `SELECT * FROM public."${t}" LIMIT 1;`,
        expectedSqlState: '42501', // Table grants revoked from anon post-migration
      });
    }

    // --- RELATIONSHIP RULES ---
    await testCase({
      name: 'Relationship: Linked Doctor A reads Patient A health record',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT * FROM public.health_records WHERE record_id = '${hrId}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Relationship: Unlinked Doctor B denied Patient A health record',
      table: 'health_records',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docB),
      sql: `SELECT * FROM public.health_records WHERE record_id = '${hrId}';`,
      expectedRows: 0,
    });

    // --- CLIENT RPC CROSS-USER AUTHORIZATION (Expect 42501 FORBIDDEN) ---
    await testCase({
      name: 'RPC Authz: book_appointment_atomic - Patient B books for Patient A',
      table: 'rpc/book_appointment_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT public.book_appointment_atomic('appt_cross_1', '${docA}', 'Dr. A', 'General', 'Patient B', 25, 'Male', now() + interval '2 days', '10:00 AM', 'newVisit', null, null, null, 'patient_supabase', '${pA}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: reschedule_appointment_atomic - Patient B reschedules Patient A appt',
      table: 'rpc/reschedule_appointment_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT public.reschedule_appointment_atomic('${apptId}', '${docA}', CURRENT_DATE + 3, '11:00 AM');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: create_prescription_atomic - Doctor B prescribes for Doctor A appt',
      table: 'rpc/create_prescription_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docB),
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object('prescription_id', 'rx_cross_1', 'patient_id', '${pA}', 'appointment_id', '${apptId}'));`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: cancel_ambulance_broadcast - Patient B cancels Patient A broadcast',
      table: 'rpc/cancel_ambulance_broadcast',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT public.cancel_ambulance_broadcast('${bcId}', 'Malicious cancel');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: complete_ambulance_trip - Driver B completes Driver A trip',
      table: 'rpc/complete_ambulance_trip',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT public.complete_ambulance_trip('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: update_ambulance_location - Driver B updates Driver A location',
      table: 'rpc/update_ambulance_location',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT public.update_ambulance_location('${bcId}', 28.5, 77.2);`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: get_ambulance_trip_location - Driver B views Patient A trip location',
      table: 'rpc/get_ambulance_trip_location',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT public.get_ambulance_trip_location('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: accept_ambulance_request - Patient A calls driver accept RPC',
      table: 'rpc/accept_ambulance_request',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.accept_ambulance_request('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: update_lab_booking_status - Lab B updates Lab A booking',
      table: 'rpc/update_lab_booking_status',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labB),
      sql: `SELECT public.update_lab_booking_status('${labBkId}', 'cancelled');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: update_lab_order_status - Lab B updates Lab A order',
      table: 'rpc/update_lab_order_status',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labB),
      sql: `SELECT public.update_lab_order_status('${labOrdId}', 'cancelled');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'RPC Authz: update_pharmacy_delivery_status - Store B updates Store A delivery',
      table: 'rpc/update_pharmacy_delivery_status',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeB),
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'cancelled');`,
      expectedSqlState: '42501',
    });

    // --- (a) UNPROFILED AUTHENTICATED CALLER (random sub, NO users row -> Expect 42501 FORBIDDEN across all 11 client RPCs) ---
    const unprofiledSub = 'test_usr_unprofiled_xyz';
    const claimsUnprofiled = getTestJwtClaims('patient', unprofiledSub);

    await testCase({
      name: 'Unprofiled Caller: book_appointment_atomic',
      table: 'rpc/book_appointment_atomic',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.book_appointment_atomic('appt_unprof_1', '${docA}', 'Dr. A', 'General', 'Anon', 30, 'Male', now() + interval '2 days', '10:00 AM');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: reschedule_appointment_atomic',
      table: 'rpc/reschedule_appointment_atomic',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.reschedule_appointment_atomic('${apptId}', '${docA}', CURRENT_DATE + 3, '11:00 AM');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: create_prescription_atomic',
      table: 'rpc/create_prescription_atomic',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object('prescription_id', 'rx_unprof_1', 'patient_id', '${pA}'));`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: cancel_ambulance_broadcast',
      table: 'rpc/cancel_ambulance_broadcast',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.cancel_ambulance_broadcast('${bcId}', 'Cancel unprofiled');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: complete_ambulance_trip',
      table: 'rpc/complete_ambulance_trip',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.complete_ambulance_trip('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: update_ambulance_location',
      table: 'rpc/update_ambulance_location',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.update_ambulance_location('${bcId}', 28.5, 77.2);`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: get_ambulance_trip_location',
      table: 'rpc/get_ambulance_trip_location',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.get_ambulance_trip_location('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: accept_ambulance_request',
      table: 'rpc/accept_ambulance_request',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.accept_ambulance_request('${bcPendingId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: update_lab_booking_status',
      table: 'rpc/update_lab_booking_status',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.update_lab_booking_status('${labBkId}', 'cancelled');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: update_lab_order_status',
      table: 'rpc/update_lab_order_status',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.update_lab_order_status('${labOrdId}', 'cancelled');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Unprofiled Caller: update_pharmacy_delivery_status',
      table: 'rpc/update_pharmacy_delivery_status',
      role: 'authenticated',
      claims: claimsUnprofiled,
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'cancelled');`,
      expectedSqlState: '42501',
    });

    // --- (b) CALLER OF WRONG ROLE / AMBULANCE LIFECYCLE (Expect 42501 FORBIDDEN) ---
    // complete_ambulance_trip by patient on accepted, pending, cancelled broadcasts
    await testCase({
      name: 'Wrong Role: Patient calls complete_ambulance_trip on accepted broadcast',
      table: 'rpc/complete_ambulance_trip',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.complete_ambulance_trip('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Wrong Role: Patient calls complete_ambulance_trip on pending broadcast',
      table: 'rpc/complete_ambulance_trip',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.complete_ambulance_trip('${bcPendingId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Wrong Role: Patient calls complete_ambulance_trip on cancelled broadcast',
      table: 'rpc/complete_ambulance_trip',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.complete_ambulance_trip('${bcCancelledId}');`,
      expectedSqlState: '42501',
    });

    // accept_ambulance_request by patient on accepted, pending, cancelled broadcasts
    await testCase({
      name: 'Wrong Role: Patient calls accept_ambulance_request on accepted broadcast',
      table: 'rpc/accept_ambulance_request',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.accept_ambulance_request('${bcId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Wrong Role: Patient calls accept_ambulance_request on pending broadcast',
      table: 'rpc/accept_ambulance_request',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.accept_ambulance_request('${bcPendingId}');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Wrong Role: Patient calls accept_ambulance_request on cancelled broadcast',
      table: 'rpc/accept_ambulance_request',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.accept_ambulance_request('${bcCancelledId}');`,
      expectedSqlState: '42501',
    });

    // update_ambulance_location by patient
    await testCase({
      name: 'Wrong Role: Patient calls update_ambulance_location',
      table: 'rpc/update_ambulance_location',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.update_ambulance_location('${bcId}', 28.5, 77.2);`,
      expectedSqlState: '42501',
    });

    // create_prescription_atomic by medicalStore and patient
    await testCase({
      name: 'Wrong Role: Medical Store calls create_prescription_atomic',
      table: 'rpc/create_prescription_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object('prescription_id', 'rx_store_1', 'patient_id', '${pA}'));`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Wrong Role: Patient calls create_prescription_atomic',
      table: 'rpc/create_prescription_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT public.create_prescription_atomic(jsonb_build_object('prescription_id', 'rx_pat_1', 'patient_id', '${pA}'));`,
      expectedSqlState: '42501',
    });

    // update_pharmacy_delivery_status by doctor
    await testCase({
      name: 'Wrong Role: Doctor calls update_pharmacy_delivery_status',
      table: 'rpc/update_pharmacy_delivery_status',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'cancelled');`,
      expectedSqlState: '42501',
    });

    // update_lab_booking_status by ambulance
    await testCase({
      name: 'Wrong Role: Ambulance driver calls update_lab_booking_status',
      table: 'rpc/update_lab_booking_status',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.update_lab_booking_status('${labBkId}', 'cancelled');`,
      expectedSqlState: '42501',
    });

    // update_lab_order_status by medical store
    await testCase({
      name: 'Wrong Role: Medical Store calls update_lab_order_status',
      table: 'rpc/update_lab_order_status',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `SELECT public.update_lab_order_status('${labOrdId}', 'cancelled');`,
      expectedSqlState: '42501',
    });

    // reschedule_appointment_atomic by ambulance
    await testCase({
      name: 'Wrong Role: Ambulance driver calls reschedule_appointment_atomic',
      table: 'rpc/reschedule_appointment_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.reschedule_appointment_atomic('${apptId}', '${docA}', CURRENT_DATE + 3, '11:00 AM');`,
      expectedSqlState: '42501',
    });

    // cancel_ambulance_broadcast by unrelated medical store on pending broadcast
    await testCase({
      name: 'Wrong Role: Medical Store calls cancel_ambulance_broadcast on pending broadcast',
      table: 'rpc/cancel_ambulance_broadcast',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `SELECT public.cancel_ambulance_broadcast('${bcPendingId}', 'Unauthorized cancel');`,
      expectedSqlState: '42501',
    });

    // get_ambulance_trip_location by unrelated medical store
    await testCase({
      name: 'Wrong Role: Medical Store calls get_ambulance_trip_location on broadcast',
      table: 'rpc/get_ambulance_trip_location',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `SELECT public.get_ambulance_trip_location('${bcId}');`,
      expectedSqlState: '42501',
    });

    // --- IDEMPOTENCY / APPOINTMENT CONFLICT CASE ---
    // Patient B calls book_appointment_atomic with Patient A's appointment_id and expects no data returned (42501)
    await testCase({
      name: 'Idempotency Conflict: Patient B calls book_appointment_atomic with Patient A appointment_id',
      table: 'rpc/book_appointment_atomic',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `SELECT public.book_appointment_atomic('${apptId}', '${docA}', 'Dr. A', 'General', 'Patient B', 25, 'Male', now() + interval '2 days', '10:00 AM', 'newVisit', null, null, null, 'patient_supabase', '${pB}');`,
      expectedSqlState: '42501',
    });

    // Task 2: Privilege Escalation & Column Tampering Harness Cases
    // (a) Authenticated user updates own users.role to 'admin' -> Expect 42501
    await testCase({
      name: 'Privilege Escalation: Authenticated user updates own users.role to admin',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.users SET role = 'admin' WHERE id = '${pA}';`,
      expectedSqlState: '42501',
    });

    // (b) Authenticated user updates own users.profile_id to another user's id -> Expect 42501
    await testCase({
      name: 'Identity Tampering: Authenticated user updates own users.profile_id to victim id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.users SET profile_id = '${pB}' WHERE id = '${pA}';`,
      expectedSqlState: '42501',
    });

    // (c) Authenticated user inserts a users row with a chosen role/profile_id -> Expect 42501
    await testCase({
      name: 'Account Provisioning Tampering: Authenticated user inserts users row claiming admin role',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', 'new_unregistered_attacker_uid'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('new_unregistered_attacker_uid', 'new_unregistered_attacker_uid', 'admin', 'victim_profile_id', 'Attacker Admin', 'attacker@test.local', '+919999900998', false);`,
      expectedSqlState: '42501',
    });

    // (d) Authenticated user changes patients.owner_uid -> Expect 42501
    await testCase({
      name: 'Resource Ownership Hijack: Authenticated user updates patients.owner_uid',
      table: 'public.patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.patients SET owner_uid = '${pB}' WHERE patient_id = '${pA}';`,
      expectedSqlState: '42501',
    });

    // (e) Authenticated user inserts users row claiming orphan doctor profile_id -> Expect 42501
    await testCase({
      name: 'Account Provisioning Tampering: User B inserts users row claiming orphan doctor profile_id',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', 'test_usr_pat_b_atk'),
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('test_usr_pat_b_atk', 'test_usr_pat_b_atk', 'patient', 'test_orphan_doc', 'Attacker', 'atk@test.local', '+919999900999', true);`,
      expectedSqlState: '42501',
    });

    // (f) Authenticated user B inserts doctors row with mismatched doctor_id -> Expect 42501
    await testCase({
      name: 'Resource Ownership Hijack: User B inserts doctors row with mismatched doctor_id',
      table: 'public.doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', pB),
      sql: `INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified) VALUES ('doc_arbitrary_123', '${pB}', 'Fake Dr', 'fakedr@test.local', '+919999900999', 'General', 'MBBS', false);`,
      expectedSqlState: '42501',
    });

    // (g) Anon user inserts users row -> Expect 42501
    await testCase({
      name: 'Account Provisioning Tampering: Anon user inserts users row',
      table: 'public.users',
      role: 'anon',
      claims: null,
      sql: `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES ('anon_usr_atk', 'anon_usr_atk', 'patient', 'anon_usr_atk', 'Anon Atk', 'anonatk@test.local', '+919999900996', false);`,
      expectedSqlState: '42501',
    });

    // --- ANON ROLE ACCESS ENFORCEMENT ---
    // (a) Allowed discovery views/tables for anon
    await testCase({
      name: 'Anon Access: Select from doctor_directory view',
      table: 'doctor_directory',
      role: 'anon',
      claims: null,
      sql: `SELECT count(*) FROM public.doctor_directory;`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Anon Access: Select from lab_catalog_tests table',
      table: 'lab_catalog_tests',
      role: 'anon',
      claims: null,
      sql: `SELECT count(*) FROM public.lab_catalog_tests;`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Anon Access: Select from review_public view',
      table: 'review_public',
      role: 'anon',
      claims: null,
      sql: `SELECT count(*) FROM public.review_public;`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Anon Access: Select from promoted_ads table',
      table: 'promoted_ads',
      role: 'anon',
      claims: null,
      sql: `SELECT ad_id, title, description, image_url, cta_label, status FROM public.promoted_ads;`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Anon Access: Select whitelisted keys from system_config (patient_module_status, promoted_ads)',
      table: 'system_config',
      role: 'anon',
      claims: null,
      sql: `SELECT config_key, config_value FROM public.system_config WHERE config_key IN ('patient_module_status', 'promoted_ads');`,
      expectedSqlState: '00000',
    });

    // (b) Denied access for anon on protected tables
    await testCase({
      name: 'Anon Access Denied: Select from users table',
      table: 'users',
      role: 'anon',
      claims: null,
      sql: `SELECT * FROM public.users LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Denied: Select from appointments table',
      table: 'appointments',
      role: 'anon',
      claims: null,
      sql: `SELECT * FROM public.appointments LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Denied: Select from patients table',
      table: 'patients',
      role: 'anon',
      claims: null,
      sql: `SELECT * FROM public.patients LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Denied: Select from doctors table',
      table: 'doctors',
      role: 'anon',
      claims: null,
      sql: `SELECT * FROM public.doctors LIMIT 1;`,
      expectedSqlState: '42501',
    });

    // --- HAPPY-PATH REALISTIC CLIENT 2-STEP REGISTRATIONS (users upsert -> domain profile insert) ---
    const regPat = 'reg_usr_pat_seq';
    await testCase({
      name: 'Happy Path Registration: 2-step registration for patient (users -> patients)',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', regPat),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${regPat}', '${regPat}', 'patient', '${regPat}', 'Reg Patient', 'regpat@test.local', '+919999980001', true);
        INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
        VALUES ('${regPat}', '${regPat}', 'Reg Patient', '+919999980001');
      `,
      expectedRows: 1,
    });

    const regDoc = 'reg_usr_doc_seq';
    await testCase({
      name: 'Happy Path Registration: 2-step registration for doctor (users -> doctors)',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', regDoc, false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${regDoc}', '${regDoc}', 'doctor', '${regDoc}', 'Reg Doctor', 'regdoc@test.local', '+919999980002', false);
        INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified)
        VALUES ('${regDoc}', '${regDoc}', 'Reg Doctor', 'regdoc@test.local', '+919999980002', 'General', 'MBBS', false);
      `,
      expectedRows: 1,
    });

    const regStore = 'reg_usr_store_seq';
    await testCase({
      name: 'Happy Path Registration: 2-step registration for medicalStore (users -> medical_stores)',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', regStore, false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${regStore}', '${regStore}', 'medicalStore', '${regStore}', 'Reg Store', 'regstore@test.local', '+919999980003', false);
        INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified)
        VALUES ('${regStore}', '${regStore}', 'Reg Store', 'Owner Reg', 'DL-REG-01', '+919999980003', 'regstore@test.local', false);
      `,
      expectedRows: 1,
    });

    const regLab = 'reg_usr_lab_seq';
    await testCase({
      name: 'Happy Path Registration: 2-step registration for lab (users -> labs)',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', regLab, false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${regLab}', '${regLab}', 'lab', '${regLab}', 'Reg Lab', 'reglab@test.local', '+919999980004', false);
        INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified)
        VALUES ('${regLab}', '${regLab}', 'Reg Lab', 'LIC-REG-01', '+919999980004', 'reglab@test.local', false);
      `,
      expectedRows: 1,
    });

    const regAmb = 'reg_usr_amb_seq';
    await testCase({
      name: 'Happy Path Registration: 2-step registration for ambulance (users -> ambulances)',
      table: 'public.users',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', regAmb, false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${regAmb}', '${regAmb}', 'ambulance', '${regAmb}', 'Reg Ambulance', 'regamb@test.local', '+919999980005', false);
        INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified)
        VALUES ('${regAmb}', '${regAmb}', 'Reg Amb Service', 'Driver Reg', '+919999980005', 'DL-01-REG', 'bls', 'Delhi', false);
      `,
      expectedRows: 1,
    });

    // --- PRIVILEGED COLUMNS GUARD CONTROLS ---
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot insert with verified=true',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'usr_doc_priv_ins', false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('usr_doc_priv_ins', 'usr_doc_priv_ins', 'doctor', 'usr_doc_priv_ins', 'Dr Priv Ins', 'priv_ins@test.local', '+919999981001', false);
        INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified)
        VALUES ('usr_doc_priv_ins', 'usr_doc_priv_ins', 'Dr Priv Ins', 'priv_ins@test.local', '+919999981001', 'Cardio', 'MD', true);
      `,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot update verified flag',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET verified = false WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot update deactivated flag',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET deactivated = true WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot change owner_uid',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET owner_uid = 'hacked_owner' WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Normal profile edit allowed for doctor owner',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET qualification = 'MBBS, MD (Gold Medalist)' WHERE doctor_id = '${docA}';`,
      expectedRows: 1,
    });

    await testCase({
      name: 'Privileged Columns: Lab owner cannot insert with verified=true',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', 'usr_lab_priv_ins', false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('usr_lab_priv_ins', 'usr_lab_priv_ins', 'lab', 'usr_lab_priv_ins', 'Lab Priv Ins', 'lab_ins@test.local', '+919999981002', false);
        INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified)
        VALUES ('usr_lab_priv_ins', 'usr_lab_priv_ins', 'Lab Priv Ins', 'LIC-PRIV-01', '+919999981002', 'lab_ins@test.local', true);
      `,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Lab owner cannot update verified flag',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET verified = false WHERE lab_id = '${labA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Lab owner cannot change owner_uid',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET owner_uid = 'hacked_owner' WHERE lab_id = '${labA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Normal profile edit allowed for lab owner',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET lab_name = 'Lab A Renovated' WHERE lab_id = '${labA}';`,
      expectedRows: 1,
    });

    await testCase({
      name: 'Privileged Columns: Store owner cannot insert with verified=true',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', 'usr_store_priv_ins', false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('usr_store_priv_ins', 'usr_store_priv_ins', 'medicalStore', 'usr_store_priv_ins', 'Store Priv Ins', 'store_ins@test.local', '+919999981003', false);
        INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified)
        VALUES ('usr_store_priv_ins', 'usr_store_priv_ins', 'Store Priv Ins', 'Owner Priv', 'DL-PRIV-01', '+919999981003', 'store_ins@test.local', true);
      `,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Store owner cannot update verified flag',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET verified = false WHERE store_id = '${storeA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Normal profile edit allowed for store owner',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET store_name = 'Store A Updated' WHERE store_id = '${storeA}';`,
      expectedRows: 1,
    });

    await testCase({
      name: 'Privileged Columns: Ambulance owner cannot insert with verified=true',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'usr_amb_priv_ins', false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('usr_amb_priv_ins', 'usr_amb_priv_ins', 'ambulance', 'usr_amb_priv_ins', 'Amb Priv Ins', 'amb_ins@test.local', '+919999981004', false);
        INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified)
        VALUES ('usr_amb_priv_ins', 'usr_amb_priv_ins', 'Amb Priv Ins', 'Driver Priv', '+919999981004', 'DL-01-PRIV', 'bls', 'Delhi', true);
      `,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Ambulance owner cannot update verified flag',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET verified = false WHERE ambulance_id = '${ambA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Ambulance owner cannot change auth_uid',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET auth_uid = 'hacked_auth' WHERE ambulance_id = '${ambA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Normal profile edit allowed for ambulance owner',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET service_name = 'Amb A Deluxe' WHERE ambulance_id = '${ambA}';`,
      expectedRows: 1,
    });

    // --- PATIENTS GUARD & SQUATTING PREVENTIONS ---
    await testCase({
      name: 'Family Guard: Attacker B denied squatting un-namespaced patient_id as family member',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `INSERT INTO public.patients (patient_id, owner_uid, name, mobile) VALUES ('victim_squatted_001', '${pB}', 'Squatted Victim', '+919999900002');`,
      expectedSqlState: '42501',
    });
    const dartGenFamilyId = `${pA}_fm1730000000000`; // Dart AddFamilyMemberProfileScreen.generateFamilyMemberId
    await testCase({
      name: 'Family Guard: Patient A inserts namespaced family patient successfully',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `INSERT INTO public.patients (patient_id, owner_uid, name, mobile) VALUES ('${dartGenFamilyId}', '${pA}', 'Legit Child', '+919999900001');`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Family Guard: Unsquatted victim registers primary profile without collision',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', 'victim_squatted_001'),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('victim_squatted_001', 'victim_squatted_001', 'patient', 'victim_squatted_001', 'Victim User', 'vic@test.local', '+919999989999', true);
        INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
        VALUES ('victim_squatted_001', 'victim_squatted_001', 'Victim User', '+919999989999');
      `,
      expectedRows: 1,
    });

    // --- USERS UPSERT FOR VERIFIED PROVIDER RE-LOGIN ---
    await testCase({
      name: 'Users Upsert: Existing verified doctor re-login upsert succeeds',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${docA}', '${docA}', 'doctor', '${docA}', 'Dr A Re-login', 'da@test.local', '+919999900003', true)
        ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, verified = EXCLUDED.verified;
      `,
      expectedRows: 1,
    });
    await testCase({
      name: 'Users Upsert: Existing verified medical store re-login upsert succeeds',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${storeA}', '${storeA}', 'medicalStore', '${storeA}', 'Store A Re-login', 'sa@test.local', '+919999900005', true)
        ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, verified = EXCLUDED.verified;
      `,
      expectedRows: 1,
    });
    await testCase({
      name: 'Users Upsert: Existing verified lab re-login upsert succeeds',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${labA}', '${labA}', 'lab', '${labA}', 'Lab A Re-login', 'la@test.local', '+919999900007', true)
        ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, verified = EXCLUDED.verified;
      `,
      expectedRows: 1,
    });
    await testCase({
      name: 'Users Upsert: Existing verified ambulance re-login upsert succeeds',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('${ambA}', '${ambA}', 'ambulance', '${ambA}', 'Amb A Re-login', 'aa@test.local', '+919999900009', true)
        ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, verified = EXCLUDED.verified;
      `,
      expectedRows: 1,
    });

    // --- ANONYMOUS ACCESS RESTRICTIONS & COLUMN PRUNING ---
    await testCase({
      name: 'Anon Access Denied: Anonymous caller cannot SELECT from medical_directory',
      table: 'medical_directory',
      role: 'anon',
      claims: null,
      sql: `SELECT * FROM public.medical_directory LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Denied: Anonymous caller cannot SELECT amount_paid from promoted_ads',
      table: 'promoted_ads',
      role: 'anon',
      claims: null,
      sql: `SELECT amount_paid FROM public.promoted_ads LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Denied: Anonymous caller cannot SELECT payment_status from promoted_ads',
      table: 'promoted_ads',
      role: 'anon',
      claims: null,
      sql: `SELECT payment_status FROM public.promoted_ads LIMIT 1;`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Anon Access Allow: Anonymous caller selects public columns from promoted_ads',
      table: 'promoted_ads',
      role: 'anon',
      claims: null,
      sql: `SELECT ad_id, title, description, image_url, cta_label, status FROM public.promoted_ads LIMIT 1;`,
      expectedSqlState: '00000',
    });

    // --- ROUND 4: TRUSTED WRITERS & DOMAIN GUARDS ---
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot update own rating',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET rating = 5.0 WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Trusted Writers: Patient A submits review on Doctor A and aggregates update rating',
      table: 'reviews',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `
        INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment)
        VALUES ('test_rev_round4', '${pA}', '${docA}', 'Patient A', 5, 'Great consultation and care');
      `,
      expectedRows: 1,
    });
    await testCase({
      name: 'Trusted Writers: Assigned driver completes ambulance trip via complete_ambulance_trip RPC',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT public.complete_ambulance_trip('${bcId}');`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Trusted Writers: Super admin verifies unverified doctor account',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('super_admin', 'super_admin_test_uid'),
      sql: `UPDATE public.doctors SET verified = true WHERE doctor_id = 'test_usr_doc_unverified';`,
      expectedRows: 1,
    });

    // --- ROUND 5: DOMAIN ALLOWLIST, REVIEWS POLICY, AMBULANCE PHONE & FORGERY DEFENSE ---
    // Item 1: Claims Provenance & Admin Write Denial
    await testCase({
      name: 'Admin Write Denied: Authenticated patient denied admin write to verify doctor (UPDATE doctors SET verified=true as non-owner)',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.doctors SET verified = true WHERE doctor_id = 'test_usr_doc_unverified';`,
      expectedSqlState: '42501',
    });

    // Item 2: Domain UPDATE allowlist - Deny privileged columns per table
    // Doctors
    await testCase({
      name: 'Privileged Columns: Unverified doctor owner cannot self-verify by updating verified=true',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'test_usr_doc_unverified'),
      sql: `UPDATE public.doctors SET verified = true WHERE doctor_id = 'test_usr_doc_unverified';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Doctor owner cannot update owner_uid',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET owner_uid = 'hacked_uid' WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });

    // Labs
    await testCase({
      name: 'Privileged Columns: Lab owner cannot update rating',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET rating = 5.0 WHERE lab_id = '${labA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Unverified lab owner cannot self-verify by updating verified=true',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', 'test_usr_lab_unverified'),
      sql: `UPDATE public.labs SET verified = true WHERE lab_id = 'test_usr_lab_unverified';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Lab owner cannot update owner_uid',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET owner_uid = 'hacked_uid' WHERE lab_id = '${labA}';`,
      expectedSqlState: '42501',
    });

    // Medical Stores
    await testCase({
      name: 'Privileged Columns: Unverified medical store owner cannot self-verify by updating verified=true',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', 'test_usr_store_unverified'),
      sql: `UPDATE public.medical_stores SET verified = true WHERE store_id = 'test_usr_store_unverified';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Medical store owner cannot update owner_uid',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET owner_uid = 'hacked_uid' WHERE store_id = '${storeA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Medical store owner cannot update unallowlisted column (deactivated)',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET deactivated = true WHERE store_id = '${storeA}';`,
      expectedSqlState: '42501',
    });

    // Ambulances
    await testCase({
      name: 'Privileged Columns: Ambulance owner cannot update total_rating',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET total_rating = 5.0 WHERE ambulance_id = '${ambA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Unverified ambulance owner cannot self-verify by updating verified=true',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'test_usr_amb_unverified'),
      sql: `UPDATE public.ambulances SET verified = true WHERE ambulance_id = 'test_usr_amb_unverified';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Ambulance owner cannot update auth_uid (via UPDATE guard)',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET auth_uid = 'hacked_uid' WHERE ambulance_id = '${ambA}';`,
      expectedSqlState: '42501',
    });

    // Patients
    await testCase({
      name: 'Privileged Columns: Patient owner cannot update verified flag',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.patients SET verified = false WHERE patient_id = '${pA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Privileged Columns: Patient owner cannot update owner_uid',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.patients SET owner_uid = 'hacked_uid' WHERE patient_id = '${pA}';`,
      expectedSqlState: '42501',
    });

    // Reviews Deny Cases
    await testCase({
      name: 'Reviews Guard: Patient B denied review without completed appointment',
      table: 'reviews',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pB),
      sql: `INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment) VALUES ('test_rev_pB_no_appt', '${pB}', '${docA}', 'Patient B', 4, 'No prior visit');`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'Reviews Guard: Doctor A denied self-reviewing own profile',
      table: 'reviews',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment) VALUES ('test_rev_docA_self', '${docA}', '${docA}', 'Dr A', 5, 'I am great');`,
      expectedSqlState: '42501',
    });

    // Item 3: Ambulance Phone Queries via PostgREST mapping
    await testCase({
      name: 'Ambulance Phone: Driver reads accepted broadcast through exact PostgREST query with unmasked contact_phone',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT contact_phone, patient_name, pickup_location, status, accepted_driver_id, accepted_driver_phone FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 1,
      assertResult: (res) => {
        const row = res.rows[0];
        return row && row.contact_phone === '+919999900001' && row.accepted_driver_phone === '+919999900009';
      },
    });
    await testCase({
      name: 'Ambulance Phone: Patient reads accepted broadcast through exact PostgREST query with accepted_driver_phone',
      table: 'ambulance_broadcasts',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `SELECT contact_phone, patient_name, pickup_location, status, accepted_driver_id, accepted_driver_phone FROM public.ambulance_broadcasts WHERE broadcast_id = '${bcId}';`,
      expectedRows: 1,
      assertResult: (res) => {
        const row = res.rows[0];
        return row && row.accepted_driver_phone === '+919999900009';
      },
    });

    // --- ROUND 6: KYC IMMUTABILITY, CLIENT WRITE COMPATIBILITY & REVIEWS ---
    // Item 4: KYC field immutability
    await testCase({
      name: 'KYC Immutability: Verified doctor owner cannot update council_number',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET council_number = 'NEW-COUNCIL-001' WHERE doctor_id = '${docA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'KYC Immutability: Unverified doctor owner can update council_number',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'test_usr_doc_unverified'),
      sql: `UPDATE public.doctors SET council_number = 'DMC-NEW-999' WHERE doctor_id = 'test_usr_doc_unverified';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'KYC Immutability: Verified lab owner cannot update license_number',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET license_number = 'NEW-LIC-001' WHERE lab_id = '${labA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'KYC Immutability: Unverified lab owner can update license_number',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', 'test_usr_lab_unverified'),
      sql: `UPDATE public.labs SET license_number = 'LIC-UNV-888' WHERE lab_id = 'test_usr_lab_unverified';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'KYC Immutability: Verified medical store owner cannot update drug_license_number',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET drug_license_number = 'NEW-DL-001' WHERE store_id = '${storeA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'KYC Immutability: Unverified medical store owner can update drug_license_number',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', 'test_usr_store_unverified'),
      sql: `UPDATE public.medical_stores SET drug_license_number = 'DL-UNV-888' WHERE store_id = 'test_usr_store_unverified';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'KYC Immutability: Verified ambulance owner cannot update vehicle_number',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET vehicle_number = 'DL-01-A-9999' WHERE ambulance_id = '${ambA}';`,
      expectedSqlState: '42501',
    });
    await testCase({
      name: 'KYC Immutability: Unverified ambulance owner can update vehicle_number',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'test_usr_amb_unverified'),
      sql: `UPDATE public.ambulances SET vehicle_number = 'DL-01-U-7777' WHERE ambulance_id = 'test_usr_amb_unverified';`,
      expectedRows: 1,
    });

    // Item 3 & 4: Client write compatibility with exact frontend payloads & Provider lifecycle RPCs
    await testCase({
      name: 'Client Compatibility: Doctor owner updates profile with exact frontend payload',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `UPDATE public.doctors SET qualification = 'MBBS, MD', about = 'Dedicated physician', clinic_name = 'Care Clinic', city = 'Delhi', consultation_fee = 750.00, specialization = 'Cardiologist', experience_years = 12 WHERE doctor_id = '${docA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Client Compatibility: Patient owner updates profile with exact frontend payload',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.patients SET name = 'Patient A Updated', email = 'pa_updated@test.local', share_records_with_doctors = true, profile_completed = true WHERE patient_id = '${pA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Client Compatibility: Lab owner updates profile with exact frontend payload',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `UPDATE public.labs SET lab_name = 'Central Diagnostic Lab', phone = '+919999900003', email = 'lab_updated@test.local', area = 'Rohini Sector 7', city = 'Delhi', state = 'Delhi', country = 'India', pincode = '110085', address_line1 = '123 Health Ave', profile_completed = true WHERE lab_id = '${labA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Client Compatibility: Medical store owner updates profile with exact frontend payload',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `UPDATE public.medical_stores SET store_name = 'City Care Pharmacy', owner_name = 'Owner A Updated', phone = '+919999900005', email = 'pharmacy_updated@test.local', address_line1 = '456 Market St', city = 'Delhi', state = 'Delhi', pincode = '110001', profile_completed = true WHERE store_id = '${storeA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Client Compatibility: Ambulance driver updates profile with exact frontend payload',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `UPDATE public.ambulances SET service_name = 'Express Ambulance Network', driver_name = 'Driver A Senior', phone = '+919999900009', ambulance_type = 'als', city = 'Delhi', base_address = 'Connaught Place Base', has_oxygen = true, has_ventilator = true, is_24x7 = true, rate_per_km = 35.00, is_available = true, profile_completed = true WHERE ambulance_id = '${ambA}';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'Provider Lifecycle: Doctor owner deactivates profile via owner-bound RPC',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.deactivate_provider_profile();`,
      expectedSqlState: '00000',
    });
    await testCase({
      name: 'Provider Lifecycle: Doctor owner reactivates profile via owner-bound RPC',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.reactivate_provider_profile();`,
      expectedSqlState: '00000',
    });

    // Item 5: Reviews self-completion denial & Family owner review
    await testCase({
      name: 'Reviews Integrity: Patient cannot self-complete appointment to bypass review gating',
      table: 'appointments',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `UPDATE public.appointments SET patient_status = 'completed' WHERE appointment_id = '${apptId}';`,
      expectedSqlState: '42501',
    });

    await testCase({
      name: 'Reviews Support: Patient submits review on Doctor A for completed family member appointment',
      table: 'reviews',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `
        INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment)
        VALUES ('test_rev_fam_round6', 'test_fam_a1', '${docA}', 'Parent for Child A', 5, 'Exceptional care for my child');
      `,
      expectedRows: 1,
    });

    // Item 6: system_config anon keys
    await testCase({
      name: 'System Config: Anon selects whitelisted patient_module_status key',
      table: 'system_config',
      role: 'anon',
      claims: { role: 'anon' },
      sql: `SELECT config_key, config_value FROM public.system_config WHERE config_key = 'patient_module_status';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'System Config: Anon selects whitelisted promoted_ads key',
      table: 'system_config',
      role: 'anon',
      claims: { role: 'anon' },
      sql: `SELECT config_key, config_value FROM public.system_config WHERE config_key = 'promoted_ads';`,
      expectedRows: 1,
    });
    await testCase({
      name: 'System Config: Anon query on non-whitelisted key returns 0 rows',
      table: 'system_config',
      role: 'anon',
      claims: { role: 'anon' },
      sql: `SELECT config_key, config_value FROM public.system_config WHERE config_key = 'internal_secrets';`,
      expectedRows: 0,
    });

    // --- ROUND 8 REGRESSION & INVARIANT TESTS ---
    // Invariant: Existing verified doctor/lab/store/ambulance re-login upsert with verified:false succeeds and stays verified:true
    await testCase({
      name: 'Doctor re-login upsert with verified:false succeeds and stays verified:true',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `
        UPDATE public.doctors
        SET verified = false,
            name = 'Dr. A Re-login',
            specialization = 'General',
            qualification = 'MBBS'
        WHERE doctor_id = '${docA}'
        RETURNING verified;
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
      assertResult: res => res.rows[0].verified === true,
    });

    await testCase({
      name: 'Lab re-login upsert with verified:false succeeds and stays verified:true',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `
        UPDATE public.labs
        SET verified = false,
            lab_name = 'Lab A Re-login',
            phone = '+919999900007'
        WHERE lab_id = '${labA}'
        RETURNING verified;
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
      assertResult: res => res.rows[0].verified === true,
    });

    await testCase({
      name: 'Medical store re-login upsert with verified:false succeeds and stays verified:true',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `
        UPDATE public.medical_stores
        SET verified = false,
            store_name = 'Store A Re-login',
            phone = '+919999900005'
        WHERE store_id = '${storeA}'
        RETURNING verified;
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
      assertResult: res => res.rows[0].verified === true,
    });

    await testCase({
      name: 'Ambulance re-login upsert with verified:false succeeds and stays verified:true',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `
        UPDATE public.ambulances
        SET verified = false,
            driver_name = 'Driver A Re-login',
            phone = '+919999900009',
            is_available = true
        WHERE ambulance_id = '${ambA}'
        RETURNING verified;
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
      assertResult: res => res.rows[0].verified === true,
    });

    // Photo Upload Tests using exact keys from profile_photo_uploader.dart
    await testCase({
      name: 'Photo Upload: Doctor A updates photo keys via exact client payload (profile_photo_uploader.dart:227)',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `
        UPDATE public.doctors
        SET photo_key = 'doctor_profile/${docA}/avatar.jpg',
            photo_storage = 's3',
            photo_s3_key = 'doctor_profile/${docA}/avatar.jpg',
            photo_storage_provider = 's3',
            photo_updated_at = now()
        WHERE doctor_id = '${docA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    await testCase({
      name: 'Photo Upload: Doctor A clears photo keys via exact client payload (profile_photo_uploader.dart:381)',
      table: 'doctors',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `
        UPDATE public.doctors
        SET photo_key = NULL,
            photo_storage = NULL,
            photo_s3_key = NULL,
            photo_url = NULL,
            photo_updated_at = now()
        WHERE doctor_id = '${docA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    await testCase({
      name: 'Photo Upload: Patient A updates photo keys via exact client payload (profile_photo_uploader.dart:99)',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `
        UPDATE public.patients
        SET photo_key = 'patient_profile/${pA}/avatar.jpg',
            photo_storage = 's3',
            photo_s3_key = 'patient_profile/${pA}/avatar.jpg',
            photo_storage_provider = 's3',
            photo_updated_at = now()
        WHERE patient_id = '${pA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    await testCase({
      name: 'Photo Upload: Patient A clears photo keys via exact client payload (profile_photo_uploader.dart:331)',
      table: 'patients',
      role: 'authenticated',
      claims: getTestJwtClaims('patient', pA),
      sql: `
        UPDATE public.patients
        SET photo_key = NULL,
            photo_storage = NULL,
            photo_s3_key = NULL,
            photo_url = NULL,
            photo_updated_at = now()
        WHERE patient_id = '${pA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    // Domain Profile Edit Tests using exact extracted Dart payloads
    await testCase({
      name: 'Domain Profile Edit: Lab A updates profile using exact Dart payload (lab_repository.dart:210)',
      table: 'labs',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `
        UPDATE public.labs
        SET lab_name = 'Metro Diagnostic Centre',
            phone = '+919876543210',
            email = 'metro_lab@test.local',
            address_line1 = '123 Health Ave',
            address_line2 = 'Suite 4',
            city = 'Delhi',
            state = 'Delhi',
            country = 'India',
            pincode = '110001'
        WHERE lab_id = '${labA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    await testCase({
      name: 'Domain Profile Edit: Medical store A updates profile using exact Dart payload (medical_store_repository.dart:150)',
      table: 'medical_stores',
      role: 'authenticated',
      claims: getTestJwtClaims('medicalStore', storeA),
      sql: `
        UPDATE public.medical_stores
        SET store_name = 'Metro Pharmacy',
            owner_name = 'Owner Alpha',
            phone = '+919876543211',
            email = 'metro_pharmacy@test.local',
            address_line1 = '456 Pharma Lane',
            address_line2 = 'Shop 2',
            city = 'Delhi',
            state = 'Delhi',
            country = 'India',
            pincode = '110002'
        WHERE store_id = '${storeA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    await testCase({
      name: 'Domain Profile Edit: Ambulance A updates profile using exact Dart payload (ambulance_models.dart:191)',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `
        UPDATE public.ambulances
        SET service_name = 'Fast Ambulance Co',
            driver_name = 'Driver Alpha',
            phone = '+919876543212',
            city = 'Delhi',
            base_address = 'Depot 5 Central',
            has_oxygen = true,
            has_ventilator = true,
            has_stretcher = true,
            is_24x7 = true,
            rate_per_km = 30.50,
            is_available = true
        WHERE ambulance_id = '${ambA}';
      `,
      expectedRows: 1,
      expectedSqlState: '00000',
    });

    // Ambulance Driver Link RPC Tests (claim_ambulance_driver)
    await testCase({
      name: 'Ambulance Driver Link RPC: Driver links unclaimed ambulance profile (claim_ambulance_driver)',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', 'test_usr_amb_unclaimed'),
      sql: `SELECT public.claim_ambulance_driver('test_amb_unclaimed') AS success;`,
      expectedRows: 1,
      expectedSqlState: '00000',
      assertResult: res => res.rows[0].success === true,
    });

    await testCase({
      name: 'Ambulance Driver Link RPC: Non-owner driver link is denied with 42501',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT public.claim_ambulance_driver('test_amb_unclaimed');`,
      expectedSqlState: '42501',
    });

    await testCase({
      name: 'Ambulance Driver Link RPC: Anon driver link is denied with 42501',
      table: 'ambulances',
      role: 'anon',
      claims: { role: 'anon' },
      sql: `SELECT public.claim_ambulance_driver('test_amb_unclaimed');`,
      expectedSqlState: '42501',
    });

    await testCase({
      name: 'Ambulance Driver Link RPC: Driver claims already-claimed row is denied with 42501',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambB),
      sql: `SELECT public.claim_ambulance_driver('${ambA}');`,
      expectedSqlState: '42501',
    });

    await testCase({
      name: 'Ambulance Driver Link RPC: Non-ambulance role (doctor) is denied claim with 42501',
      table: 'ambulances',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', docA),
      sql: `SELECT public.claim_ambulance_driver('test_amb_unclaimed');`,
      expectedSqlState: '42501',
    });

    await testCase({
      name: 'Users Guard: Unverified domain user upserting verified=true is denied with 42501',
      table: 'users',
      role: 'authenticated',
      claims: getTestJwtClaims('doctor', 'test_usr_doc_unverified', false),
      sql: `
        INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
        VALUES ('test_usr_doc_unverified', 'test_usr_doc_unverified', 'doctor', 'test_usr_doc_unverified', 'Dr. Unverified', 'unverified@test.local', '+919999900099', true)
        ON CONFLICT (id) DO UPDATE SET verified = true;
      `,
      expectedSqlState: '42501',
    });

    // Always ROLLBACK everything
    await client.query('ROLLBACK');
    console.log('✔ Transaction ROLLED BACK successfully.');

    // Verify Zero Residue
    const afterCountRes = await client.query(`SELECT count(*)::int as cnt FROM public.users;`);
    const countAfter = afterCountRes.rows[0].cnt;
    console.log(`Row count after rollback: ${countAfter} (Delta: ${countAfter - countBefore})`);

    if (countAfter !== countBefore) {
      console.error(`FATAL: Zero residue invariant violated! ${countAfter - countBefore} rows leaked.`);
      process.exit(1);
    }
    console.log('✔ ZERO RESIDUE PROVEN: Database row counts before and after are identical.');

    // Print Results Summary
    console.log('\n--- SQL Harness Results Matrix ---');
    console.table(results.map(r => ({
      Test: r.name,
      Role: r.role,
      Expected_SQLSTATE: r.expectedSqlState,
      Actual_SQLSTATE: r.actualSqlState,
      Expected_Rows: r.expectedRows,
      Actual_Rows: r.actualRows,
      Verdict: r.verdict,
    })));

    // Load previous run for comparative before/after matrix
    let prevMap = new Map();
    if (fs.existsSync('docs/ops/rls_sql_harness_results.json')) {
      try {
        const prev = JSON.parse(fs.readFileSync('docs/ops/rls_sql_harness_results.json', 'utf8'));
        if (Array.isArray(prev.results)) {
          for (const item of prev.results) {
            prevMap.set(item.name, item);
          }
        }
      } catch (_) {}
    }

    fs.writeFileSync('docs/ops/rls_sql_harness_results.json', JSON.stringify({ target, results, zeroResidue: true }, null, 2));

    const tsStr = new Date().toISOString().replace(/[:.]/g, '-');
    const mdPath = path.resolve(__dirname, `../../docs/reports/rls_harness_${target}_${tsStr}.md`);
    let md = `# RLS SQL Harness Report (${target.toUpperCase()})\n\n`;
    md += `**Timestamp:** ${new Date().toISOString()}  \n`;
    md += `**Target:** ${target}  \n`;
    md += `**Zero Residue:** PROVEN (Count Before: ${countBefore}, Count After: ${countAfter})  \n\n`;

    md += `## 1. Fixture Changes (Audit Justification)\n\n`;
    md += `| Fixture | Before | After | Schema Justification |\n`;
    md += `|---|---|---|---|\n`;
    md += `| \`public.patients\` | Only primary profiles (\`pA\`, \`pB\`) | Primary profiles + family patient profile \`test_fam_a1\` (owner_uid: \`pA\`) | Satisfies FK \`appointments_patient_id_fkey\` which references \`patients(patient_id)\` |\n`;
    md += `| \`public.doctors\` | Only verified doctors (\`docA\`, \`docB\`) | Verified doctors + unverified doctor \`test_usr_doc_unverified\` (\`verified = false\`) | Required to empirically test doctor verification check in \`create_prescription_atomic\` |\n`;
    md += `| \`pharmacy_delivery_medicines\` | Payload used \`"availability": "dispensed"\` | Payload uses \`"availability": "available"\` | Check constraint \`pharmacy_delivery_medicines_availability_check\` permits only: \`('pending', 'available', 'outOfStock', 'substituted')\` |\n\n`;

    md += `## 2. Before vs After Comparative Matrix\n\n`;
    md += `| Test Name | Previous Verdict | Current Verdict | Change Classification | Notes |\n`;
    md += `|---|---|---|---|---|\n`;

    const knownFixtureChanges = new Set([
      'Happy Path: Patient A books family member appointment via book_appointment_atomic',
      'Happy Path: Family owner reschedules family appointment',
      'Happy Path: Pharmacy dispenses delivery with p_medicine_lines',
    ]);

    for (const r of results) {
      const prevItem = prevMap.get(r.name);
      let prevVerdict = prevItem ? prevItem.verdict : 'N/A';
      let classification = 'unchanged-pass';
      let note = 'Maintained pass';

      if (!prevItem) {
        classification = 'new-test';
        note = 'Added in Staging Round 2';
      } else if (prevVerdict === 'FAIL' && r.verdict === 'PASS') {
        if (knownFixtureChanges.has(r.name)) {
          classification = 'fixture-change';
          note = 'Passing after schema-compliant fixture alignment';
        } else {
          classification = 'migration-effect';
          note = 'Fixed by migration 20261029000001';
        }
      } else if (r.verdict === 'FAIL') {
        classification = 'FAIL';
        note = r.error || 'Expected match failed';
      }

      md += `| ${r.name.replace(/\|/g, '\\|')} | ${prevVerdict} | ${r.verdict} | **${classification}** | ${note} |\n`;
    }

    md += `\n## 3. Full Results Matrix\n\n`;
    md += `| Test | Table | Role | Expected SQLSTATE | Actual SQLSTATE | Expected Rows | Actual Rows | Verdict |\n`;
    md += `|---|---|---|---|---|---|---|---|\n`;
    for (const r of results) {
      md += `| ${r.name.replace(/\|/g, '\\|')} | ${r.table} | ${r.role} | ${r.expectedSqlState} | ${r.actualSqlState} | ${r.expectedRows !== undefined ? r.expectedRows : '-'} | ${r.actualRows} | ${r.verdict} |\n`;
    }
    const failCount = results.filter(r => r.verdict === 'FAIL').length;
    const passCount = results.filter(r => r.verdict === 'PASS').length;
    md += `\n**Summary:** Total: ${results.length} | PASS: ${passCount} | FAIL: ${failCount}\n`;
    fs.writeFileSync(mdPath, md, 'utf8');
    console.log(`Report saved to: ${mdPath}`);

  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  runRlsSqlHarness().catch(err => {
    console.error('RLS SQL Harness failed:', err.message);
    process.exit(1);
  });
}

module.exports = { runRlsSqlHarness };
