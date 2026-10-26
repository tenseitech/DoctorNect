const { Client } = require('pg');
const fs = require('fs');

const content = fs.readFileSync('.env.migration', 'utf8');
const match = content.match(/PROD_SUPABASE_DB_URL=([^\r\n]+)/);
const client = new Client({ connectionString: match[1].trim(), ssl: { rejectUnauthorized: false } });

async function check() {
  await client.connect();
  const res = await client.query(`
    SELECT conname, pg_get_constraintdef(oid) as def
    FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass;
  `);
  console.log('Constraints on public.users:');
  res.rows.forEach(r => console.log(' ', r.conname, ':', r.def));
  await client.end();
}

check().catch(console.error);
