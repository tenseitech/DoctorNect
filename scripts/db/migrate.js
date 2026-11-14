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
const {
  assertProductionPgCronOrThrow,
  shouldSkipMigrationFile,
  queryPgCronCatalog,
  allowNoCronFromArgv,
} = require('../lib/pg_cron_policy');
const {
  listMigrationsForTarget,
  migrationVersionFromRel,
  MIGRATION_ADVISORY_LOCK_KEYS,
  resolveMigrationSqlPath,
} = require('../lib/migration_file_list');

const MIGRATION_ADVISORY_TARGETS = new Set(['production', 'rehearsal']);

// Staging-only ghost in supabase_migrations.schema_migrations: same body as repo 20261103000008_staging_anon_security_cleanup.sql
// (no db/migrations/20261104000001_*.sql). Omit from backfill into public._schema_migrations (commit 2d5332e, 2026-11-12).
const GHOST_SUPABASE_LEDGER_VERSION = '20261104000001';

function printConnectionFailureHint(target) {
  if (target === 'staging') {
    console.error(
      'Hint: STAGING_SUPABASE_DB_URL must use the session pooler on port 5432 (not transaction pooler 6543).',
    );
  } else if (target === 'production' || target === 'rehearsal') {
    console.error('Hint: use SSM/SSH tunnel — PROD_RDS_CONNECT_HOST=127.0.0.1 and PROD_RDS_PORT (e.g. 5433).');
    console.error('  docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md');
    console.error('  Ensure PROD_RDS_SSL_ROOT_CERT / infra/aws/global-bundle.pem (infra/aws/README_CA_BUNDLE.md).');
  }
}

function loadActiveMigrationSql(relPath, target) {
  const { sqlPath, useOverride } = resolveMigrationSqlPath({ relPath, target });
  const sqlContent = fs.readFileSync(sqlPath, 'utf8');
  return { sqlContent, useOverride };
}

function verifyAllAppliedChecksums({ files, appliedMap, target }) {
  for (const relPath of files) {
    const version = migrationVersionFromRel(relPath);
    if (!appliedMap.has(version)) {
      continue;
    }
    const recordedChecksum = appliedMap.get(version);
    const { sqlContent } = loadActiveMigrationSql(relPath, target);
    const checksum = computeChecksum(sqlContent);
    if (!ledgerChecksumMatches(sqlContent, recordedChecksum)) {
      console.error(
        `\n[FATAL CHECKSUM MISMATCH] Applied migration ${relPath} (version ${version}) no longer matches ledger.`,
      );
      console.error(`Recorded checksum: ${recordedChecksum}`);
      console.error(`Current checksum:  ${checksum}`);
      console.error('Altering already applied migrations violates database integrity.');
      console.error('Aborting before applying any pending migration.');
      process.exit(1);
    }
  }
}

async function loadAppliedMigrationsMap(client, isExecute) {
  const appliedMap = new Map();
  let supabaseMigExists = false;

  if (isExecute) {
    await client.query(`
      CREATE TABLE IF NOT EXISTS public._schema_migrations (
        version text PRIMARY KEY,
        name text NOT NULL,
        checksum text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      );
    `);

    const hasSupabaseMig = await client.query(`
      SELECT 1 FROM information_schema.tables 
      WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations';
    `);
    if (hasSupabaseMig.rows && hasSupabaseMig.rows.length > 0) {
      supabaseMigExists = true;
      try {
        await client.query(`
          INSERT INTO public._schema_migrations (version, name, checksum)
          SELECT version, COALESCE(name, version), 'legacy_supabase'
          FROM supabase_migrations.schema_migrations
          WHERE version <> $1
          ON CONFLICT (version) DO NOTHING;
        `, [GHOST_SUPABASE_LEDGER_VERSION]);
      } catch (err) {
        console.error(
          '[FATAL] Failed to sync supabase_migrations.schema_migrations into public._schema_migrations:',
          err.message,
        );
        throw err;
      }
    }
  } else {
    const ledgerExists = await client.query(`
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = '_schema_migrations'
      LIMIT 1;
    `);
    if (!ledgerExists.rows.length) {
      console.log('[DRY-RUN] public._schema_migrations not found — ledger treated as empty (no DDL executed).');
      return { appliedMap, supabaseMigExists };
    }
  }

  const appliedRes = await client.query(
    `SELECT version, checksum FROM public._schema_migrations ORDER BY version;`,
  );
  for (const row of appliedRes.rows) {
    appliedMap.set(row.version, row.checksum);
  }
  return { appliedMap, supabaseMigExists };
}

