'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('../node_modules/pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl });

  console.log('================================================================');
  console.log('DoctorNect: Ledger Verification & Applied Migration Proof');
  console.log('================================================================');

  const colRes = await pool.query(`
    SELECT table_schema, table_name, column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name IN ('schema_migrations', '_schema_migrations')
    ORDER BY table_schema, table_name, ordinal_position
  `);
  console.log('\n--- Migration Tables Schema ---');
  console.table(colRes.rows);

  console.log('\n--- public._schema_migrations (20261026 to 20261102) ---');
  const pubRes = await pool.query(`
    SELECT version, name, applied_at, checksum 
    FROM public._schema_migrations 
    WHERE version >= '20261026000001' 
    ORDER BY version ASC
  `);
  console.table(pubRes.rows);

  console.log('\n--- supabase_migrations.schema_migrations (20261026 to 20261102) ---');
  const supaRes = await pool.query(`
    SELECT version, name, statements 
    FROM supabase_migrations.schema_migrations 
    WHERE version >= '20261026000001' 
    ORDER BY version ASC
  `);
  for (const row of supaRes.rows) {
    console.log(`Version: ${row.version} | Name: ${row.name} | Stmt Count: ${row.statements ? row.statements.length : 0}`);
  }

  // Deep comparison of 20261101000001
  const diskPath = path.resolve(__dirname, '../../db/migrations/20261101000001_domain_allowlist_and_reviews_guard.sql');
  const diskBuf = fs.readFileSync(diskPath);
  const diskText = diskBuf.toString('utf8');
  const diskNormalizedLF = diskText.replace(/\r\n/g, '\n');
  const diskNormalizedSha256 = crypto.createHash('sha256').update(diskNormalizedLF, 'utf8').digest('hex');
  const diskRawSha256 = crypto.createHash('sha256').update(diskBuf).digest('hex');

  console.log('\n--- 20261101000001 Disk File Metrics ---');
  console.log(`Path: ${diskPath}`);
  console.log(`Raw byte length: ${diskBuf.length}`);
  console.log(`LF normalized byte length: ${Buffer.byteLength(diskNormalizedLF, 'utf8')}`);
  console.log(`Raw SHA-256: ${diskRawSha256}`);
  console.log(`LF Normalized SHA-256: ${diskNormalizedSha256}`);

  const row1101 = supaRes.rows.find(r => r.version === '20261101000001');
  const pub1101 = pubRes.rows.find(r => r.version === '20261101000001');

  console.log('\n--- 20261101000001 Staging Ledger Verification ---');
  if (pub1101) {
    console.log(`public._schema_migrations recorded checksum: ${pub1101.checksum}`);
    console.log(`Checksum matches disk LF SHA-256: ${pub1101.checksum === diskNormalizedSha256}`);
  }

  if (row1101 && row1101.statements) {
    console.log(`supabase_migrations statement count: ${row1101.statements.length}`);
    const appliedContent = row1101.statements.join(';\n');
    const appliedLF = appliedContent.replace(/\r\n/g, '\n');
    const appliedSha256 = crypto.createHash('sha256').update(appliedLF, 'utf8').digest('hex');
    console.log(`Applied statements joined byte length: ${Buffer.byteLength(appliedLF, 'utf8')}`);
    console.log(`Applied statements SHA-256: ${appliedSha256}`);
    
    // Compare statement texts
    console.log(`Applied statement exactly equals disk content: ${appliedLF.trim() === diskNormalizedLF.trim()}`);
  }

  await pool.end();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
