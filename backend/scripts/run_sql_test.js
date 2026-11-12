const fs = require('fs');
const path = require('path');
const { Client } = require(path.join(__dirname, '../node_modules/pg'));

const connectionString = process.env.SUPABASE_DB_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

async function runTest(testFile) {
  const filePath = path.resolve(__dirname, '../supabase/tests', testFile);
  console.log(`\n================================================================`);
  console.log(`RUNNING SQL TEST: ${testFile}`);
  console.log(`================================================================`);

  const sql = fs.readFileSync(filePath, 'utf8');
  const client = new Client({ connectionString });
  await client.connect();

  try {
    const res = await client.query(sql);
    if (Array.isArray(res)) {
      for (const r of res) {
        if (r.command === 'SELECT' && r.rows.length > 0) {
          console.table(r.rows);
        } else if (r.command) {
          // command result
        }
      }
    } else if (res.command === 'SELECT') {
      console.table(res.rows);
    }
    console.log(`\nSUCCESS: ${testFile} passed with zero errors.`);
  } catch (err) {
    console.error(`\nFAIL: ${testFile} encountered error:`, err.message);
    if (err.position) console.error(`Error at position: ${err.position}`);
    process.exit(1);
  } finally {
    await client.end();
  }
}

const target = process.argv[2] || 'rls_policies_test.sql';
runTest(target).catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
