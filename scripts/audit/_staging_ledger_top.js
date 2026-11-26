#!/usr/bin/env node
'use strict';
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { stagingPgSsl } = require('../lib/staging_pg_ssl');

async function main() {
  const client = new Client({
    connectionString: getEnv('STAGING_SUPABASE_DB_URL'),
    ssl: stagingPgSsl(),
  });
  await client.connect();
  const r = await client.query(`
    SELECT version, name, checksum, applied_at
    FROM public._schema_migrations
    ORDER BY version DESC
    LIMIT 5`);
  console.log(JSON.stringify(r.rows, null, 2));
  const mx = await client.query(`SELECT max(version) AS max_version, count(*)::int AS n FROM public._schema_migrations`);
  console.log('SUMMARY', JSON.stringify(mx.rows[0]));
  await client.end();
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});