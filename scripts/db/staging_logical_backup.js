'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

let Pool;
try {
  Pool = require('pg').Pool;
} catch (_) {
  try {
    Pool = require('../node_modules/pg').Pool;
  } catch (__) {
    Pool = require(path.resolve(__dirname, '../node_modules/pg')).Pool;
  }
}

async function runStagingLogicalBackup() {
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'Staging Logical Backup', allowDestructive: false });

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('FATAL: STAGING_SUPABASE_DB_URL not found.');
    process.exit(1);
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.resolve(__dirname, `../../backups/staging_logical_${timestamp}`);
  const dataDir = path.join(backupDir, 'data');

  fs.mkdirSync(dataDir, { recursive: true });

  console.log(`\n===============================================================`);
  console.log(`DoctorNect Staging Logical Backup`);
  console.log(`Connection: ${maskConnectionString(dbUrl)}`);
  console.log(`Output Directory: ${backupDir}`);
  console.log(`===============================================================\n`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();

  const checksums = {};
  const rowCounts = {};
  const manifests = {
    timestamp: new Date().toISOString(),
    connection: maskConnectionString(dbUrl),
    tables: [],
    sequences: {},
    functions: [],
    policies: [],
    triggers: [],
  };

  try {
    // 1. Export Tables
    console.log('--- 1. Exporting Tables (public & private) ---');
    const tablesRes = await client.query(`
      SELECT table_schema, table_name
      FROM information_schema.tables
      WHERE table_schema IN ('public', 'private')
        AND table_type = 'BASE TABLE'
      ORDER BY table_schema, table_name;
    `);

    for (const row of tablesRes.rows) {
      const { table_schema, table_name } = row;
      const fullTableName = `"${table_schema}"."${table_name}"`;
      const fileName = `${table_schema}.${table_name}.ndjson`;
      const filePath = path.join(dataDir, fileName);

      const dataRes = await client.query(`SELECT * FROM ${fullTableName};`);
      const count = dataRes.rows.length;
      rowCounts[`${table_schema}.${table_name}`] = count;

      const lines = dataRes.rows.map(r => JSON.stringify(r));
      const content = lines.length > 0 ? lines.join('\n') + '\n' : '';
      fs.writeFileSync(filePath, content, 'utf8');

      const hash = crypto.createHash('sha256').update(content).digest('hex');
      checksums[fileName] = {
        schema: table_schema,
        table: table_name,
        rows: count,
        sha256: hash,
        bytes: Buffer.byteLength(content, 'utf8'),
      };

      manifests.tables.push({ schema: table_schema, table: table_name, rows: count, sha256: hash });
      console.log(`  Exported ${table_schema}.${table_name}: ${count} rows (SHA-256: ${hash.slice(0, 12)}...)`);
    }

    // 2. Export Sequences
    console.log('\n--- 2. Exporting Sequences ---');
    const seqRes = await client.query(`
      SELECT sequence_schema, sequence_name
      FROM information_schema.sequences
      WHERE sequence_schema IN ('public', 'private')
      ORDER BY sequence_schema, sequence_name;
    `);

    for (const row of seqRes.rows) {
      const { sequence_schema, sequence_name } = row;
      try {
        const valRes = await client.query(`SELECT last_value, is_called FROM "${sequence_schema}"."${sequence_name}";`);
        manifests.sequences[`${sequence_schema}.${sequence_name}`] = valRes.rows[0];
        console.log(`  Sequence ${sequence_schema}.${sequence_name}: last_value=${valRes.rows[0].last_value}, is_called=${valRes.rows[0].is_called}`);
      } catch (err) {
        console.warn(`  Warning: Could not read sequence ${sequence_schema}.${sequence_name}: ${err.message}`);
      }
    }

    // 3. Export Functions (Definitions)
    console.log('\n--- 3. Exporting Function Definitions ---');
    const funcRes = await client.query(`
      SELECT n.nspname AS schema_name, p.proname AS func_name, pg_get_functiondef(p.oid) AS definition
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname IN ('public', 'private')
      ORDER BY n.nspname, p.proname;
    `);

    for (const row of funcRes.rows) {
      manifests.functions.push({
        schema: row.schema_name,
        name: row.func_name,
        definition: row.definition,
      });
    }
    console.log(`  Exported ${funcRes.rows.length} function definitions.`);

    // 4. Export Policies
    console.log('\n--- 4. Exporting RLS Policies ---');
    const polRes = await client.query(`
      SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
      WHERE schemaname IN ('public', 'private')
      ORDER BY schemaname, tablename, policyname;
    `);
    manifests.policies = polRes.rows;
    console.log(`  Exported ${polRes.rows.length} RLS policies.`);

    // 5. Export Triggers
    console.log('\n--- 5. Exporting Triggers ---');
    const trigRes = await client.query(`
      SELECT trigger_schema, event_object_table, trigger_name, action_timing, event_manipulation, action_statement
      FROM information_schema.triggers
      WHERE trigger_schema IN ('public', 'private')
      ORDER BY trigger_schema, event_object_table, trigger_name;
    `);
    manifests.triggers = trigRes.rows;
    console.log(`  Exported ${trigRes.rows.length} triggers.`);

    // Write all manifest files
    fs.writeFileSync(path.join(backupDir, 'checksums.json'), JSON.stringify(checksums, null, 2), 'utf8');
    fs.writeFileSync(path.join(backupDir, 'row_counts.json'), JSON.stringify(rowCounts, null, 2), 'utf8');
    fs.writeFileSync(path.join(backupDir, 'manifest.json'), JSON.stringify(manifests, null, 2), 'utf8');
    fs.writeFileSync(path.join(backupDir, 'functions.json'), JSON.stringify(manifests.functions, null, 2), 'utf8');
    fs.writeFileSync(path.join(backupDir, 'policies.json'), JSON.stringify(manifests.policies, null, 2), 'utf8');
    fs.writeFileSync(path.join(backupDir, 'triggers.json'), JSON.stringify(manifests.triggers, null, 2), 'utf8');

    // 6. Compare with docs/ops/source_facts_preflight.json
    console.log('\n--- 6. Comparing with Preflight Facts ---');
    const preflightPath = path.resolve(__dirname, '../../docs/ops/source_facts_preflight.json');
    if (fs.existsSync(preflightPath)) {
      const preflight = JSON.parse(fs.readFileSync(preflightPath, 'utf8'));
      const preflightCounts = {};
      if (Array.isArray(preflight.rowCounts)) {
        for (const item of preflight.rowCounts) {
          preflightCounts[`${item.schema}.${item.table}`] = item.count;
        }
      }

      const comparisons = [];
      let totalLiveRows = 0;
      let totalPreflightRows = 0;
      let mismatches = 0;

      for (const [tableKey, liveCount] of Object.entries(rowCounts)) {
        totalLiveRows += liveCount;
        const preflightCount = preflightCounts[tableKey] !== undefined ? preflightCounts[tableKey] : 'N/A';
        if (preflightCount !== 'N/A') totalPreflightRows += preflightCount;

        const matches = preflightCount === 'N/A' || preflightCount === liveCount;
        if (!matches) mismatches++;

        if (liveCount > 0 || (preflightCount !== 'N/A' && preflightCount > 0)) {
          comparisons.push({
            Table: tableKey,
            LiveCount: liveCount,
            PreflightCount: preflightCount,
            Status: matches ? 'MATCH' : 'MISMATCH',
          });
        }
      }

      console.table(comparisons);
      console.log(`Total live rows across all tables: ${totalLiveRows}`);
      console.log(`Total preflight rows across compared tables: ${totalPreflightRows}`);
      console.log(`Mismatches: ${mismatches}`);

      if (mismatches > 0) {
        console.warn(`WARNING: ${mismatches} table row-count differences found compared to preflight facts.`);
      } else {
        console.log('✔ All non-empty tables match preflight facts perfectly.');
      }
    }

    console.log(`\n✔ Staging logical backup successfully saved to: ${backupDir}\n`);
    return { backupDir, checksums, rowCounts };
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  runStagingLogicalBackup().catch(err => {
    console.error('FATAL: Logical backup failed:', err);
    process.exit(1);
  });
}

module.exports = { runStagingLogicalBackup };

