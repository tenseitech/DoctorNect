'use strict';

const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl });
  try {
    const res = await pool.query(`
      SELECT 
        r.rolname,
        has_function_privilege(r.rolname, 'public.get_ambulance_trip_contact(varchar)', 'execute') as can_execute
      FROM pg_roles r
      WHERE r.rolname IN ('authenticated', 'anon', 'service_role', 'postgres')
      ORDER BY r.rolname;
    `);
    console.table(res.rows);
  } finally {
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
