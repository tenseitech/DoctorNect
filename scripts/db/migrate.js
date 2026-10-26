'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');

function computeChecksum(content) {
  return crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

async function runMigrations() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const targetArg = args.find(a => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

  console.log(`\n======================================================`);
  console.log(`DoctorNect Migration Runner (Target: ${target.toUpperCase()}${isDryRun ? ' [DRY-RUN]' : ''})`);
  console.log(`======================================================`);

  let dbUrl;
  let poolConfig;

  if (target === 'staging') {
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'Run Migrations', allowDestructive: false });
    dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    poolConfig = { connectionString: dbUrl };
  } else if (target === 'rehearsal' || target === 'production') {
    assertDatabaseGuard({ targetKind: 'production', operationName: `Run Migrations on ${target}`, allowDestructive: false });
    const host = getEnv('PROD_RDS_HOST');
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
        if (recordedChecksum !== checksum) {
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
      await client.query('BEGIN');
      try {
        await client.query(sqlContent);
        await client.query(
          `INSERT INTO public._schema_migrations (version, name, checksum) VALUES ($1, $2, $3);`,
          [version, file, checksum]
        );
        await client.query('COMMIT');
        console.log(`✔ Successfully applied ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`\n[MIGRATION FAILED] Error applying ${file}: ${err.message}`);
        throw err;
      }
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

if (require.main === module) {
  runMigrations().catch(err => {
    console.error('Migration runner failed:', err.message);
    process.exit(1);
  });
}

module.exports = { runMigrations, computeChecksum };
