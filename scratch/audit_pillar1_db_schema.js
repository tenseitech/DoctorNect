require('../scripts/load_env').loadEnv();
const { Client } = require('../scripts/node_modules/pg');

async function auditPillar1() {
  const connectionString = process.env.STAGING_SUPABASE_DB_URL || process.env.SUPABASE_DB_URL;
  if (!connectionString) {
    console.error('ERROR: No database connection string found.');
    process.exit(1);
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('Connected to Supabase PostgreSQL successfully.');

    const expectedTables = [
      'users',
      'doctors',
      'doctor_availability',
      'patients',
      'family_members',
      'medical_stores',
      'labs',
      'ambulances',
      'appointments',
      'prescriptions',
      'prescription_medicines',
      'prescription_investigations',
      'health_records',
      'reviews',
      'system_config'
    ];

    // 1. Check tables existence
    const tablesRes = await client.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `);
    const existingTables = new Set(tablesRes.rows.map(r => r.table_name));

    console.log('\n--- Table Existence Audit ---');
    const tableAudit = [];
    for (const tbl of expectedTables) {
      const exists = existingTables.has(tbl);
      tableAudit.push({ Table: tbl, Exists: exists ? 'YES' : 'MISSING' });
    }
    console.table(tableAudit);

    // 2. Primary Keys & Foreign Keys
    console.log('\n--- Foreign Keys & Constraints ---');
    const fkRes = await client.query(`
      SELECT
        tc.table_name, 
        kcu.column_name, 
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name 
      FROM information_schema.table_constraints AS tc 
      JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage AS ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema='public';
    `);
    console.log(`Total Foreign Keys: ${fkRes.rowCount}`);
    console.table(fkRes.rows.slice(0, 15));

    // 3. Custom types / Enums
    console.log('\n--- Custom Enums / Types ---');
    const enumRes = await client.query(`
      SELECT t.typname, e.enumlabel
      FROM pg_type t 
      JOIN pg_enum e ON t.oid = e.enumtypid
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public'
      ORDER BY t.typname, e.enumsortorder;
    `);
    const enumsGrouped = {};
    for (const r of enumRes.rows) {
      if (!enumsGrouped[r.typname]) enumsGrouped[r.typname] = [];
      enumsGrouped[r.typname].push(r.enumlabel);
    }
    console.log('Enums defined in public:', Object.keys(enumsGrouped));

    // 4. Critical Indexes
    console.log('\n--- Critical Indexes on Appointments & Health Records ---');
    const idxRes = await client.query(`
      SELECT tablename, indexname, indexdef 
      FROM pg_indexes 
      WHERE schemaname = 'public' 
        AND tablename IN ('appointments', 'health_records', 'prescriptions')
      ORDER BY tablename, indexname;
    `);
    console.table(idxRes.rows.map(r => ({ Table: r.tablename, Index: r.indexname, Def: r.indexdef.substring(0, 80) + '...' })));

    // 5. Function verification: book_appointment_atomic
    console.log('\n--- RPC Function Verification: book_appointment_atomic ---');
    const funcRes = await client.query(`
      SELECT routine_name, routine_type, data_type, security_type
      FROM information_schema.routines 
      WHERE routine_schema = 'public' AND routine_name = 'book_appointment_atomic';
    `);
    if (funcRes.rowCount > 0) {
      console.log('Function book_appointment_atomic found:');
      console.table(funcRes.rows);
    } else {
      console.error('ERROR: book_appointment_atomic NOT found in public schema!');
    }

    // 6. Test invocation of book_appointment_atomic in a transaction that rolls back
    console.log('\n--- Functional Test of book_appointment_atomic (Dry Run in Rollback Tx) ---');
    await client.query('BEGIN');
    try {
      const testDoctorRes = await client.query('SELECT doctor_id FROM doctors LIMIT 1');
      const doctorId = testDoctorRes.rows[0]?.doctor_id || 'test_doc_001';
      
      const testRes = await client.query(`
        SELECT book_appointment_atomic(
          p_appointment_id => 'test_audit_apt_001',
          p_doctor_id => $1,
          p_patient_id => 'test_audit_pat_001',
          p_doctor_name => 'Dr. Audit Test',
          p_patient_name => 'Audit Patient',
          p_patient_age => 30,
          p_patient_gender => 'Other',
          p_date_time => '2026-10-15 10:00:00+05:30',
          p_slot_label => '10:00 AM',
          p_specialization => 'Cardiology',
          p_visit_type => 'newVisit'
        ) AS result;
      `, [doctorId]);
      console.log('book_appointment_atomic execution result:', testRes.rows[0]?.result);
    } catch (err) {
      console.log('book_appointment_atomic test notice/error:', err.message);
    } finally {
      await client.query('ROLLBACK');
      console.log('Rolled back test transaction cleanly.');
    }

  } finally {
    await client.end();
  }
}

auditPillar1().catch(err => {
  console.error('Pillar 1 audit failed:', err);
  process.exit(1);
});
