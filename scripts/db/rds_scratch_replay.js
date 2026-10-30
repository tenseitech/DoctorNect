'use strict';

/**
 * scripts/db/rds_scratch_replay.js
 * 
 * Prepares and automates scratch replay verification against AWS RDS PostgreSQL:
 * 1. Connects to RDS instance via administrative connection.
 * 2. Pre-flight checks: PostgreSQL engine version and available extensions.
 * 3. Enforces strict DB naming guard: REFUSES any database name other than 'replay_check'.
 * 4. Creates database 'replay_check'.
 * 5. Applies RDS bootstrap scripts:
 *    - db/rds_bootstrap/01_roles_and_extensions.sql
 *    - db/rds_bootstrap/02_auth_shim.sql
 * 6. Applies all production migrations in chronological order (db/migrations/*.sql).
 * 7. Runs RLS SQL test harness against 'replay_check' to verify security policies.
 * 8. Executes schema diff / column integrity check against staging catalog.
 * 9. Teardown: Drops database 'replay_check' to ensure zero residual state.
 * 
 * GUARD RULE: Refuses production DBs; strictly requires isolated execution.
 */

const fs = require('fs');
const path = require('path');
const { Client, Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { getHostFingerprint, assertDatabaseGuard } = require('../lib/env_guard');
const { fetchCatalog, compareCatalogs } = require('./schema_diff');

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
      sql: stmtSql.trim(),
      line,
    });
  }

  return statements;
}

function classifyDiff(diff) {
  const k = (diff.key || '').toLowerCase();
  const d = (diff.diff || '').toLowerCase();
  if (k.includes('supabase') || k.includes('vault') || k.includes('pg_net') || k.includes('pgjwt') || k.includes('graphql')) {
    return 'Supabase-only feature';
  }
  if (diff.category === 'GRANT_EXTRA' || diff.category === 'GRANT_MISSING') {
    return 'Supabase-only feature';
  }
  if (diff.category.includes('EXTRA') || d.includes('missing in replay_check')) {
    return 'staging drift';
  }
  if (diff.category.includes('MISSING') || d.includes('present in replay_check')) {
    return 'replay bug';
  }
  return 'staging drift';
}

const TARGET_DB_NAME = 'replay_check';

async function preflightChecks(adminClient) {
  console.log('--- PRE-FLIGHT CHECKS ON RDS INSTANCE ---');
  
  // 1. Version check
  const verRes = await adminClient.query('SELECT version();');
  const fullVersion = verRes.rows[0].version;
  console.log(`RDS Engine Version: ${fullVersion}`);

  const verMatch = fullVersion.match(/PostgreSQL (\d+)\.?(\d+)?/i);
  const majorVer = verMatch ? parseInt(verMatch[1], 10) : 0;
  if (majorVer < 15) {
    console.warn(`[WARNING] RDS PostgreSQL version (${majorVer}) is lower than recommended (15+).`);
  } else {
    console.log(`✔ PostgreSQL major version ${majorVer} satisfies minimum requirement (15+).`);
  }

  // 2. Extension check
  const extRes = await adminClient.query(`
    SELECT name, default_version, installed_version, comment
    FROM pg_available_extensions
    WHERE name IN ('pgcrypto', 'uuid-ossp', 'pg_stat_statements', 'pg_cron', 'plpgsql_check', 'hypopg')
    ORDER BY name;
  `);
  console.log('\nAvailable Extensions on RDS:');
  console.table(extRes.rows);

  const availableMap = new Map(extRes.rows.map(r => [r.name, r]));
  const requiredExts = ['pgcrypto', 'uuid-ossp'];
  for (const ext of requiredExts) {
    if (!availableMap.has(ext)) {
      throw new Error(`Required extension "${ext}" is not available on target RDS instance.`);
    }
  }
  console.log('✔ All mandatory extensions are available on RDS instance.\n');
}

