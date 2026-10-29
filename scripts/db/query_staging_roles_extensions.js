'use strict';

const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl });
  try {
    console.log('=== ROLES ON STAGING ===');
    const roles = await pool.query(`
      SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin
      FROM pg_roles
      WHERE rolname IN ('anon', 'authenticated', 'service_role', 'authenticator', 'postgres', 'supabase_admin')
      ORDER BY rolname;
    `);
    console.table(roles.rows);

    console.log('\n=== ROLE MEMBERSHIPS ===');
    const mems = await pool.query(`
      SELECT r.rolname AS role, m.rolname AS member
      FROM pg_auth_members am
      JOIN pg_roles r ON r.oid = am.roleid
      JOIN pg_roles m ON m.oid = am.member
      WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
         OR m.rolname IN ('authenticator', 'anon', 'authenticated', 'service_role')
      ORDER BY r.rolname, m.rolname;
    `);
    console.table(mems.rows);

    console.log('\n=== EXTENSIONS ON STAGING ===');
    const exts = await pool.query(`
      SELECT extname, extversion
      FROM pg_extension
      ORDER BY extname;
    `);
    console.table(exts.rows);

    console.log('\n=== DEFAULT PRIVILEGES IN PUBLIC ===');
    const defAcl = await pool.query(`
      SELECT defaclrole::regrole as role, defaclnamespace::regnamespace as schema, defaclobjtype, defaclacl
      FROM pg_default_acl;
    `);
    console.table(defAcl.rows);

  } finally {
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

