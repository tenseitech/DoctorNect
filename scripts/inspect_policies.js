const fs = require('fs');
const path = require('path');
const { Client } = require(path.join(__dirname, '../backend/node_modules/pg'));

function loadDbUrl() {
  const envPath = path.join(__dirname, '../.env.migration');
  const lines = fs.readFileSync(envPath, 'utf8').split('\n');
  for (const line of lines) {
    const idx = line.indexOf('=');
    if (idx !== -1) {
      const key = line.slice(0, idx).trim();
      const val = line.slice(idx + 1).trim();
      if (key === 'STAGING_SUPABASE_DB_URL' || key === 'SUPABASE_DB_URL') {
        return val;
      }
    }
  }
  throw new Error('No DB URL');
}

async function inspectPolicies() {
  const client = new Client({ connectionString: loadDbUrl(), ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const res = await client.query(`
      SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
      WHERE schemaname = 'public'
      ORDER BY tablename, policyname;
    `);
    fs.writeFileSync(path.join(__dirname, 'all_table_policies.json'), JSON.stringify(res.rows, null, 2));
    console.log('Saved', res.rows.length, 'policies to scripts/all_table_policies.json');
  } finally {
    await client.end();
  }
}

inspectPolicies().catch(err => {
  console.error(err);
  process.exit(1);
});
