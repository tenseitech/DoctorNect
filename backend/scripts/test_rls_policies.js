/**
 * DoctorNect: Supabase RLS Manual Policy Verification Test Harness
 * 
 * Usage:
 *   node scripts/test_rls_policies.js
 * 
 * Environment variables:
 *   SUPABASE_DB_URL or DATABASE_URL: Postgres connection string for STAGING project
 */

require('./load_env').loadEnv();

const { Client } = require('pg');
const { v4: uuidv4 } = require('uuid');

const connectionString = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;

if (!connectionString) {
  console.error('ERROR: Staging DB connection string not found.');
  console.error('Please configure STAGING_SUPABASE_DB_URL in .env.migration.');
  process.exit(1);
}

const client = new Client({
  connectionString,
  ssl: { rejectUnauthorized: false },
});

// Synthetic IDs for test suite (obviously fake test data, zero PHI/PII)
const TEST_DOCTOR_A_ID = 'test-doc-a-' + uuidv4().slice(0, 8);
const TEST_DOCTOR_B_ID = 'test-doc-b-' + uuidv4().slice(0, 8);
const TEST_DOCTOR_UNVERIFIED_ID = 'test-doc-unver-' + uuidv4().slice(0, 8);

const TEST_PATIENT_A_ID = 'test-pat-a-' + uuidv4().slice(0, 8);
const TEST_PATIENT_B_ID = 'test-pat-b-' + uuidv4().slice(0, 8);
const TEST_PATIENT_INCOMPLETE_ID = 'test-pat-incomp-' + uuidv4().slice(0, 8);

const TEST_PHARMACY_ID = 'test-pharma-' + uuidv4().slice(0, 8);
const TEST_LAB_ID = 'test-lab-' + uuidv4().slice(0, 8);
const TEST_AMBULANCE_ID = 'test-amb-' + uuidv4().slice(0, 8);

const AUTH_UID_DOC_A = uuidv4();
const AUTH_UID_DOC_B = uuidv4();
const AUTH_UID_DOC_UNVER = uuidv4();

const AUTH_UID_PAT_A = uuidv4();
const AUTH_UID_PAT_B = uuidv4();
const AUTH_UID_PAT_INCOMP = uuidv4();

const AUTH_UID_PHARMA = uuidv4();
const AUTH_UID_LAB = uuidv4();
const AUTH_UID_AMB = uuidv4();

async function setAuthContext(authUid, role = 'authenticated') {
  // Use session-scope set_config (false = not tx-local) so claims survive outside a tx.
  // Set claims FIRST, then switch role so auth.uid() can read them.
  const claims = JSON.stringify({ sub: authUid, role, email: `${authUid}@test.doctornect.com` });
  await client.query(`SELECT set_config('request.jwt.claims', $1, false);`, [claims]);
  await client.query(`SELECT set_config('request.jwt.claim.sub', $1, false);`, [authUid]);
  await client.query(`SELECT set_config('request.jwt.claim.role', $1, false);`, [role]);
  await client.query('SET ROLE authenticated;');
}

async function resetAuthContext() {
  await client.query('RESET ROLE;');
  await client.query(`SELECT set_config('request.jwt.claims', '', false);`, []);
}

