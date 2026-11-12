'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');
const { assertSessionCapableConnection, SESSION_CONNECTION_DOC } = require('../lib/db_connection_guard');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

let parse;
try {
  parse = require('libpg-query').parse;
} catch (_) {
  try {
    parse = require(path.resolve(__dirname, '../../node_modules/libpg-query')).parse;
  } catch (__) {
    parse = require(path.resolve(__dirname, '../node_modules/libpg-query')).parse;
  }
}

async function splitSqlStatements(sqlText) {
  const buf = Buffer.from(sqlText, 'utf8');
  const parsed = await parse(sqlText);
  const statements = [];

  for (let i = 0; i < parsed.stmts.length; i++) {
    const item = parsed.stmts[i];
    const loc = item.stmt_location || 0;
    let len = item.stmt_len;

    if (!len || len === 0) {
      const nextLoc = i + 1 < parsed.stmts.length ? (parsed.stmts[i + 1].stmt_location || buf.length) : buf.length;
      len = nextLoc - loc;
    }

    const stmtBuf = buf.subarray(loc, loc + len);
    const stmtSql = stmtBuf.toString('utf8');

    const prefix = buf.subarray(0, loc).toString('utf8');
    const line = prefix.split('\n').length;

    statements.push({
      sql: stmtSql,
      line,
    });
  }

  return statements;
}

const {
  computeChecksum,
  ledgerChecksumMatches,
} = require('../lib/migration_checksum');

