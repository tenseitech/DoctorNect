'use strict';

/**
 * Read-only RDS probe: connect, version, extensions, role sanity.
 * Usage:
 *   node scripts/db/rds_readiness_probe.js --target=production
 */

const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertProductionRdsTarget, verifyConnectedRdsSession } = require('../lib/rds_connect_guard');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');
const { getProdPgMajor, getProdPgVersion } = require('../lib/pg_version_policy');
const { verifyRdsPgCronReadiness } = require('../lib/pg_cron_policy');

const REQUIRED_EXTENSIONS = [
  { name: 'pgcrypto', required: true, note: 'migrations + notification_outbox' },
  { name: 'uuid-ossp', required: true, note: 'legacy UUID helpers' },
  { name: 'pg_stat_statements', required: false, note: 'bootstrap 01; optional on RDS' },
  { name: 'pg_cron', required: true, note: '20260923000003; shared_preload_libraries + cron.database_name=PROD_RDS_DB' },
];

async function main() {
  const targetArg = process.argv.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'production';
  if (target !== 'production' && target !== 'rehearsal') {
    throw new Error('--target must be production or rehearsal');
  }

  if (!process.argv.some((a) => a.startsWith('--confirm='))) {
    const host = getEnv('PROD_RDS_HOST');
    console.error(`Add --target=production --confirm=${getHostFingerprint(host)} for read-only RDS probe.`);
    process.exit(1);
  }
  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'RDS readiness probe (read-only)',
    allowDestructive: false,
    targetHost: getEnv('PROD_RDS_HOST'),
  });

  const dbName = target === 'rehearsal' ? 'doctornect_rehearsal' : getEnv('PROD_RDS_DB') || 'doctornect';
  let cfg;
  try {
    cfg = buildRdsPoolConfig({ database: dbName });
    assertProductionRdsTarget(cfg);
  } catch (e) {
    console.error(`\n✖ ${e.message}`);
    process.exit(1);
  }
  console.log('RDS readiness probe (read-only)');
  console.log(
    `Documented production engine: PROD_PG_MAJOR=${getProdPgMajor()} PROD_PG_VERSION=${getProdPgVersion()}`,
  );
  console.log(`Logical host: ${cfg.logicalHost}`);
  console.log(`Connect: ${maskRdsTarget(cfg)}\n`);

  const client = new Client(cfg);
  const t0 = Date.now();
  try {
    await client.connect();
  } catch (e) {
    diagnoseConnectError(e, cfg);
    process.exit(1);
  }
  console.log(`✔ TCP connected in ${Date.now() - t0}ms`);

  await verifyConnectedRdsSession(client, cfg);

  const ext = await client.query(`SELECT name, installed_version FROM pg_available_extensions ORDER BY name`);
  const installed = new Map(ext.rows.filter((r) => r.installed_version).map((r) => [r.name, r.installed_version]));
  console.log('\nExtensions:');
  for (const req of REQUIRED_EXTENSIONS) {
    const v = installed.get(req.name);
    if (v) {
      console.log(`  ✔ ${req.name} ${v}`);
    } else if (req.required) {
      console.log(`  ✖ ${req.name} MISSING (required: ${req.note})`);
    } else {
      console.log(`  ○ ${req.name} not installed (optional: ${req.note})`);
    }
  }

  const roles = await client.query(
    `SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role','authenticator') ORDER BY 1`,
  );
  console.log(`\nPostgREST roles present: ${roles.rows.map((r) => r.rolname).join(', ') || '(none — run bootstrap 01)'}`);

  try {
    const uid = await client.query(`SELECT auth.uid() AS u`);
    console.log(`auth.uid() callable: ${uid.rows[0].u === null ? 'yes (null without JWT)' : 'yes'}`);
  } catch (e) {
    console.log(`auth.uid() missing — run bootstrap 02 (${e.code})`);
  }

  const mig = await client.query(
    `SELECT count(*)::int n FROM information_schema.tables WHERE table_schema='public' AND table_name='_schema_migrations'`,
  );
  console.log(`_schema_migrations table: ${mig.rows[0].n ? 'yes' : 'no (migrations not applied yet)'}`);

  console.log(`\npg_cron RDS parameters (PROD_RDS_DB=${getEnv('PROD_RDS_DB') || 'doctornect'}):`);
  const cronReady = await verifyRdsPgCronReadiness(client);
  for (const line of cronReady.lines) {
    console.log(`  ${line}`);
  }
  if (!cronReady.ok) {
    process.exitCode = 1;
    console.log('\n⚠ READINESS incomplete (pg_cron / cron jobs)');
  }

  await client.end();
  if (process.exitCode === 1) {
    console.log('\n⚠ READINESS PROBE finished with warnings/errors');
    return;
  }
  console.log('\n✅ READINESS PROBE OK');
}

function diagnoseConnectError(err, cfg) {
  console.error(`\n✖ Connection failed: ${err.code || ''} ${err.message}`);
  if (err.code === 'ENOENT_CA_BUNDLE') {
    console.error('Fix: download CA bundle (infra/aws/README_CA_BUNDLE.md).');
    return;
  }
  if (err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT' || err.code === 'ENOTFOUND') {
    console.error('Likely network: start SSM tunnel, set PROD_RDS_CONNECT_HOST=127.0.0.1 and PROD_RDS_PORT=<local>.');
    console.error('RDS security group must allow 5432 from bastion/gateway SG only.');
    return;
  }
  if (err.message && err.message.toLowerCase().includes('certificate')) {
    console.error(`Set PROD_RDS_SSL_SERVERNAME=${cfg.logicalHost} when connecting via localhost tunnel.`);
    return;
  }
  if (err.code === '28P01') {
    console.error('Auth failure: check PROD_RDS_USER / PROD_RDS_PASSWORD in repo root .env (not committed).');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