async function tryAcquireMigrationAdvisoryLock(client, target) {
  if (!MIGRATION_ADVISORY_TARGETS.has(target)) {
    return false;
  }
  const lockRow = await client.query(
    'SELECT pg_try_advisory_lock($1::integer, $2::integer) AS ok',
    [MIGRATION_ADVISORY_LOCK_KEYS.classId, MIGRATION_ADVISORY_LOCK_KEYS.objectId],
  );
  if (!lockRow.rows[0]?.ok) {
    console.error(
      '[FATAL] Could not acquire migration advisory lock — another migrate.js session may be running on this database.',
    );
    process.exit(1);
  }
  console.log('✔ Migration advisory lock acquired.');
  return true;
}

async function releaseMigrationAdvisoryLock(client, lockHeld) {
  if (!lockHeld || !client) {
    return;
  }
  await client
    .query('SELECT pg_advisory_unlock($1::integer, $2::integer)', [
      MIGRATION_ADVISORY_LOCK_KEYS.classId,
      MIGRATION_ADVISORY_LOCK_KEYS.objectId,
    ])
    .catch(() => {});
}

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

function listPendingMigrationFiles(appliedMap, target) {
  const files = listMigrationsForTarget(target);
  return files.filter((f) => !appliedMap.has(migrationVersionFromRel(f)));
}

function parseMigrationCliArgs(argv) {
  const args = Array.isArray(argv) ? argv : process.argv.slice(2);
  const wantsExecute = args.includes('--execute');
  const wantsDryRun = args.includes('--dry-run') || args.includes('--dry-run-all');
  const isDryRun = wantsDryRun || !wantsExecute;
  const isExecute = !isDryRun;
  return {
    isExecute,
    isDryRun,
    isDryRunAll: args.includes('--dry-run-all'),
    allowOutOfOrder: args.includes('--allow-out-of-order'),
  };
}

function warnLedgerVersionsWithoutRepoFile({ appliedMap, files }) {
  const repoVersions = new Set(files.map((rel) => migrationVersionFromRel(rel)));
  for (const version of appliedMap.keys()) {
    if (version === GHOST_SUPABASE_LEDGER_VERSION) {
      continue;
    }
    if (!repoVersions.has(version)) {
      console.warn(
        `[WARN] Ledger version ${version} has no matching repo migration file (expected ghost only: ${GHOST_SUPABASE_LEDGER_VERSION}).`,
      );
    }
  }
}

function assertPendingMigrationsInOrder({ files, appliedMap, target, allowOutOfOrder }) {
  if (allowOutOfOrder || !MIGRATION_ADVISORY_TARGETS.has(target)) {
    return;
  }
  if (appliedMap.size === 0) {
    return;
  }
  const maxApplied = [...appliedMap.keys()].sort().pop();
  for (const relPath of files) {
    const version = migrationVersionFromRel(relPath);
    if (appliedMap.has(version)) {
      continue;
    }
    if (version < maxApplied) {
      throw new Error(
        `[FATAL] Out-of-order pending migration ${relPath} (version ${version}) is older than max applied version ${maxApplied}. ` +
          'Reconcile the ledger or pass --allow-out-of-order for controlled recovery only.',
      );
    }
  }
}