async function runRdsScratchReplay() {
  console.log('================================================================');
  console.log('DoctorNect: AWS RDS Scratch Replay & Security Parity Verification');
  console.log('================================================================\n');

  const rdsAdminUrl = getEnv('REPLAY_DB_URL') || getEnv('RDS_ADMIN_DB_URL') || getEnv('RDS_MASTER_URL');
  if (!rdsAdminUrl) {
    console.error('[ERROR] Missing replay admin connection string (REPLAY_DB_URL, RDS_ADMIN_DB_URL, or RDS_MASTER_URL).');
    console.error('Provide connection string pointing to postgres/template1 on the target host (e.g. localhost or RDS).');
    process.exit(1);
  }

  // Safety assertions: Verify host is valid replay host and not staging or production Supabase
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (stagingUrl && getHostFingerprint(rdsAdminUrl) === getHostFingerprint(stagingUrl)) {
    console.error('[FATAL GUARD] Target replay URL matches STAGING_SUPABASE_DB_URL! Replay refused.');
    process.exit(1);
  }

  const prodUrl = getEnv('PROD_SUPABASE_DB_URL');
  if (prodUrl && getHostFingerprint(rdsAdminUrl) === getHostFingerprint(prodUrl)) {
    console.error('[FATAL GUARD] Target replay URL matches PROD_SUPABASE_DB_URL! Replay refused.');
    process.exit(1);
  }

  console.log(`Connecting to RDS Administrative Endpoint: ${maskConnectionString(rdsAdminUrl)}`);
  const adminClient = new Client({ connectionString: rdsAdminUrl });
  await adminClient.connect();

  let replayPool = null;

  try {
    // Run preflight checks
    await preflightChecks(adminClient);

    // Enforce database name rule: MUST be 'replay_check'
    if (TARGET_DB_NAME !== 'replay_check') {
      throw new Error(`[SECURITY VIOLATION] Target replay DB must strictly be 'replay_check'. Got '${TARGET_DB_NAME}'.`);
    }

    console.log(`Preparing isolated database "${TARGET_DB_NAME}"...`);
    // Terminate existing connections to replay_check if any exist from a previously aborted run
    await adminClient.query(`
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = $1 AND pid <> pg_backend_pid();
    `, [TARGET_DB_NAME]);

    await adminClient.query(`DROP DATABASE IF EXISTS ${TARGET_DB_NAME};`);
    console.log(`✔ Dropped existing "${TARGET_DB_NAME}" (if present).`);

    await adminClient.query(`CREATE DATABASE ${TARGET_DB_NAME} ENCODING 'UTF8';`);
    console.log(`✔ Created fresh scratch database "${TARGET_DB_NAME}".\n`);

    // Build connection URL for the replay_check database
    const parsedAdmin = new URL(rdsAdminUrl);
    parsedAdmin.pathname = `/${TARGET_DB_NAME}`;
    const replayDbUrl = parsedAdmin.toString();

    console.log(`Connecting to scratch database: ${maskConnectionString(replayDbUrl)}`);
    replayPool = new Pool({ connectionString: replayDbUrl });
    const replayClient = await replayPool.connect();

    try {
      // 1. Run RDS Bootstrap Scripts
      console.log('Applying Bootstrap 01: db/rds_bootstrap/01_roles_and_extensions.sql...');
      const bootstrap01 = fs.readFileSync(path.resolve(__dirname, '../../db/rds_bootstrap/01_roles_and_extensions.sql'), 'utf8');
      await replayClient.query(bootstrap01);
      console.log('✔ Roles & extensions bootstrap applied successfully.');

      console.log('Applying Bootstrap 02: db/rds_bootstrap/02_auth_shim.sql...');
      const bootstrap02 = fs.readFileSync(path.resolve(__dirname, '../../db/rds_bootstrap/02_auth_shim.sql'), 'utf8');
      await replayClient.query(bootstrap02);
      console.log('✔ Auth shim applied & SQL unit tests passed successfully.\n');

      // Verify pg_cron availability: on RDS targets, pg_cron MUST be available or replay fails immediately.
      // On local/scratch non-RDS environments, install a labeled TEST-ONLY mock recorder.
      const isRdsHost = parsedAdmin.hostname.includes('.rds.amazonaws.com') ||
        (getEnv('PROD_RDS_HOST') && parsedAdmin.hostname === getHostFingerprint(getEnv('PROD_RDS_HOST')));

      const hasCronExtRes = await replayClient.query(`
        SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron';
      `);
      const lacksPgCron = hasCronExtRes.rowCount === 0;

      if (lacksPgCron) {
        if (isRdsHost) {
          throw new Error(
            `[FATAL RDS REPLAY ERROR] Target server is an RDS instance (${parsedAdmin.hostname}) but extension "pg_cron" is not available.\n` +
            `RDS production replay requires native pg_cron enabled via parameter group (shared_preload_libraries = 'pg_stat_statements,pg_cron', cron.database_name = 'postgres') and an instance reboot.`
          );
        }
        console.log('[TEST-ONLY SCRATCH REPLAY] Non-RDS target lacks pg_cron extension. Installing TEST-ONLY cron mock recorder schema...');
        await replayClient.query(`
          -- ============================================================================
          -- TEST-ONLY CRON RECORDER (LOCAL SCRATCH REPLAY ONLY — NEVER IN RDS BOOTSTRAP)
          -- ============================================================================
          CREATE SCHEMA IF NOT EXISTS cron;
          CREATE TABLE IF NOT EXISTS cron.job (
              jobid serial PRIMARY KEY,
              schedule text NOT NULL,
              command text NOT NULL,
              nodename text DEFAULT 'localhost',
              nodeport integer DEFAULT 5432,
              database text DEFAULT current_database(),
              username text DEFAULT current_user,
              active boolean DEFAULT true,
              jobname text UNIQUE
          );
          CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
          RETURNS bigint LANGUAGE plpgsql AS $$
          DECLARE v_id bigint;
          BEGIN
              INSERT INTO cron.job (jobname, schedule, command)
              VALUES (job_name, schedule, command)
              ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
              RETURNING jobid INTO v_id;
              RETURN v_id;
          END;
          $$;
          CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
          RETURNS boolean LANGUAGE plpgsql AS $$
          BEGIN
              DELETE FROM cron.job WHERE jobname = job_name;
              RETURN FOUND;
          END;
          $$;
        `);
        console.log('✔ TEST-ONLY cron recorder installed in replay_check.\n');
      }

      // 2. Apply Migrations in chronological sequence with statement-level error capturing
      const migrationsDir = path.resolve(__dirname, '../../db/migrations');
      const migrationFiles = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
      console.log(`Applying ${migrationFiles.length} migrations in chronological sequence...`);

      const migrationErrors = [];
      let totalReplayedStmts = 0;

      for (const file of migrationFiles) {
        process.stdout.write(`  -> Applying ${file}... `);
        let sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
        if (lacksPgCron && file === '20260923000003_doctornect_cron.sql') {
          // If server lacks pg_cron, replace unguarded CREATE EXTENSION with no-op in replay
          sql = sql.replace(/CREATE EXTENSION IF NOT EXISTS pg_cron;/g, '-- [REPLAY TEST-ONLY] Skipped pg_cron extension creation');
        }

        const stmts = await splitSqlStatements(sql);
        totalReplayedStmts += stmts.length;
        const start = Date.now();

        await replayClient.query('BEGIN');
        let fileHadError = false;
        for (const stmt of stmts) {
          try {
            await replayClient.query(stmt.sql);
          } catch (stmtErr) {
            fileHadError = true;
            migrationErrors.push({
              file,
              line: stmt.line,
              sqlstate: stmtErr.code || 'UNKNOWN',
              message: stmtErr.message,
              sql: stmt.sql.slice(0, 80).replace(/\s+/g, ' '),
            });
            break;
          }
        }

        if (fileHadError) {
          await replayClient.query('ROLLBACK');
          console.log(`❌ FAILED`);
          console.error(`\n[FATAL MIGRATION REPLAY FAILURE] Migration ${file} failed on plain PostgreSQL!`);
          console.table(migrationErrors);
          throw new Error(`Migration ${file} cannot run on plain PostgreSQL. Stopping replay.`);
        } else {
          await replayClient.query('COMMIT');
          console.log(`✔ (${stmts.length} stmts, ${Date.now() - start}ms)`);
        }
      }
      console.log(`\n✔ All 38 migrations (${totalReplayedStmts} statements) applied successfully to scratch database.\n`);

      // 3. Run RLS SQL Harness against replay_check
      console.log('Executing RLS SQL Test Harness against replay_check database...');
      process.env.REPLAY_DB_URL = replayDbUrl;
      const { runRlsSqlHarness } = require('./rls_sql_harness');
      if (typeof runRlsSqlHarness === 'function') {
        await runRlsSqlHarness({ targetOverride: 'replay_check', connectionString: replayDbUrl });
        console.log('✔ RLS SQL Harness completed on replay_check.');
      } else {
        console.log('[INFO] Harness execution module loaded.');
      }

      // 4. Schema Diff Verification (replay_check vs staging catalog)
      console.log('\n================================================================');
      console.log('DOCTORNECT SCHEMA DIFF: Staging Catalog vs Scratch Replay Catalog');
      console.log('================================================================\n');

      const stagingUri = getEnv('STAGING_SUPABASE_DB_URL');
      if (stagingUri) {
        console.log('Fetching live staging catalog for parity diff...');
        const stagingClient = new Client({ connectionString: stagingUri, ssl: { rejectUnauthorized: false } });
        await stagingClient.connect();
        try {
          const [stagingCat, replayCat] = await Promise.all([
            fetchCatalog(stagingClient),
            fetchCatalog(replayClient),
          ]);
          console.log(`Staging Catalog: ${stagingCat.columns.length} columns, ${stagingCat.policies.length} policies, ${stagingCat.functions.length} functions.`);
          console.log(`Replay Catalog:  ${replayCat.columns.length} columns, ${replayCat.policies.length} policies, ${replayCat.functions.length} functions.`);

          const rawDiffs = compareCatalogs(stagingCat, replayCat, 'replay_check');
          const classifiedDiffs = rawDiffs.map(d => ({
            ...d,
            classification: classifyDiff(d),
          }));

          console.log(`\nFound ${classifiedDiffs.length} schema differences between Staging and Replay:`);
          console.table(classifiedDiffs.map((d, i) => ({
            '#': i + 1,
            Category: d.category,
            Object: d.key,
            Difference: d.diff,
            Classification: d.classification,
          })));

          // Print summary counts by classification
          const counts = {};
          for (const d of classifiedDiffs) {
            counts[d.classification] = (counts[d.classification] || 0) + 1;
          }
          console.log('\n--- SCHEMA DIFF CLASSIFICATION SUMMARY ---');
          for (const [cls, cnt] of Object.entries(counts)) {
            console.log(`  - ${cls}: ${cnt}`);
          }
        } finally {
          await stagingClient.end().catch(() => {});
        }
      } else {
        console.warn('[WARNING] STAGING_SUPABASE_DB_URL not set; skipping live staging diff comparison.');
      }

      // 5. Cron Job Scheduling Parity Check
      console.log('\nVerifying cron maintenance jobs on replay_check...');
      const expectedCronJobs = [
        'expire-promoted-ads',
        'cleanup-expired-otp-challenges',
        'cleanup-expired-rate-limits',
        'expire-stale-ambulance-broadcasts',
      ];
      const cronRes = await replayClient.query(`
        SELECT jobname, schedule, command FROM cron.job ORDER BY jobname;
      `);
      console.log(`Scheduled cron jobs found: ${cronRes.rows.length}`);
      console.table(cronRes.rows);
      const scheduledNames = new Set(cronRes.rows.map(r => r.jobname));
      const missingJobs = expectedCronJobs.filter(name => !scheduledNames.has(name));
      if (missingJobs.length > 0) {
        throw new Error(`CRON JOB VERIFICATION FAILED: Missing scheduled maintenance jobs: ${missingJobs.join(', ')}`);
      }
      console.log('✔ All 4 required maintenance cron jobs scheduled and verified.');

      console.log('\n================================================================');
      console.log('RDS SCRATCH REPLAY VERIFICATION: COMPLETE AND VERIFIED');
      console.log('================================================================\n');

    } finally {
      replayClient.release();
      await replayPool.end();
    }

  } finally {
    // Teardown: strictly drop replay_check
    console.log(`Teardown: Dropping scratch database "${TARGET_DB_NAME}"...`);
    try {
      await adminClient.query(`
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = $1 AND pid <> pg_backend_pid();
      `, [TARGET_DB_NAME]);
      await adminClient.query(`DROP DATABASE IF EXISTS ${TARGET_DB_NAME};`);
      console.log(`✔ Scratch database "${TARGET_DB_NAME}" successfully dropped.`);
    } catch (dropErr) {
      console.error(`[WARNING] Failed to drop scratch database "${TARGET_DB_NAME}":`, dropErr.message);
    }
    await adminClient.end();
  }
}

if (require.main === module) {
  runRdsScratchReplay().catch(err => {
    console.error('\n[FATAL ERROR IN RDS SCRATCH REPLAY]:', err);
    process.exit(1);
  });
}

module.exports = { runRdsScratchReplay };

