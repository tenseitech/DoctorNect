const { Client } = require('pg');
const { loadRootEnv } = require('./lib/bootstrap_root_env');
const { getEnv } = require('./lib/env_loader');

loadRootEnv();
const dbUrl = getEnv('PROD_SUPABASE_DB_URL') || getEnv('STAGING_SUPABASE_DB_URL');
if (!dbUrl) {
  console.error('PROD_SUPABASE_DB_URL or STAGING_SUPABASE_DB_URL missing in repo root .env');
  process.exit(1);
}
const client = new Client({ connectionString: dbUrl.trim(), ssl: { rejectUnauthorized: false } });

async function check() {
  await client.connect();
  const res = await client.query(`
    SELECT table_schema, table_name, table_type
    FROM information_schema.tables
    WHERE table_name IN ('doctor_private', 'ambulance_private_settings');
  `);
  const cols = await client.query(`
    SELECT table_name, column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name IN ('doctor_private', 'ambulance_private_settings')
    ORDER BY table_name, ordinal_position;
  `);
  console.log('Columns:');
  console.table(cols.rows);

  const pols = await client.query(`
    SELECT schemaname, tablename, policyname, roles, cmd, qual
    FROM pg_policies
    WHERE tablename IN ('doctor_private', 'ambulance_private_settings');
  `);
  console.log('Policies:');
  console.table(pols.rows);
  await client.end();
}

check().catch(console.error);
