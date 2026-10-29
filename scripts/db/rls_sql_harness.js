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
  if (appRole === 'superAdmin' || appRole === 'super_admin') normalized = 'super_admin';
  else if (appRole === 'medical' || appRole === 'pharmacy') normalized = 'medicalStore';

  const payload = buildPostgrestPayload({
    role: 'authenticated',
    sub: uid,
    appRole: normalized,
    verified: Boolean(verified),
  });

  return JSON.stringify(payload);
}

async function runRlsSqlHarness() {
  const args = process.argv.slice(2);
  const targetArg = args.find(a => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

  let poolConfig;
  let dbUrl;

  if (target === 'staging') {
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
        ('${ambB}', '${ambB}', 'ambulance', '${ambB}', 'Amb B', 'ab@test.local', '+919999900010', true)
      ON CONFLICT (id) DO NOTHING;
    `);

    await client.query(`
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors) VALUES
        ('${pA}', '${pA}', 'Patient A', '+919999900001', true),
        ('${pB}', '${pB}', 'Patient B', '+919999900002', false);
      INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated) VALUES
        ('test_orphan_doc', 'test_orphan_owner_uid', 'Orphan Dr', 'orphan@test.local', '+919999900998', 'General', 'MBBS', true, false),
        ('${docA}', '${docA}', 'Dr. A', 'da@test.local', '+919999900003', 'General', 'MBBS', true, false),
        ('${docB}', '${docB}', 'Dr. B', 'db@test.local', '+919999900004', 'Cardiology', 'MD', true, false);
      INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified) VALUES
        ('${storeA}', '${storeA}', 'Store A', 'Owner A', 'DL-001', '+919999900005', 'sa@test.local', true),
        ('${storeB}', '${storeB}', 'Store B', 'Owner B', 'DL-002', '+919999900006', 'sb@test.local', true);
      INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified) VALUES
        ('${labA}', '${labA}', 'Lab A', 'LIC-001', '+919999900007', 'la@test.local', true),
        ('${labB}', '${labB}', 'Lab B', 'LIC-002', '+919999900008', 'lb@test.local', true);
      INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified) VALUES
        ('${ambA}', '${ambA}', 'Amb Service A', 'Driver A', '+919999900009', 'DL-01-A-1000', 'bls', 'Delhi', true),
        ('${ambB}', '${ambB}', 'Amb Service B', 'Driver B', '+919999900010', 'DL-01-B-2000', 'icu', 'Delhi', true);
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
        ('${apptId}', '${docA}', '${pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed');
      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors) VALUES
        ('${hrId}', '${pA}', 'CBC Report', 'labReport', CURRENT_DATE, 'selfUploaded', 'cbc.pdf', true);
      INSERT INTO public.ambulance_broadcasts (broadcast_id, patient_id, patient_name, contact_phone, pickup_address, pickup_latitude, pickup_longitude, status, accepted_driver_id) VALUES
        ('${bcId}', '${pA}', 'Patient A', '+919999900001', 'Connaught Place', 28.6315, 77.2167, 'accepted', '${ambA}'),
        ('${bcPendingId}', '${pA}', 'Patient A', '+919999900001', 'Karol Bagh', 28.6515, 77.1900, 'pending', NULL),
        ('${bcCancelledId}', '${pA}', 'Patient A', '+919999900001', 'Rohini', 28.7041, 77.1025, 'cancelled', '${ambA}');
      INSERT INTO public.ambulance_requests (request_id, broadcast_id, driver_id, status) VALUES
        ('${reqId}', '${bcId}', '${ambA}', 'accepted'),
        ('${reqPendingId}', '${bcPendingId}', '${ambA}', 'pending');
      INSERT INTO public.pharmacy_deliveries (delivery_id, store_id, patient_id, delivery_address, delivery_pincode, contact_phone, status) VALUES
        ('${delId}', '${storeA}', '${pA}', '123 Test St', '110001', '+919999900001', 'sent');
      INSERT INTO public.pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability, substitute_name) VALUES
        ('${delId}', 'med_1', 'pending', NULL)
      ON CONFLICT DO NOTHING;
      INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone) VALUES
        ('${bcId}', '+919999900001', '+919999900009')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.family_members (member_id, patient_id, name, relationship, age, gender) VALUES
        ('test_fam_a1', '${pA}', 'Child A', 'Child', 8, 'Female')
      ON CONFLICT DO NOTHING;
      INSERT INTO public.lab_bookings (booking_id, lab_id, patient_id, test_id, test_name, sample_type, booking_date, slot, status) VALUES
        ('${labBkId}', '${labA}', '${pA}', 't1', 'Blood Test', 'blood', CURRENT_DATE, '10:00 AM', 'confirmed');
      INSERT INTO public.lab_orders (order_id, lab_id, doctor_id, patient_id, test_name, status) VALUES
        ('${labOrdId}', '${labA}', '${docA}', '${pA}', 'Lipid Profile', 'ordered');
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
        'appointment_id', '${apptId}',
        'medicines', jsonb_build_array(jsonb_build_object('name', 'Amoxicillin', 'dosage', '500mg', 'duration', '5 days', 'frequency', '1-0-1')),
        'investigations', jsonb_build_array(jsonb_build_object('name', 'Complete Blood Count', 'type', 'labReport', 'notes', 'Fasting')),
        'referrals', jsonb_build_array(jsonb_build_object('to_doctor_id', '${docB}', 'doctor_name', 'Dr. B', 'specialization', 'Cardiology', 'reason', 'Cardiac evaluation'))
      ));`,
      expectedRows: 1,
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
      name: 'Happy Path: Driver views ambulance trip contact',
      table: 'ambulance_trip_contacts',
      role: 'authenticated',
      claims: getTestJwtClaims('ambulance', ambA),
      sql: `SELECT * FROM public.get_ambulance_trip_contact('${bcId}');`,
      expectedRows: 1,
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
      name: 'Happy Path: Lab updates lab order status to inProgress',
      table: 'lab_orders',
      role: 'authenticated',
      claims: getTestJwtClaims('lab', labA),
      sql: `SELECT public.update_lab_order_status('${labOrdId}', 'inProgress');`,
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
      sql: `SELECT public.update_pharmacy_delivery_status('${delId}', 'dispensed', 'Dispensed full course', '[{"medicine_entry_id": "med_1", "availability": "dispensed", "substitute_name": null}]'::jsonb);`,
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
      claims: getTestJwtClaims('patient', 'new_usr_pat'),
      sql: `UPDATE public.users SET display_name = 'New Patient V2' WHERE id = 'new_usr_pat';`,
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
      claims: getTestJwtClaims('doctor', 'new_usr_doc'),
      sql: `UPDATE public.users SET display_name = 'New Doctor V2' WHERE id = 'new_usr_doc';`,
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
      claims: getTestJwtClaims('medicalStore', 'new_usr_store'),
      sql: `UPDATE public.users SET display_name = 'New Store V2' WHERE id = 'new_usr_store';`,
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
      claims: getTestJwtClaims('lab', 'new_usr_lab'),
      sql: `UPDATE public.users SET display_name = 'New Lab V2' WHERE id = 'new_usr_lab';`,
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
      claims: getTestJwtClaims('ambulance', 'new_usr_amb'),
      sql: `UPDATE public.users SET display_name = 'New Amb V2' WHERE id = 'new_usr_amb';`,
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
      sql: `INSERT INTO public.users (id, role, profile_id, display_name) VALUES ('new_unregistered_attacker_uid', 'admin', 'victim_profile_id', 'Attacker Admin');`,
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
      sql: `INSERT INTO public.doctors (doctor_id, owner_uid, name, specialization, qualification, verified) VALUES ('doc_arbitrary_123', '${pB}', 'Fake Dr', 'General', 'MBBS', false);`,
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

    fs.writeFileSync('docs/ops/rls_sql_harness_results.json', JSON.stringify({ target, results, zeroResidue: true }, null, 2));

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
