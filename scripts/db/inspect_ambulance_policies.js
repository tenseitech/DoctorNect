'use strict';

const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const pool = new Pool({ connectionString: getEnv('STAGING_SUPABASE_DB_URL') });
  try {
    const polRes = await pool.query(`
      SELECT tablename, policyname, roles, cmd, qual, with_check 
      FROM pg_policies 
      WHERE tablename IN ('ambulance_broadcasts', 'ambulance_trip_contacts', 'ambulance_requests')
      ORDER BY tablename, cmd, policyname;
    `);
    console.log('=== POLICIES ===');
    for (const p of polRes.rows) {
      console.log(`Table: ${p.tablename} | Policy: ${p.policyname} | Roles: ${p.roles} | Cmd: ${p.cmd}`);
      console.log(`  QUAL: ${p.qual}`);
      console.log(`  WITH CHECK: ${p.with_check}\n`);
    }

    const colRes = await pool.query(`
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name IN ('ambulance_broadcasts', 'ambulance_trip_contacts')
      ORDER BY table_name, ordinal_position;
    `);
    console.log('=== COLUMNS ===');
    console.table(colRes.rows);

  } finally {
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

