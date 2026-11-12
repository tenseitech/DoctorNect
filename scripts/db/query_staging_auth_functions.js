'use strict';

const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl });
  try {
    const res = await pool.query(`
      SELECT 
        p.proname,
        pg_get_function_identity_arguments(p.oid) as args,
        pg_get_function_result(p.oid) as result_type,
        p.prosecdef as is_secdef,
        p.provolatile as volatility,
        pg_get_functiondef(p.oid) as def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'auth' AND p.proname IN ('jwt', 'uid', 'role')
      ORDER BY p.proname;
    `);

    for (const row of res.rows) {
      console.log(`=== auth.${row.proname}(${row.args}) -> ${row.result_type} (secdef: ${row.is_secdef}, provolatile: ${row.volatility}) ===`);
      console.log(row.def);
      console.log('\n');
    }

    // Also check privileges and roles in staging auth schema
    console.log('=== Privileges on auth schema functions ===');
    const privs = await pool.query(`
      SELECT 
        p.proname,
        r.rolname,
        has_function_privilege(r.rolname, p.oid, 'execute') as can_execute
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN (SELECT unnest(ARRAY['anon', 'authenticated', 'service_role', 'postgres', 'public']) as rolname) r
      WHERE n.nspname = 'auth' AND p.proname IN ('jwt', 'uid', 'role')
      ORDER BY p.proname, r.rolname;
    `);
    console.table(privs.rows);

  } finally {
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

