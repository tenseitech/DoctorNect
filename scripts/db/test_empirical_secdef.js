'use strict';

const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

async function runEmpiricalProof() {
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'Empirical Guard Test' });
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  console.log(`Target: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();

  try {
    console.log('--- START EMPIRICAL GUARD PROOF (TRANSACTION ISOLATED) ---');
    await client.query('BEGIN');

    // Create a temporary SECURITY DEFINER function in public (will be rolled back)
    await client.query(`
      CREATE OR REPLACE FUNCTION public.tmp_secdef_guard_proof()
      RETURNS TABLE (
        v_current_user text,
        v_session_user text,
        v_current_setting_role text,
        v_jwt_role text
      )
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = ''
      AS $$
      BEGIN
        RETURN QUERY SELECT
          current_user::text,
          session_user::text,
          current_setting('role', true)::text,
          (auth.jwt() ->> 'role')::text;
      END;
      $$;
      GRANT EXECUTE ON FUNCTION public.tmp_secdef_guard_proof() TO authenticated, anon;
    `);

    // Switch to authenticated with gateway-shaped claims
    await client.query(`SET LOCAL ROLE authenticated;`);
    const claims = JSON.stringify({
      role: 'authenticated',
      sub: 'emp_proof_sub_123',
      iss: 'doctornect-gateway',
      app_role: 'patient',
      verified: true
    });
    await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);

    // Call the SECURITY DEFINER function
    const res = await client.query(`SELECT * FROM public.tmp_secdef_guard_proof();`);
    console.log('\nQuery Result inside SECURITY DEFINER under authenticated:');
    console.table(res.rows);

    const row = res.rows[0];
    console.log('Empirical inspection:');
    console.log(`  current_user:               "${row.v_current_user}" (EXPECTED: postgres/supabase_admin because secdef switches to owner)`);
    console.log(`  session_user:               "${row.v_session_user}" (Connection user)`);
    console.log(`  current_setting('role'):    "${row.v_current_setting_role}" (Shows the SET LOCAL ROLE value!)`);
    console.log(`  auth.jwt()->>'role':        "${row.v_jwt_role}" (JWT claim role)`);

    // Also inspect outside secdef function
    const outsideRes = await client.query(`
      SELECT current_user::text, session_user::text, current_setting('role', true)::text, (auth.jwt() ->> 'role')::text;
    `);
    console.log('\nQuery Result outside SECURITY DEFINER under authenticated:');
    console.table(outsideRes.rows);

    await client.query('ROLLBACK');
    console.log('\n--- TRANSACTION ROLLED BACK CLEANLY ---');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Empirical proof error:', err);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

runEmpiricalProof();