function buildStagingPoolConfig(dbUrl) {
  const config = { connectionString: dbUrl };
  try {
    const parsed = new URL(dbUrl.replace(/^postgres:\/\//i, 'postgresql://'));
    const sslmode = (parsed.searchParams.get('sslmode') || '').toLowerCase();
    if (sslmode === 'require' || sslmode === 'verify-ca' || sslmode === 'verify-full' || parsed.hostname.includes('supabase')) {
      config.ssl = { rejectUnauthorized: false };
    }
  } catch (_) {
    config.ssl = { rejectUnauthorized: false };
  }
  return config;
}

function listPendingMigrationFiles(appliedMap) {
  const migrationsDir = path.resolve('db/migrations');
  const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  return files.filter((f) => !appliedMap.has(f.split('_')[0]));
}

async function runMigrations() {
  const args = process.argv.slice(2);
  const isDryRun =
    args.includes('--dry-run') ||
    args.includes('--dry-run-all') ||
    !args.includes('--execute');
  const isDryRunAll = args.includes('--dry-run-all');
  const targetArg = args.find(a => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

  console.log(`\n======================================================`);
  console.log(`DoctorNect Migration Runner (Target: ${target.toUpperCase()}${isDryRun ? ' [DRY-RUN]' : ''})`);
  console.log(`======================================================`);
  console.log(`Mode: ${isDryRunAll ? '--dry-run-all (statement test + rollback)' : isDryRun ? 'dry-run (list only)' : '--execute (will commit)'}`);
  console.log(`Env files: repo root .env only (scripts/lib/env_loader.js)`);
  const stagingUrlKey = getEnv('STAGING_SUPABASE_DB_URL') ? 'STAGING_SUPABASE_DB_URL' : (getEnv('PROD_SUPABASE_DB_URL') ? 'PROD_SUPABASE_DB_URL' : null);
  if (target === 'staging') {
    console.log(`Staging DB URL variable: ${stagingUrlKey || '[MISSING — set STAGING_SUPABASE_DB_URL in root .env]'}`);
  }

  bootstrapMutatingScript('scripts/db/migrate.js');

  let dbUrl;
  let poolConfig;
  let targetHostLabel = '';

  if (target === 'staging') {
    dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    if (!dbUrl) {
      console.error('\n[FATAL] STAGING_SUPABASE_DB_URL is not set. Cannot connect.');
      process.exit(1);
    }
    const targetHost = getHostFingerprint(dbUrl);
    targetHostLabel = targetHost;
    const guard = assertDatabaseGuard({ targetKind: 'staging', operationName: 'Run Migrations', allowDestructive: !isDryRun && !isDryRunAll, targetHost });
    console.log(`Target host (staging): ${guard.host}`);
    poolConfig = buildStagingPoolConfig(dbUrl);
  } else if (target === 'replay' || target === 'replay_check') {
    const rawReplayUrl = getEnv('REPLAY_DB_URL');
    if (!rawReplayUrl) {
      console.error('\n[GUARD ABORT] REPLAY_DB_URL is not configured.');
      process.exit(1);
    }
    const parsed = new URL(rawReplayUrl);
    parsed.pathname = '/replay_check';
    const replayUser = getEnv('REPLAY_USER') || 'rds_master';
    if (replayUser) {
      parsed.username = replayUser;
    }
    dbUrl = parsed.toString();
    const targetHost = getHostFingerprint(dbUrl);
    assertDatabaseGuard({ targetKind: 'replay', operationName: `Run Migrations on ${target}`, allowDestructive: true, targetHost });
    poolConfig = { connectionString: dbUrl };
  } else if (target === 'rehearsal' || target === 'production') {
    const host = getEnv('PROD_RDS_HOST');
    assertDatabaseGuard({ targetKind: 'production', operationName: `Run Migrations on ${target}`, allowDestructive: false, targetHost: host });
    const database = target === 'rehearsal' ? 'doctornect_rehearsal' : (getEnv('PROD_RDS_DB') || 'doctornect');
    poolConfig = buildRdsPoolConfig({ database });
    dbUrl = maskRdsTarget(poolConfig);
    targetHostLabel = poolConfig.logicalHost;
  } else {
    console.error(`Invalid target: ${target}. Must be staging, rehearsal, or production.`);
    process.exit(1);
  }

  assertSessionCapableConnection(dbUrl, 'migrate.js');
  console.log(`Target Connection: ${maskConnectionString(dbUrl)}`);
  console.log(SESSION_CONNECTION_DOC);

  let pool;
  let client;
  try {
    pool = new Pool(poolConfig);
    client = await pool.connect();
    console.log('✔ Database connection established.');
  } catch (connErr) {
    console.error(`\n[FATAL] Could not connect to database (${targetHostLabel || target}): ${connErr.code || ''} ${connErr.message}`);
    console.error('Check STAGING_SUPABASE_DB_URL uses session pooler port 5432 and network access.');
    process.exit(1);
  }

  try {
    // 1. Ensure migrations ledger exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS public._schema_migrations (
        version text PRIMARY KEY,
        name text NOT NULL,
        checksum text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      );
    `);

    // Sync from legacy supabase_migrations if present (e.g. on Supabase staging)
    let supabaseMigExists = false;
    try {
      const hasSupabaseMig = await client.query(`
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations';
      `);
      if (hasSupabaseMig.rows && hasSupabaseMig.rows.length > 0) {
        supabaseMigExists = true;
        await client.query(`
          INSERT INTO public._schema_migrations (version, name, checksum)
          SELECT version, COALESCE(name, version), 'legacy_supabase'
          FROM supabase_migrations.schema_migrations
          WHERE version <> '20261104000001'
          ON CONFLICT (version) DO NOTHING;
        `);
      }
    } catch (_) {}

    // 2. Fetch applied migrations
    const appliedRes = await client.query(`SELECT version, checksum FROM public._schema_migrations ORDER BY version;`);
    const appliedMap = new Map();
    for (const row of appliedRes.rows) {
      appliedMap.set(row.version, row.checksum);
    }
    console.log(`Existing Applied Migrations in Ledger: ${appliedMap.size}`);

    // 3. Scan migrations directory
    const migrationsDir = path.resolve('db/migrations');
    const overridesDir = path.resolve('db/rds_overrides');
    const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
    const pendingFilesPreview = listPendingMigrationFiles(appliedMap);
    console.log(`\nPending migration files (${pendingFilesPreview.length}):`);
    if (pendingFilesPreview.length === 0) {
      console.log('  (none — schema is at head)');
    } else {
      for (const f of pendingFilesPreview) {
        console.log(`  - ${f}`);
      }
    }

    // Check if pg_cron extension is available on this PostgreSQL instance
    const hasCronExtRes = await client.query(`
      SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron';
    `);
    const lacksPgCron = hasCronExtRes.rows.length === 0;

    let pendingCount = 0;
    let appliedThisRun = 0;

    if (isDryRunAll) {
      console.log(`\n--- EXECUTING --dry-run-all (Statement-level testing inside single rollback transaction) ---`);
      const pendingFiles = files.filter(f => !appliedMap.has(f.split('_')[0]));
      console.log(`Found ${pendingFiles.length} pending migration files: ${pendingFiles.join(', ')}`);

      await client.query('BEGIN');
      const allErrors = [];
      let totalStatements = 0;

      for (const file of pendingFiles) {
        const baseSqlPath = path.join(migrationsDir, file);
        const overrideSqlPath = path.join(overridesDir, file);
        const useOverride = (target === 'production' || target === 'rehearsal' || target === 'replay' || target === 'replay_check') && fs.existsSync(overrideSqlPath);
        const activeFilePath = useOverride ? overrideSqlPath : baseSqlPath;
        let sqlContent = fs.readFileSync(activeFilePath, 'utf8');
        if (lacksPgCron && file === '20260923000003_doctornect_cron.sql') {
          sqlContent = sqlContent.replace(/CREATE EXTENSION IF NOT EXISTS pg_cron;/g, '-- [NO PG_CRON AVAILABLE] skipped extension creation');
        }

        console.log(`\nParsing & testing statements in ${file}...`);
        const stmts = await splitSqlStatements(sqlContent);
        totalStatements += stmts.length;
        console.log(`  Extracted ${stmts.length} top-level AST statements.`);

        for (const item of stmts) {
          await client.query('SAVEPOINT sp_stmt;');
          try {
            await client.query(item.sql);
            await client.query('RELEASE SAVEPOINT sp_stmt;');
          } catch (err) {
            allErrors.push({
              file,
              line: item.line,
              sqlstate: err.code || 'UNKNOWN',
              message: err.message,
              snippet: item.sql.trim().replace(/\s+/g, ' ').slice(0, 90),
            });
            await client.query('ROLLBACK TO SAVEPOINT sp_stmt;');
          }
        }
      }

      await client.query('ROLLBACK');
      console.log(`\n✔ Transaction ROLLED BACK. Nothing applied to database.`);
      console.log(`\n=== DRY-RUN-ALL SUMMARY ===`);
      console.log(`Files tested: ${pendingFiles.length} | Statements tested: ${totalStatements} | Errors found: ${allErrors.length}`);

      if (allErrors.length > 0) {
        console.log('\n--- STATEMENT ERRORS DETECTED ---');
        console.table(allErrors.map((e, idx) => ({
          '#': idx + 1,
          File: e.file,
          Line: e.line,
          SQLSTATE: e.sqlstate,
          Message: e.message,
          Statement: e.snippet,
        })));
        throw new Error(`dry-run-all failed with ${allErrors.length} statement error(s)`);
      } else {
        console.log('\n✔ ZERO ERRORS DETECTED across all pending migration statements.');
      }

      return { pendingCount: pendingFiles.length, totalStatements, errors: allErrors };
    }

    for (const file of files) {
      const version = file.split('_')[0];
      const baseSqlPath = path.join(migrationsDir, file);
      const overrideSqlPath = path.join(overridesDir, file);

      // In RDS targets, use override file if present
      const useOverride = (target === 'production' || target === 'rehearsal' || target === 'replay' || target === 'replay_check') && fs.existsSync(overrideSqlPath);
      const activeFilePath = useOverride ? overrideSqlPath : baseSqlPath;
      const sqlContent = fs.readFileSync(activeFilePath, 'utf8');
      const checksum = computeChecksum(sqlContent);

      if (appliedMap.has(version)) {
        const recordedChecksum = appliedMap.get(version);
        if (!ledgerChecksumMatches(sqlContent, recordedChecksum)) {
          console.error(`\n[FATAL CHECKSUM MISMATCH] Migration ${file} (version ${version}) has been altered!`);
          console.error(`Recorded checksum: ${recordedChecksum}`);
          console.error(`Current checksum:  ${checksum}`);
          console.error('Altering already applied migrations violates database integrity.');
          process.exit(1);
        }
        continue;
      }

      pendingCount++;
      console.log(`\n[Pending Migration] -> ${file} (checksum: ${checksum.slice(0, 8)}...) ${useOverride ? '[RDS OVERRIDE]' : ''}`);

      if (isDryRun) {
        console.log(`[DRY-RUN] Would apply: ${file}`);
        continue;
      }

      // Execute in a transaction
      console.log(`Applying ${file}...`);
      await applySingleMigration({ client, version, file, sqlContent, checksum, supabaseMigExists, lacksPgCron });
      appliedThisRun++;
    }

    if (!isDryRun) {
      // Reload PostgREST schema cache
      try {
        await client.query(`NOTIFY pgrst, 'reload schema';`);
        console.log(`✔ Sent NOTIFY pgrst, 'reload schema'`);
      } catch (_) {}
    }

    const finalLedger = await client.query(
      `SELECT version, name, applied_at FROM public._schema_migrations ORDER BY version DESC LIMIT 15;`,
    );
    console.log(`\n=== MIGRATION RUN SUMMARY ===`);
    console.log(`Target: ${target} | Host: ${targetHostLabel || '(see connection mask above)'}`);
    console.log(`Pending seen this run: ${pendingCount} | Applied this run: ${isDryRun ? 0 : appliedThisRun}`);
    console.log(`Ledger total versions: ${appliedMap.size + (isDryRun ? 0 : appliedThisRun)}`);
    if (finalLedger.rows.length) {
      console.log('\nMost recent _schema_migrations rows:');
      for (const row of finalLedger.rows) {
        console.log(`  ${row.version}  ${row.name}  @ ${row.applied_at}`);
      }
    }
    console.log(`\nMigration run completed.`);

  } finally {
    client.release();
    await pool.end();
  }
}

async function applySingleMigration({ client, version, file, sqlContent, checksum, supabaseMigExists = false, lacksPgCron = false }) {
  await client.query('BEGIN');
  try {
    let sqlToExecute = sqlContent;
    if (lacksPgCron && file === '20260923000003_doctornect_cron.sql') {
      sqlToExecute = sqlToExecute.replace(/CREATE EXTENSION IF NOT EXISTS pg_cron;/g, () => `
        CREATE SCHEMA IF NOT EXISTS cron;
        CREATE TABLE IF NOT EXISTS cron.job (jobid bigint, schedule text, command text, nodename text, nodeport integer, database text, username text, active boolean, jobname text);
        CREATE OR REPLACE FUNCTION cron.schedule(text, text, text) RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint; $$;
        CREATE OR REPLACE FUNCTION cron.schedule(text, text) RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint; $$;
      `);
    }
    await client.query(sqlToExecute);
    await client.query(
      `INSERT INTO public._schema_migrations (version, name, checksum) VALUES ($1, $2, $3);`,
      [version, file, checksum]
    );

    if (supabaseMigExists) {
      await client.query('SAVEPOINT sp_supamig;');
      try {
        await client.query(
          `INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ($1, $2, ARRAY[$3]::text[]) ON CONFLICT DO NOTHING;`,
          [version, file, sqlContent]
        );
        await client.query('RELEASE SAVEPOINT sp_supamig;');
      } catch (_) {
        await client.query('ROLLBACK TO SAVEPOINT sp_supamig;');
      }
    }

    const commitRes = await client.query('COMMIT');
    if (commitRes && commitRes.command && commitRes.command !== 'COMMIT') {
      throw new Error(`COMMIT returned unexpected command tag: "${commitRes.command}". Expected "COMMIT".`);
    }

    // After COMMIT, re-read ledger row, failing loudly if absent
    const checkLedger = await client.query(
      `SELECT version, checksum FROM public._schema_migrations WHERE version = $1;`,
      [version]
    );
    if (!checkLedger.rows || checkLedger.rows.length === 0) {
      throw new Error(`FATAL: Migration ledger check failed for ${file} (${version}) immediately following COMMIT!`);
    }

    console.log(`✔ Successfully applied ${file}`);
    return true;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error(`\n[MIGRATION FAILED] Error applying ${file}: ${err.message}`);
    throw err;
  }
}

if (require.main === module) {
  runMigrations()
    .then((result) => {
      if (result?.errors?.length) {
        process.exit(1);
      }
      process.exit(0);
    })
    .catch((err) => {
      console.error('\n[MIGRATION RUNNER FAILED]', err.message);
      if (err.stack && process.env.DEBUG_MIGRATE === '1') {
        console.error(err.stack);
      }
      process.exit(1);
    });
}

module.exports = { runMigrations, applySingleMigration, computeChecksum };
