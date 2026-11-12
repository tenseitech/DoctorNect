'use strict';

const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const c = new Client({ connectionString: getEnv('STAGING_SUPABASE_DB_URL') });
  await c.connect();

  const res = await c.query(`
    SELECT trigger_name, event_manipulation, action_statement
    FROM information_schema.triggers
    WHERE event_object_table = 'users'
    ORDER BY trigger_name;
  `);
  console.table(res.rows);

  await c.end();
}

main().catch(console.error);
