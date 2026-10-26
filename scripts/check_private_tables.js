const { Client } = require('pg');
const fs = require('fs');

const content = fs.readFileSync('.env.migration', 'utf8');
const match = content.match(/PROD_SUPABASE_DB_URL=([^\r\n]+)/);
const client = new Client({ connectionString: match[1].trim(), ssl: { rejectUnauthorized: false } });

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
