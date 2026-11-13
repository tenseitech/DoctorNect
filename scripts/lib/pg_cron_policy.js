'use strict';

function getEnv(key) {
  // Lazy load so unit tests do not require parsing repo .env at import time.
  const { getEnv: load } = require('./env_loader');
  return load(key);
}

const CRON_MIGRATION_FILE = '20260923000003_doctornect_cron.sql';
const CRON_MIGRATION_VERSION = '20260923000003';

const EXPECTED_CRON_JOB_NAMES = [
  'expire-promoted-ads',
  'cleanup-expired-otp-challenges',
  'cleanup-expired-rate-limits',
  'expire-stale-ambulance-broadcasts',
];

function isRdsProductionTarget(target) {
  return target === 'production' || target === 'rehearsal';
}

function allowNoCronFromArgv(argv = process.argv.slice(2)) {
  return argv.includes('--allow-no-cron');
}

function printAllowNoCronBanner(target) {
  console.error('\n' + '='.repeat(72));
  console.error('⚠️  --allow-no-cron: SKIPPING pg_cron migration and cron job guarantees.');
  console.error(`    Target: ${target}`);
  console.error('    Scheduled maintenance (ads expiry, OTP cleanup, rate limits, ambulance');
  console.error('    broadcast expiry) will NOT run in-database unless you replace them.');
  console.error('    Do NOT use in production cutover without an external scheduler.');
  console.error('='.repeat(72) + '\n');
}

/**
 * @param {{ target: string, available: boolean, installed: boolean, allowNoCron?: boolean }} ctx
 */
function assertProductionPgCronOrThrow(ctx) {
  const { target, available, installed, allowNoCron = false } = ctx;
  if (!isRdsProductionTarget(target)) return { skipCronMigration: false };

  if (allowNoCron) {
    printAllowNoCronBanner(target);
    return { skipCronMigration: true };
  }

  if (!available) {
    const err = new Error(
      `pg_cron is not available in pg_available_extensions on ${target}. ` +
        'Enable shared_preload_libraries=pg_cron, set cron.database_name=PROD_RDS_DB, reboot RDS, ' +
        'then CREATE EXTENSION pg_cron in the target database. ' +
        'Emergency only: re-run with --allow-no-cron (skips cron migration; jobs will not run).',
    );
    err.code = 'PG_CRON_NOT_AVAILABLE';
    throw err;
  }

  if (!installed) {
    console.log(
      'ℹ pg_cron is available but not installed yet (expected before first migrate); ' +
        `${CRON_MIGRATION_FILE} will run CREATE EXTENSION.`,
    );
  }

  return { skipCronMigration: false };
}

function shouldSkipMigrationFile(file, skipCronMigration) {
  return skipCronMigration && file === CRON_MIGRATION_FILE;
}

async function queryPgCronCatalog(client) {
  const avail = await client.query(
    `SELECT 1 AS ok FROM pg_available_extensions WHERE name = 'pg_cron' LIMIT 1`,
  );
  const inst = await client.query(
    `SELECT extversion FROM pg_extension WHERE extname = 'pg_cron' LIMIT 1`,
  );
  return {
    available: avail.rows.length > 0,
    installed: inst.rows.length > 0,
    version: inst.rows[0]?.extversion || null,
  };
}

async function queryPgCronParameterSettings(client) {
  const res = await client.query(`
    SELECT name, setting
    FROM pg_settings
    WHERE name IN ('shared_preload_libraries', 'cron.database_name')
    ORDER BY name`);
  const map = Object.fromEntries(res.rows.map((r) => [r.name, r.setting]));
  return {
    sharedPreloadLibraries: map.shared_preload_libraries || '',
    cronDatabaseName: map.cron_database_name || map['cron.database_name'] || '',
  };
}

function sharedPreloadIncludesPgCron(sharedPreloadLibraries) {
  return String(sharedPreloadLibraries || '')
    .split(',')
    .map((s) => s.trim())
    .includes('pg_cron');
}

