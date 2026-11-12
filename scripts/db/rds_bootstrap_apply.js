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

async function main() {
  bootstrapMutatingScript('scripts/db/rds_bootstrap_apply.js');

  const args = process.argv.slice(2);
  const execute = args.includes('--execute');
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
  for (const f of BOOTSTRAP_FILES) {
    const p = path.join(bootstrapDir, f);
    console.log(`  - ${f} (${fs.statSync(p).size} bytes)`);
  }

  if (!execute) {
    console.log('\nDry-run only. To apply: add --execute --target=production --confirm=<PROD_RDS_HOST>');
    return;
  }

  const client = new Client(cfg);
  await client.connect();
  try {
    for (const f of BOOTSTRAP_FILES) {
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
