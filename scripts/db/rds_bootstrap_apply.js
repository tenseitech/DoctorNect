'use strict';

/**
 * Apply db/rds_bootstrap/01–04 idempotently to production/rehearsal RDS.
 *
 * Dry-run (default): list files only.
 * Execute: --execute --target=production --confirm=<PROD_RDS_HOST fingerprint host>
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

const BOOTSTRAP_FILES = [
  '01_roles_and_extensions.sql',
  '02_auth_shim.sql',
  '03_legacy_compat.sql',
  '04_rds_runtime_grants.sql',
];

function printBootstrapSqlSummary() {
  const child = require('child_process');
  child.spawnSync(process.execPath, [path.join(__dirname, 'rds_bootstrap_print_summary.js')], {
    stdio: 'inherit',
  });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--print-summary')) {
    printBootstrapSqlSummary();
    return;
  }

  bootstrapMutatingScript('scripts/db/rds_bootstrap_apply.js');

  const execute = args.includes('--execute');
  const preMigrateOnly = args.includes('--pre-migrate-only');
  const targetArg = args.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'production';

  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'RDS bootstrap apply',
    allowDestructive: execute,
    targetHost: getEnv('PROD_RDS_HOST'),
  });

  const dbName = target === 'rehearsal' ? 'doctornect_rehearsal' : getEnv('PROD_RDS_DB') || 'doctornect';
  const cfg = buildRdsPoolConfig({ database: dbName });
  const bootstrapDir = path.resolve(__dirname, '../../db/rds_bootstrap');

  console.log(`RDS bootstrap (target=${target}, mode=${execute ? 'EXECUTE' : 'DRY-RUN'})`);
  console.log(maskRdsTarget(cfg));
  const preMigrateFiles = BOOTSTRAP_FILES.filter((f) => f !== '04_rds_runtime_grants.sql');
  const filesToRun = preMigrateOnly ? preMigrateFiles : BOOTSTRAP_FILES;

  for (const f of filesToRun) {
    const p = path.join(bootstrapDir, f);
    console.log(`  - ${f} (${fs.statSync(p).size} bytes)${f === '04_rds_runtime_grants.sql' ? ' [POST-MIGRATE]' : ''}`);
  }

  if (!execute) {
    console.log('\nDry-run only. To apply pre-migrate 01–03: --execute --pre-migrate-only --confirm-live-data --confirm=<PROD_RDS_HOST>');
    console.log('Full 01–04 after migrations: --execute --confirm-live-data --confirm=<PROD_RDS_HOST>');
    console.log('SQL summary without RDS: --print-summary');
    return;
  }

  const client = new Client(cfg);
  await client.connect();
  try {
    const applyList = preMigrateOnly ? preMigrateFiles : BOOTSTRAP_FILES;
    for (const f of applyList) {
      const sql = fs.readFileSync(path.join(bootstrapDir, f), 'utf8');
      console.log(`\nApplying ${f}...`);
      await client.query(sql);
      console.log(`✔ ${f}`);
    }
    const roles = await client.query(
      `SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role','authenticator') ORDER BY 1`,
    );
    console.log(`Roles: ${roles.rows.map((r) => r.rolname).join(', ')}`);
    const fn = await client.query(
      `SELECT pg_get_functiondef(p.oid) LIKE '%RETURNS text%' AS uid_is_text
       FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
       WHERE n.nspname='auth' AND p.proname='uid' LIMIT 1`,
    );
    if (fn.rows.length) {
      console.log(fn.rows[0].uid_is_text ? '✔ auth.uid() TEXT shim' : '⚠ auth.uid() check manually');
    }
  } finally {
    await client.end();
  }
  console.log('\n✅ Bootstrap complete');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