function cronDatabaseMatchesProd(cronDatabaseName, expectedDb) {
  const expected = String(expectedDb != null ? expectedDb : getEnv('PROD_RDS_DB') || 'doctornect').trim();
  return String(cronDatabaseName || '').trim() === expected;
}

async function queryExpectedCronJobs(client) {
  try {
    const res = await client.query(
      `SELECT jobname, schedule, active
       FROM cron.job
       WHERE jobname = ANY($1::text[])
       ORDER BY jobname`,
      [EXPECTED_CRON_JOB_NAMES],
    );
    return res.rows;
  } catch (e) {
    if (e.code === '42P01' || /cron\.job/.test(e.message)) {
      return null;
    }
    throw e;
  }
}

async function verifyRdsPgCronReadiness(client, options = {}) {
  const expectJobsAfterMigrate = options.expectJobsAfterMigrate !== false;
  const lines = [];
  let ok = true;

  const params = await queryPgCronParameterSettings(client);
  if (!sharedPreloadIncludesPgCron(params.sharedPreloadLibraries)) {
    lines.push(
      `✖ shared_preload_libraries does not include pg_cron (current: "${params.sharedPreloadLibraries}")`,
    );
    ok = false;
  } else {
    lines.push('✔ shared_preload_libraries includes pg_cron');
  }

  const expectedDb = getEnv('PROD_RDS_DB') || 'doctornect';
  if (!cronDatabaseMatchesProd(params.cronDatabaseName)) {
    lines.push(
      `✖ cron.database_name is "${params.cronDatabaseName}" (expected PROD_RDS_DB="${expectedDb}")`,
    );
    ok = false;
  } else {
    lines.push(`✔ cron.database_name matches PROD_RDS_DB (${expectedDb})`);
  }

  const cat = await queryPgCronCatalog(client);
  if (!cat.available) {
    lines.push('✖ pg_cron not in pg_available_extensions');
    ok = false;
  } else if (!cat.installed) {
    lines.push('○ pg_cron available, not installed (run migrations or CREATE EXTENSION)');
  } else {
    lines.push(`✔ pg_cron installed (${cat.version || 'version n/a'})`);
  }

  let ledgerHasCron = false;
  if (expectJobsAfterMigrate) {
    const mig = await client.query(
      `SELECT 1 FROM information_schema.tables
       WHERE table_schema='public' AND table_name='_schema_migrations'`,
    );
    if (mig.rows.length) {
      const ver = await client.query(
        `SELECT 1 FROM public._schema_migrations WHERE version = $1 LIMIT 1`,
        [CRON_MIGRATION_VERSION],
      );
      ledgerHasCron = ver.rows.length > 0;
    }
  }

  if (ledgerHasCron && cat.installed) {
    const jobs = await queryExpectedCronJobs(client);
    if (jobs === null) {
      lines.push('✖ cron.job not queryable (pg_cron broken?)');
      ok = false;
    } else {
      const found = new Set(jobs.map((j) => j.jobname));
      for (const name of EXPECTED_CRON_JOB_NAMES) {
        if (found.has(name)) {
          const row = jobs.find((j) => j.jobname === name);
          lines.push(`✔ cron job "${name}" schedule=${row.schedule} active=${row.active}`);
        } else {
          lines.push(`✖ cron job missing: "${name}"`);
          ok = false;
        }
      }
    }
  } else if (!ledgerHasCron) {
    lines.push('○ cron jobs not required yet (_schema_migrations lacks 20260923000003)');
  }

  return { ok, lines };
}

module.exports = {
  CRON_MIGRATION_FILE,
  CRON_MIGRATION_VERSION,
  EXPECTED_CRON_JOB_NAMES,
  isRdsProductionTarget,
  allowNoCronFromArgv,
  assertProductionPgCronOrThrow,
  shouldSkipMigrationFile,
  queryPgCronCatalog,
  queryPgCronParameterSettings,
  sharedPreloadIncludesPgCron,
  cronDatabaseMatchesProd,
  verifyRdsPgCronReadiness,
  printAllowNoCronBanner,
};
