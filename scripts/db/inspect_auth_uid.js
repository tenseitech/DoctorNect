'use strict';

const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL');
  const client = new Client({ connectionString: stagingUrl });
  await client.connect();

  const res = await client.query(`SELECT pg_get_functiondef('auth.uid'::regproc) AS def;`);
  console.log('=== STAGING auth.uid() DEFINITION ===');
  console.log(res.rows[0].def);

  const resRole = await client.query(`SELECT pg_get_functiondef('auth.role'::regproc) AS def;`);
  console.log('\n=== STAGING auth.role() DEFINITION ===');
  console.log(resRole.rows[0].def);

  const resJwt = await client.query(`SELECT pg_get_functiondef('auth.jwt'::regproc) AS def;`);
  console.log('\n=== STAGING auth.jwt() DEFINITION ===');
  console.log(resJwt.rows[0].def);

  const resUsers = await client.query(`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_schema = 'auth' AND table_name = 'users'
    ORDER BY ordinal_position;
  `);
  console.log('\n=== STAGING auth.users COLUMNS ===');
  console.table(resUsers.rows);

  await client.end();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