async function runRlsTests() {
  console.log('================================================================');
  console.log('DOCTORNECT RLS VERIFICATION TEST SUITE (STAGING DATABASE)');
  console.log('================================================================\n');

  try {
    await client.connect();
    console.log('Connected to Staging Postgres successfully.\n');

    if (process.argv.includes('--apply-migrations')) {
      const fs = require('fs');
      const path = require('path');
      console.log('-> Applying schema and RLS migrations to Staging...');
      const schemaSql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260923000001_doctornect_schema.sql'), 'utf8');
      const rlsSql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260923000002_doctornect_rls.sql'), 'utf8');
      await client.query(schemaSql);
      await client.query(rlsSql);
      console.log('-> Migrations successfully applied to Staging.\n');
    }

    // Temporarily drop FK constraint to auth.users so synthetic users can be seeded
    await client.query('ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;');

    // 1. SEED SYNTHETIC TEST FIXTURES (Running as superuser / postgres)
    console.log('-> Seeding synthetic test fixtures across all roles...');
    
    // Seed users
    const usersToInsert = [
      [AUTH_UID_DOC_A, 'doctor', TEST_DOCTOR_A_ID, 'Test Doctor A', true, true],
      [AUTH_UID_DOC_B, 'doctor', TEST_DOCTOR_B_ID, 'Test Doctor B', true, true],
      [AUTH_UID_DOC_UNVER, 'doctor', TEST_DOCTOR_UNVERIFIED_ID, 'Test Doctor Unverified', true, false],
      [AUTH_UID_PAT_A, 'patient', TEST_PATIENT_A_ID, 'Test Patient A', true, true],
      [AUTH_UID_PAT_B, 'patient', TEST_PATIENT_B_ID, 'Test Patient B', true, true],
      [AUTH_UID_PAT_INCOMP, 'patient', TEST_PATIENT_INCOMPLETE_ID, 'Test Patient Incomplete', false, false],
      [AUTH_UID_PHARMA, 'medicalStore', TEST_PHARMACY_ID, 'Test Pharmacy', true, true],
      [AUTH_UID_LAB, 'lab', TEST_LAB_ID, 'Test Lab', true, true],
      [AUTH_UID_AMB, 'ambulance', TEST_AMBULANCE_ID, 'Test Ambulance', true, true],
    ];

    for (const u of usersToInsert) {
      await client.query(
        `INSERT INTO users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
         VALUES ($1::uuid, $2, $3, $4, $5, $6, '0000000000', $7, $8, 'approved')
         ON CONFLICT (id) DO NOTHING`,
        [u[0], u[0], u[1], u[2], u[3], `${u[0]}@test.doctornect.com`, u[4], u[5]]
      );
    }

    // Seed doctors (include all NOT NULL columns from live staging schema)
    await client.query(
      `INSERT INTO doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
       VALUES 
         ($1, $2, 'Test Doctor A', 'doc_a@test.com', '0000000001', 'General Medicine', 'MBBS MD', TRUE, FALSE, TRUE),
         ($3, $4, 'Test Doctor B', 'doc_b@test.com', '0000000002', 'Cardiology', 'MBBS MD', TRUE, FALSE, TRUE),
         ($5, $6, 'Test Doctor Unverified', 'doc_unver@test.com', '0000000003', 'Orthopedics', 'MBBS MS', FALSE, FALSE, TRUE)
       ON CONFLICT (doctor_id) DO NOTHING`,
      [TEST_DOCTOR_A_ID, AUTH_UID_DOC_A, TEST_DOCTOR_B_ID, AUTH_UID_DOC_B, TEST_DOCTOR_UNVERIFIED_ID, AUTH_UID_DOC_UNVER]
    );

    // Seed patients
    await client.query(
      `INSERT INTO patients (patient_id, owner_uid, name, mobile, share_records_with_doctors, profile_completed, verified)
       VALUES 
         ($1, $2, 'Test Patient A', '1111111111', TRUE, TRUE, TRUE),
         ($3, $4, 'Test Patient B', '2222222222', TRUE, TRUE, TRUE),
         ($5, $6, 'Test Patient Incomplete', '3333333333', TRUE, FALSE, FALSE)
       ON CONFLICT (patient_id) DO NOTHING`,
      [TEST_PATIENT_A_ID, AUTH_UID_PAT_A, TEST_PATIENT_B_ID, AUTH_UID_PAT_B, TEST_PATIENT_INCOMPLETE_ID, AUTH_UID_PAT_INCOMP]
    );

    // Seed appointments linking Doctor A to Patient A, and Doctor B to Patient B
    await client.query(
      `INSERT INTO appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status)
       VALUES 
         ('apt-test-a', $1, $2, 'Test Doctor A', 'General Medicine', 'Test Patient A', 30, 'Male', NOW(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
         ('apt-test-b', $3, $4, 'Test Doctor B', 'Cardiology', 'Test Patient B', 45, 'Female', NOW(), '11:00 AM', 'newVisit', 'confirmed', 'confirmed')
       ON CONFLICT (appointment_id) DO NOTHING`,
      [TEST_DOCTOR_A_ID, TEST_PATIENT_A_ID, TEST_DOCTOR_B_ID, TEST_PATIENT_B_ID]
    );

    // Seed prescriptions (only confirmed NOT NULL columns from live schema)
    await client.query(
      `INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age)
       VALUES 
         ('rx-test-a', $1, $2, 'apt-test-a', 'Test Patient A', 30),
         ('rx-test-b', $3, $4, 'apt-test-b', 'Test Patient B', 45)
       ON CONFLICT (prescription_id) DO NOTHING`,
      [TEST_DOCTOR_A_ID, TEST_PATIENT_A_ID, TEST_DOCTOR_B_ID, TEST_PATIENT_B_ID]
    );

    console.log('-> Synthetic test fixtures successfully initialized.\n');

    const testResults = [];

    // ------------------------------------------------------------------------
    // TEST 1: Doctor Isolation
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_DOC_A);
    const docAPatients = await client.query('SELECT patient_id FROM patients;');
    const docAPatientIds = docAPatients.rows.map((r) => r.patient_id);
    const test1Pass = docAPatientIds.includes(TEST_PATIENT_A_ID) && !docAPatientIds.includes(TEST_PATIENT_B_ID);
    testResults.push({
      testNumber: 1,
      name: 'Doctor Isolation (Doctor A queries patients)',
      expected: 'Sees Patient A only; Patient B blocked',
      actual: `Returned: [${docAPatientIds.join(', ')}]`,
      status: test1Pass ? 'PASS' : 'FAIL',
    });

    // ------------------------------------------------------------------------
    // TEST 2: Patient Isolation
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_PAT_A);
    const patAAppointments = await client.query('SELECT appointment_id FROM appointments;');
    const patAAppIds = patAAppointments.rows.map((r) => r.appointment_id);
    const patAPrescriptions = await client.query('SELECT prescription_id FROM prescriptions;');
    const patARxIds = patAPrescriptions.rows.map((r) => r.prescription_id);
    const test2Pass =
      patAAppIds.includes('apt-test-a') &&
      !patAAppIds.includes('apt-test-b') &&
      patARxIds.includes('rx-test-a') &&
      !patARxIds.includes('rx-test-b');
    testResults.push({
      testNumber: 2,
      name: 'Patient Isolation (Patient A queries appointments/prescriptions)',
      expected: 'Sees own records only; Patient B records blocked',
      actual: `Appointments: [${patAAppIds.join(', ')}], Rx: [${patARxIds.join(', ')}]`,
      status: test2Pass ? 'PASS' : 'FAIL',
    });

    // ------------------------------------------------------------------------
    // TEST 3: Cross-Role Blocking (Pharmacy queries patients)
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_PHARMA);
    const pharmaPatients = await client.query('SELECT patient_id FROM patients;');
    const test3Pass = pharmaPatients.rows.length === 0;
    testResults.push({
      testNumber: 3,
      name: 'Cross-Role Blocking (Pharmacy queries patients table)',
      expected: 'Zero rows visible (completely blocked)',
      actual: `${pharmaPatients.rows.length} rows returned`,
      status: test3Pass ? 'PASS' : 'FAIL',
    });

    // ------------------------------------------------------------------------
    // TEST 4: Admin-Only Table Lockdown (security_events)
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_DOC_A);
    const secEventsSelect = await client.query('SELECT * FROM security_events;').catch(() => ({ rows: [] }));
    let secInsertBlocked = false;
    try {
      await client.query(`INSERT INTO security_events (event_type, details) VALUES ('test_event', '{"attempt": 1}')`);
    } catch (err) {
      secInsertBlocked = true;
    }
    const test4Pass = secEventsSelect.rows.length === 0 && secInsertBlocked;
    testResults.push({
      testNumber: 4,
      name: 'Admin-Only Table Lockdown (security_events direct client query)',
      expected: 'Zero rows on SELECT; INSERT rejected by policy',
      actual: `SELECT count: ${secEventsSelect.rows.length}, INSERT rejected: ${secInsertBlocked}`,
      status: test4Pass ? 'PASS' : 'FAIL',
    });

    // ------------------------------------------------------------------------
    // TEST 5: Doctor Verification Gating
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_DOC_UNVER);
    const unverDocPatients = await client.query('SELECT patient_id FROM patients;');
    // Check if unverified doctor appears in search when queried by Patient A
    await setAuthContext(AUTH_UID_PAT_A);
    const searchDocs = await client.query('SELECT doctor_id FROM doctors WHERE doctor_id = $1;', [TEST_DOCTOR_UNVERIFIED_ID]);
    const test5Pass = unverDocPatients.rows.length === 0 && searchDocs.rows.length === 0;
    testResults.push({
      testNumber: 5,
      name: 'Doctor Verification Gating (Unverified doctor access & discovery)',
      expected: 'Patient data blocked; hidden from public search',
      actual: `Patient rows: ${unverDocPatients.rows.length}, Search visible: ${searchDocs.rows.length > 0}`,
      status: test5Pass ? 'PASS' : 'FAIL',
    });

    // ------------------------------------------------------------------------
    // TEST 6: profileCompleted Gating
    // ------------------------------------------------------------------------
    await setAuthContext(AUTH_UID_PAT_INCOMP);
    const incompAppointments = await client.query('SELECT appointment_id FROM appointments;');
    const incompPrescriptions = await client.query('SELECT prescription_id FROM prescriptions;');
    // Does RLS block incomplete profiles or is it an app-layer route gate?
    const incompBlocked = incompAppointments.rows.length === 0 && incompPrescriptions.rows.length === 0;
    testResults.push({
      testNumber: 6,
      name: 'profileCompleted Gating (profile_completed = false querying content)',
      expected: 'Blocked from data-tab content (0 rows returned)',
      actual: incompBlocked ? 'Blocked (0 rows)' : `Permitted (${incompAppointments.rows.length + incompPrescriptions.rows.length} rows)`,
      status: incompBlocked ? 'PASS' : 'FAIL',
    });

    await resetAuthContext();

    // PRINT SUMMARY TABLE
    console.log('\n================================================================');
    console.log('RLS POLICY AUDIT RESULTS TABLE');
    console.log('================================================================');
    console.table(
      testResults.map((r) => ({
        '#': r.testNumber,
        Test: r.name,
        Expected: r.expected,
        Actual: r.actual,
        Result: r.status,
      }))
    );
  } catch (err) {
    console.error('Fatal execution error during RLS testing:', err);
  } finally {
    // CLEANUP: Remove all synthetic test fixtures and restore FK constraint
    console.log('\n-> Cleaning up synthetic test fixtures...');
    try {
      // Ensure we're back to superuser before cleanup (in case a test tx is still open)
      await client.query('ROLLBACK;').catch(() => {});
      await client.query('RESET ROLE;').catch(() => {});
      await client.query(`DELETE FROM prescriptions WHERE prescription_id IN ('rx-test-a', 'rx-test-b');`);
      await client.query(`DELETE FROM appointments WHERE appointment_id IN ('apt-test-a', 'apt-test-b');`);
      await client.query(`DELETE FROM patients WHERE patient_id IN ($1, $2, $3);`, [TEST_PATIENT_A_ID, TEST_PATIENT_B_ID, TEST_PATIENT_INCOMPLETE_ID]);
      await client.query(`DELETE FROM doctors WHERE doctor_id IN ($1, $2, $3);`, [TEST_DOCTOR_A_ID, TEST_DOCTOR_B_ID, TEST_DOCTOR_UNVERIFIED_ID]);
      await client.query(`DELETE FROM users WHERE id IN ($1, $2, $3, $4, $5, $6, $7, $8, $9);`,
        [AUTH_UID_DOC_A, AUTH_UID_DOC_B, AUTH_UID_DOC_UNVER,
         AUTH_UID_PAT_A, AUTH_UID_PAT_B, AUTH_UID_PAT_INCOMP,
         AUTH_UID_PHARMA, AUTH_UID_LAB, AUTH_UID_AMB]);
      // Restore the FK constraint to auth.users if not exists
      await client.query(`
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'users_id_fkey'
          ) THEN
            ALTER TABLE public.users
            ADD CONSTRAINT users_id_fkey
            FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
          END IF;
        END $$;
      `);
      console.log('-> Cleanup complete. FK constraint restored.');
    } catch (cleanupErr) {
      console.error('Warning: cleanup step encountered an error:', cleanupErr.message);
    }
    await client.end();
  }
}

runRlsTests();
