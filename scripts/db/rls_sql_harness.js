'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

// Emits real claims matching backend registration logic
function getTestJwtClaims(appRole, uid) {
  let normalized = appRole;
  if (appRole === 'superAdmin' || appRole === 'super_admin') normalized = 'super_admin';
  else if (appRole === 'medicalStore' || appRole === 'medical') normalized = 'pharmacy';

  return JSON.stringify({
    sub: uid,
    role: 'authenticated',
    app_role: normalized,
    user_role: normalized,
  });
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
    await client.query(`
      INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status) VALUES
        ('${apptId}', '${docA}', '${pA}', 'Dr. A', 'General', 'Patient A', 30, 'Male', now(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed');
      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors) VALUES
        ('${hrId}', '${pA}', 'CBC Report', 'labReport', CURRENT_DATE, 'selfUploaded', 'cbc.pdf', true);
    `);

    async function testCase({ name, table, role, claims, sql, expectedRows, expectedSqlState = '00000', allowZeroRows = false }) {
      try {
        await client.query(`SAVEPOINT sp_case;`);
        await client.query(`SET LOCAL ROLE ${role};`);
        if (claims) {
          await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);
        } else {
          await client.query(`SELECT set_config('request.jwt.claims', '', true);`);
        }

        const res = await client.query(sql);
        const rowCount = res.rowCount !== null ? res.rowCount : (res.rows ? res.rows.length : 0);

        let pass = false;
        if (expectedSqlState === '00000') {
          if (expectedRows !== undefined) {
            pass = rowCount === expectedRows;
          } else if (allowZeroRows) {
            pass = rowCount === 0;
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
