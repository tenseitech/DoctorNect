'use strict';

const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const pool = new Pool({ connectionString: getEnv('STAGING_SUPABASE_DB_URL') });
  try {
    const res = await pool.query(`
      SELECT table_name, column_name, data_type, column_default, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public' 
        AND table_name IN ('doctors', 'labs', 'medical_stores', 'ambulances')
      ORDER BY table_name, ordinal_position;
    `);
    console.table(res.rows);

    // Also inspect current RLS policies for INSERT and UPDATE
    const polRes = await pool.query(`
      SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename IN ('doctors', 'labs', 'medical_stores', 'ambulances')
      ORDER BY tablename, cmd, policyname;
    `);
    console.log('\n=== CURRENT RLS POLICIES ===');
    for (const p of polRes.rows) {
      console.log(`Table: ${p.tablename} | Cmd: ${p.cmd} | Policy: ${p.policyname} | Roles: ${p.roles}`);
      console.log(`  QUAL: ${p.qual}`);
      console.log(`  WITH CHECK: ${p.with_check}`);
    }

    // Also inspect triggers on these tables
    const trgRes = await pool.query(`
      SELECT event_object_table, trigger_name, event_manipulation, action_statement, action_timing
      FROM information_schema.triggers
      WHERE event_object_schema = 'public'
        AND event_object_table IN ('doctors', 'labs', 'medical_stores', 'ambulances')
      ORDER BY event_object_table, trigger_name;
    `);
    console.log('\n=== CURRENT TRIGGERS ===');
    console.table(trgRes.rows);

  } finally {
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

