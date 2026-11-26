'use strict';
const fs = require('fs');
const path = require('path');
const tables = new Set();
for (const f of fs.readdirSync(path.join('db/migrations')).filter((x) => x.endsWith('.sql'))) {
  const sql = fs.readFileSync(path.join('db/migrations', f), 'utf8');
  for (const m of sql.matchAll(/CREATE TABLE IF NOT EXISTS public\.([a-z_][a-z0-9_]*)/gi)) tables.add(m[1].toLowerCase());
  for (const m of sql.matchAll(/CREATE TABLE IF NOT EXISTS ([a-z_][a-z0-9_]*)\s*\(/gi)) {
    if (!['private', 'auth'].includes(m[1])) tables.add(m[1].toLowerCase());
  }
}
const blob04 = fs.readFileSync('db/rds_bootstrap/04_rds_runtime_grants.sql', 'utf8');
const missing = [...tables].filter((t) => !blob04.includes(`'${t}'`)).sort();
console.log(JSON.stringify({ migration_public_tables: tables.size, missing_from_04: missing }, null, 2));