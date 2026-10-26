const { Client } = require('pg');
const admin = require('firebase-admin');
const fs = require('fs');

function parseSimpleEnv(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const res = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx > 0) {
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      res[key] = val;
    }
  }
  return res;
}

const migEnv = parseSimpleEnv('.env.migration');
const dbUrl = migEnv.STAGING_SUPABASE_DB_URL || migEnv.SUPABASE_DB_URL;

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  const saPath = fs.existsSync('scripts/service-account.json') ? 'scripts/service-account.json' : 'backend/functions/service-account.json';
  if (fs.existsSync(saPath)) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad'
    });
  } else {
    admin.initializeApp({ projectId: 'medibond-45fad' });
  }
}

async function findAndCleanLeftovers() {
  const client = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();
  console.log('[1/4] Connected to Supabase DB. Scanning tables for test leftovers...');

  // Get all tables in public schema
  const tablesRes = await client.query(`
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name;
  `);

  const tables = tablesRes.rows.map(r => r.table_name);
  const testPatterns = [
    '%rt_test%',
    '%smoke-test%',
    '%test_uid%',
    '%test_doc%',
    '%rt_user%',
    '%test_patient%',
    '%test_doctor%',
    '%test_pharmacy%',
    '%test_lab%',
    '%test_ambulance%',
    '%rls_test%'
  ];

  const leftoversBefore = {};

  for (const table of tables) {
    // Check columns of this table
    const colsRes = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = $1;
    `, [table]);
    const cols = colsRes.rows.map(c => c.column_name);

    const conditions = [];
    const params = [];
    let pIdx = 1;

    if (cols.includes('id')) {
      for (const pat of testPatterns) {
        conditions.push(`id::text LIKE $${pIdx}`);
        params.push(pat);
        pIdx++;
      }
    }
    if (cols.includes('uid')) {
      for (const pat of testPatterns) {
        conditions.push(`uid::text LIKE $${pIdx}`);
        params.push(pat);
        pIdx++;
      }
    }
    if (cols.includes('owner_uid')) {
      for (const pat of testPatterns) {
        conditions.push(`owner_uid::text LIKE $${pIdx}`);
        params.push(pat);
        pIdx++;
      }
    }
    if (cols.includes('doctor_id')) {
      for (const pat of testPatterns) {
        conditions.push(`doctor_id::text LIKE $${pIdx}`);
        params.push(pat);
        pIdx++;
      }
    }
    if (cols.includes('patient_id')) {
      for (const pat of testPatterns) {
        conditions.push(`patient_id::text LIKE $${pIdx}`);
        params.push(pat);
        pIdx++;
      }
    }
    if (cols.includes('metadata')) {
      conditions.push(`metadata::text LIKE '%test_run_id%'`);
      conditions.push(`metadata::text LIKE '%rls_test%'`);
    }

    if (conditions.length > 0) {
      const q = `SELECT count(*)::int as cnt FROM public."${table}" WHERE ${conditions.join(' OR ')}`;
      try {
        const countRes = await client.query(q, params);
        const count = countRes.rows[0].cnt;
        if (count > 0) {
          leftoversBefore[table] = count;
        }
      } catch (err) {
        // column type mismatch or similar
      }
    }
  }

  console.log('[2/4] Leftover rows in Supabase before cleanup:');
  console.table(leftoversBefore);

  // Now delete leftovers if any found
  const leftoversAfter = {};
  for (const [table, count] of Object.entries(leftoversBefore)) {
    const colsRes = await client.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = $1;
    `, [table]);
    const cols = colsRes.rows.map(c => c.column_name);

    const conditions = [];
    const params = [];
    let pIdx = 1;

    for (const col of ['id', 'uid', 'owner_uid', 'doctor_id', 'patient_id']) {
      if (cols.includes(col)) {
        for (const pat of testPatterns) {
          conditions.push(`${col}::text LIKE $${pIdx}`);
          params.push(pat);
          pIdx++;
        }
      }
    }
    if (cols.includes('metadata')) {
      conditions.push(`metadata::text LIKE '%test_run_id%'`);
      conditions.push(`metadata::text LIKE '%rls_test%'`);
    }

    if (conditions.length > 0) {
      const delQ = `DELETE FROM public."${table}" WHERE ${conditions.join(' OR ')}`;
      await client.query(delQ, params);
      
      const checkQ = `SELECT count(*)::int as cnt FROM public."${table}" WHERE ${conditions.join(' OR ')}`;
      const checkRes = await client.query(checkQ, params);
      leftoversAfter[table] = checkRes.rows[0].cnt;
    }
  }

  console.log('[3/4] Leftover rows in Supabase after cleanup:');
  console.table(leftoversAfter);

  await client.end();

  // Check Firebase Auth users
  console.log('[4/4] Checking Firebase Auth for test users...');
  let testUsersFound = [];
  try {
    const listUsersResult = await admin.auth().listUsers(1000);
    testUsersFound = listUsersResult.users.filter(u => {
      const uid = u.uid.toLowerCase();
      const email = (u.email || '').toLowerCase();
      return uid.includes('rt_test') || uid.includes('smoke-test') || uid.includes('test_') || uid.includes('rls_') ||
             email.includes('rt_test') || email.includes('smoke-test') || email.includes('test_') || email.includes('rls_');
    });

    console.log(`Firebase Auth test users found before cleanup: ${testUsersFound.length}`);
    for (const u of testUsersFound) {
      console.log(`  Deleting Firebase Auth user: ${u.uid} (${u.email || 'no email'})`);
      await admin.auth().deleteUser(u.uid);
    }

    const listAfter = await admin.auth().listUsers(1000);
    const testUsersAfter = listAfter.users.filter(u => {
      const uid = u.uid.toLowerCase();
      const email = (u.email || '').toLowerCase();
      return uid.includes('rt_test') || uid.includes('smoke-test') || uid.includes('test_') || uid.includes('rls_') ||
             email.includes('rt_test') || email.includes('smoke-test') || email.includes('test_') || email.includes('rls_');
    });
    console.log(`Firebase Auth test users remaining after cleanup: ${testUsersAfter.length}`);
  } catch (authErr) {
    console.warn('Firebase Auth list/delete error:', authErr.message);
  }

  console.log('\n--- CLEANUP COMPLETE ---');
}

findAndCleanLeftovers().catch(console.error);
