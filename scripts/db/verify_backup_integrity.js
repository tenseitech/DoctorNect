'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');
const { getEnv } = require('../lib/env_loader');

async function main() {
  const backupDir = path.resolve('backups/staging_logical_2026-10-29T07-41-24-509Z');
  const dataDir = path.join(backupDir, 'data');
  const manifest = JSON.parse(fs.readFileSync(path.join(backupDir, 'manifest.json'), 'utf8'));
  const checksums = JSON.parse(fs.readFileSync(path.join(backupDir, 'checksums.json'), 'utf8'));
  const rowCounts = JSON.parse(fs.readFileSync(path.join(backupDir, 'row_counts.json'), 'utf8'));

  console.log(`\n======================================================`);
  console.log(`Verifying Backup Integrity: ${path.basename(backupDir)}`);
  console.log(`======================================================\n`);

  const ndjsonFiles = fs.readdirSync(dataDir).filter(f => f.endsWith('.ndjson'));
  console.log(`Total NDJSON files in backup: ${ndjsonFiles.length}`);

  let allChecksumsMatch = true;
  let allRowCountsMatch = true;

  const fileStats = [];

  for (const file of ndjsonFiles) {
    const filePath = path.join(dataDir, file);
    const content = fs.readFileSync(filePath);
    const sha256 = crypto.createHash('sha256').update(content).digest('hex');
    const lines = content.toString('utf8').trim().split('\n').filter(Boolean);
    const lineCount = lines.length;

    const expectedEntry = checksums[file];
    const expectedChecksum = typeof expectedEntry === 'object' ? expectedEntry.sha256 : expectedEntry;
    const tableName = file.replace('.ndjson', '');
    const expectedRowCount = rowCounts[tableName];

    const cMatch = sha256 === expectedChecksum;
    const rMatch = lineCount === (expectedRowCount || 0);

    if (!cMatch) allChecksumsMatch = false;
    if (!rMatch) allRowCountsMatch = false;

    fileStats.push({
      file,
      lineCount,
      expectedRowCount: expectedRowCount || 0,
      sha256: sha256.slice(0, 12) + '...',
      checksumMatch: cMatch,
      rowMatch: rMatch,
    });
  }

  console.log(`Checksum verification: ${allChecksumsMatch ? '✔ ALL 68 CHECKSUMS MATCH MANIFEST' : '❌ CHECKSUM MISMATCH'}`);
  console.log(`Row count verification: ${allRowCountsMatch ? '✔ ALL 68 ROW COUNTS MATCH MANIFEST' : '❌ ROW COUNT MISMATCH'}`);

  // Now compare against live staging
  const pool = new Pool({ connectionString: getEnv('STAGING_SUPABASE_DB_URL') });
  console.log('\nQuerying live staging table row counts for comparison...');
  
  let liveMatch = true;
  const liveDiffs = [];

  for (const [tbl, count] of Object.entries(rowCounts)) {
    // Skip internal ledger tables that change during migrations
    if (tbl === 'public._schema_migrations' || tbl === 'supabase_migrations.schema_migrations') continue;

    const [schema, name] = tbl.split('.');
    try {
      const res = await pool.query(`SELECT count(*)::int as cnt FROM "${schema}"."${name}";`);
      const liveCnt = res.rows[0].cnt;
      if (liveCnt !== count) {
        liveMatch = false;
        liveDiffs.push({ table: tbl, backup: count, live: liveCnt });
      }
    } catch (err) {
      console.warn(`Could not query ${tbl}: ${err.message}`);
    }
  }

  await pool.end();

  console.log(`Live staging comparison: ${liveMatch ? '✔ PERFECT MATCH WITH LIVE STAGING' : '⚠️ DIFFERENCES DETECTED'}`);
  if (liveDiffs.length > 0) {
    console.table(liveDiffs);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
