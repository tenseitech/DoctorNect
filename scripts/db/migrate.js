'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

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

function computeChecksum(content) {
  const normalized = typeof content === 'string' ? content.replace(/\r\n/g, '\n') : content;
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');
}

async function runMigrations() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const isDryRunAll = args.includes('--dry-run-all');
  const targetArg = args.find(a => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

  console.log(`\n======================================================`);
  console.log(`DoctorNect Migration Runner (Target: ${target.toUpperCase()}${isDryRun ? ' [DRY-RUN]' : ''})`);
  console.log(`======================================================`);

  let dbUrl;
  let poolConfig;

  if (target === 'staging') {
    dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    const targetHost = getHostFingerprint(dbUrl);
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'Run Migrations', allowDestructive: !isDryRun && !isDryRunAll, targetHost });
    poolConfig = { connectionString: dbUrl };
  } else if (target === 'rehearsal' || target === 'production') {
    const host = getEnv('PROD_RDS_HOST');
    assertDatabaseGuard({ targetKind: 'production', operationName: `Run Migrations on ${target}`, allowDestructive: false, targetHost: host });
    const port = parseInt(getEnv('PROD_RDS_PORT') || '5432', 10);
    const database = target === 'rehearsal' ? 'doctornect_rehearsal' : (getEnv('PROD_RDS_DB') || 'postgres');
    const user = getEnv('PROD_RDS_USER') || 'postgres';
    const password = getEnv('PROD_RDS_PASSWORD');
    const certPath = getEnv('PROD_RDS_SSL_ROOT_CERT') || path.resolve(__dirname, '../../infra/aws/global-bundle.pem');

    poolConfig = {
      host,
      port,
      database,
      user,
      password,
      ssl: {
        rejectUnauthorized: true,
        ca: fs.readFileSync(certPath),
      },
    };
    dbUrl = `postgresql://${user}:****@${host}:${port}/${database}`;
  } else {
    console.error(`Invalid target: ${target}. Must be staging, rehearsal, or production.`);
    process.exit(1);
  }

  console.log(`Target Connection: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool(poolConfig);
  const client = await pool.connect();

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

    let pendingCount = 0;

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
        const useOverride = (target === 'production' || target === 'rehearsal') && fs.existsSync(overrideSqlPath);
        const activeFilePath = useOverride ? overrideSqlPath : baseSqlPath;
        const sqlContent = fs.readFileSync(activeFilePath, 'utf8');

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
      const useOverride = (target === 'production' || target === 'rehearsal') && fs.existsSync(overrideSqlPath);
      const activeFilePath = useOverride ? overrideSqlPath : baseSqlPath;
      const sqlContent = fs.readFileSync(activeFilePath, 'utf8');
      const checksum = computeChecksum(sqlContent);

      if (appliedMap.has(version)) {
        const recordedChecksum = appliedMap.get(version);
        if (recordedChecksum !== 'legacy_supabase' && recordedChecksum !== checksum) {
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
      await applySingleMigration({ client, version, file, sqlContent, checksum, supabaseMigExists });
    }

    if (!isDryRun) {
      // Reload PostgREST schema cache
      try {
        await client.query(`NOTIFY pgrst, 'reload schema';`);
        console.log(`✔ Sent NOTIFY pgrst, 'reload schema'`);
      } catch (_) {}
    }

    console.log(`\nMigration run completed. Total pending applied: ${pendingCount}`);

  } finally {
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
  runMigrations().catch(err => {
    console.error('Migration runner failed:', err.message);
    process.exit(1);
  });
}

module.exports = { runMigrations, applySingleMigration, computeChecksum };
