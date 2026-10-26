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

async function inspectColumns() {
  const client = new Client({ connectionString: loadDbUrl(), ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const res = await client.query(`
      SELECT table_name, column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public'
      ORDER BY table_name, ordinal_position;
    `);
    const tables = {};
    for (const r of res.rows) {
      if (!tables[r.table_name]) tables[r.table_name] = [];
      tables[r.table_name].push({
        col: r.column_name,
        type: r.data_type,
        nullable: r.is_nullable === 'YES',
        default: r.column_default
      });
    }
    fs.writeFileSync(path.join(__dirname, 'table_columns.json'), JSON.stringify(tables, null, 2));
    console.log('Saved table columns for', Object.keys(tables).length, 'tables.');
  } finally {
    await client.end();
  }
}

inspectColumns().catch(console.error);