async function runMigrations() {
  const args = process.argv.slice(2);
  const { isExecute, isDryRun, isDryRunAll, allowOutOfOrder } = parseMigrationCliArgs(args);
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
    console.error(
      `Invalid target: ${target}. Must be staging, production, rehearsal, replay, or replay_check.`,
    );
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
    printConnectionFailureHint(target);
    process.exit(1);
  }

  let lockHeld = false;
  try {
    lockHeld = await tryAcquireMigrationAdvisoryLock(client, target);

    const { appliedMap, supabaseMigExists } = await loadAppliedMigrationsMap(client, isExecute);
    console.log(`Existing Applied Migrations in Ledger: ${appliedMap.size}`);

    const files = listMigrationsForTarget(target);
    warnLedgerVersionsWithoutRepoFile({ appliedMap, files });
    if (target === 'staging') {
      const prodMigrations = listMigrationsForTarget('production');
      const rdsOnlySkipped = prodMigrations.length - files.length;
      if (rdsOnlySkipped > 0) {
        console.log(`Note: ${rdsOnlySkipped} RDS-only migration(s) skipped for target=${target}`);
      }
    }

    const pendingFilesPreview = listPendingMigrationFiles(appliedMap, target);
    console.log(`\nPending migration files (${pendingFilesPreview.length}):`);
    if (pendingFilesPreview.length === 0) {
      console.log('  (none — schema is at head)');
    } else {
      for (const f of pendingFilesPreview) {
        console.log(`  - ${f}`);
      }
    }

    const pgCronCatalog = await queryPgCronCatalog(client);
    const allowNoCron = allowNoCronFromArgv();
    const pgCronPolicy = assertProductionPgCronOrThrow({
      target,
      available: pgCronCatalog.available,
      installed: pgCronCatalog.installed,
      allowNoCron,
    });
    const skipCronMigration = pgCronPolicy.skipCronMigration;

    verifyAllAppliedChecksums({ files, appliedMap, target });
    assertPendingMigrationsInOrder({ files, appliedMap, target, allowOutOfOrder });

    let pendingCount = 0;
    let appliedThisRun = 0;

    if (isDryRunAll) {
      console.log(
        'Note: --dry-run-all wraps statements in a rollback transaction. ' +
          'CREATE INDEX CONCURRENTLY and other non-transactional statements may show false errors.',
      );
      console.log(`\n--- EXECUTING --dry-run-all (Statement-level testing inside single rollback transaction) ---`);
      const pendingFiles = files.filter((f) => !appliedMap.has(migrationVersionFromRel(f)));
      console.log(`Found ${pendingFiles.length} pending migration files: ${pendingFiles.join(', ')}`);

      await client.query('BEGIN');
      let dryRunTxnOpen = true;
      const allErrors = [];
      let totalStatements = 0;

      try {
        for (const file of pendingFiles) {
          if (shouldSkipMigrationFile(path.basename(file), skipCronMigration)) {
            console.log(`\n[SKIPPED — --allow-no-cron] ${file}`);
            continue;
          }
          const { sqlContent } = loadActiveMigrationSql(file, target);

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
        dryRunTxnOpen = false;
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
        }
        console.log('\n✔ ZERO ERRORS DETECTED across all pending migration statements.');

        return { pendingCount: pendingFiles.length, totalStatements, errors: allErrors };
      } catch (dryRunErr) {
        if (dryRunTxnOpen) {
          await client.query('ROLLBACK').catch(() => {});
          dryRunTxnOpen = false;
          console.error('\n✔ Transaction ROLLED BACK after dry-run-all error.');
        }
        throw dryRunErr;
      }
    }

    for (const file of files) {
      const version = migrationVersionFromRel(file);
      const { sqlContent, useOverride } = loadActiveMigrationSql(file, target);
      const checksum = computeChecksum(sqlContent);

      if (appliedMap.has(version)) {
        continue;
      }

      pendingCount++;
      console.log(`\n[Pending Migration] -> ${file} (checksum: ${checksum.slice(0, 8)}...) ${useOverride ? '[RDS OVERRIDE]' : ''}`);

      if (shouldSkipMigrationFile(path.basename(file), skipCronMigration)) {
        console.log(`[SKIPPED — --allow-no-cron] Would skip: ${file}`);
        continue;
      }

      if (isDryRun) {
        console.log(`[DRY-RUN] Would apply: ${file}`);
        continue;
      }

      // Execute in a transaction
      console.log(`Applying ${file}...`);
      await applySingleMigration({ client, version, file, sqlContent, checksum, supabaseMigExists });
      appliedThisRun++;
    }

    if (!isDryRun) {
      // Reload PostgREST schema cache
      try {
        await client.query(`NOTIFY pgrst, 'reload schema';`);
        console.log(`✔ Sent NOTIFY pgrst, 'reload schema'`);
      } catch (_) {}
    }

    console.log(`\n=== MIGRATION RUN SUMMARY ===`);
    console.log(`Target: ${target} | Host: ${targetHostLabel || '(see connection mask above)'}`);
    console.log(`Pending seen this run: ${pendingCount} | Applied this run: ${isDryRun ? 0 : appliedThisRun}`);
    console.log(`Ledger total versions: ${appliedMap.size + (isDryRun ? 0 : appliedThisRun)}`);
    if (appliedMap.size > 0 || isExecute) {
      try {
        const finalLedger = await client.query(
          `SELECT version, name, applied_at FROM public._schema_migrations ORDER BY version DESC LIMIT 15;`,
        );
        if (finalLedger.rows.length) {
          console.log('\nMost recent _schema_migrations rows:');
          for (const row of finalLedger.rows) {
            console.log(`  ${row.version}  ${row.name}  @ ${row.applied_at}`);
          }
        }
      } catch (_) {
        /* dry-run: ledger table may be absent */
      }
    }
    console.log(`\nMigration run completed.`);

  } finally {
    await releaseMigrationAdvisoryLock(client, lockHeld);
    client.release();
    await pool.end();
  }
}

async function applySingleMigration({ client, version, file, sqlContent, checksum, supabaseMigExists = false }) {
  await client.query('BEGIN');
  try {
    await client.query(sqlContent);
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

module.exports = {
  runMigrations,
  applySingleMigration,
  computeChecksum,
  parseMigrationCliArgs,
  assertPendingMigrationsInOrder,
  loadAppliedMigrationsMap,
};
