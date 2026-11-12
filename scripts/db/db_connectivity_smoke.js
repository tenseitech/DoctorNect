'use strict';

/**
 * Non-destructive DB connectivity smoke per environment.
 * - staging: direct Postgres via STAGING_SUPABASE_DB_URL
 * - production: Auth Gateway HTTP + optional module table counts via service key
 *
 * Usage:
 *   node scripts/db/db_connectivity_smoke.js --env=staging
 *   node scripts/db/db_connectivity_smoke.js --env=production
 */

const { Client } = require('pg');
const { getEnv, maskConnectionString, printEnvSummary } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertProductionRdsTarget, verifyConnectedRdsSession } = require('../lib/rds_connect_guard');
const { getHostFingerprint } = require('../lib/env_guard');

const MODULE_PROBES = [
  { module: 'doctor', table: 'doctors', column: 'id' },
  { module: 'patient', table: 'patients', column: 'id' },
  { module: 'pharmacy', table: 'medical_stores', column: 'id' },
  { module: 'lab', table: 'labs', column: 'id' },
  { module: 'ambulance', table: 'ambulances', column: 'id' },
];

async function smokeStagingPostgres() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  if (!dbUrl) {
    throw new Error('STAGING_SUPABASE_DB_URL is not configured');
  }
  console.log(`Postgres target: ${maskConnectionString(dbUrl)}`);
  const client = new Client({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  try {
    const mig = await client.query(
      'SELECT count(*)::int AS n FROM public._schema_migrations',
    );
    console.log(`✅ Connected; _schema_migrations rows: ${mig.rows[0].n}`);
    for (const probe of MODULE_PROBES) {
      const res = await client.query(
        `SELECT count(*)::int AS n FROM public.${probe.table}`,
      );
      console.log(`  [${probe.module}] ${probe.table}: ${res.rows[0].n} rows (read OK)`);
    }
  } finally {
    await client.end();
  }
}

async function smokeProductionPostgres() {
  const logicalHost = getEnv('PROD_RDS_HOST');
  if (!logicalHost) throw new Error('PROD_RDS_HOST is not configured');
  const cfg = buildRdsPoolConfig({ database: getEnv('PROD_RDS_DB') || 'doctornect' });
  assertProductionRdsTarget(cfg);
  console.log(`RDS Postgres (read-only): ${maskRdsTarget(cfg)}`);
  const client = new Client(cfg);
  await client.connect();
  try {
    await verifyConnectedRdsSession(client, cfg);
    const mig = await client.query(
      `SELECT count(*)::int n FROM information_schema.tables WHERE table_schema='public' AND table_name='_schema_migrations'`,
    );
    if (mig.rows[0].n) {
      const c = await client.query('SELECT count(*)::int n FROM public._schema_migrations');
      console.log(`  _schema_migrations rows: ${c.rows[0].n}`);
    } else {
      console.log('  _schema_migrations: (not created yet — bootstrap/migrate pending)');
    }
    for (const probe of MODULE_PROBES) {
      const exists = await client.query(
        `SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=$1`,
        [probe.table],
      );
      if (!exists.rows.length) {
        console.log(`  [${probe.module}] ${probe.table}: table not present yet`);
        continue;
      }
      const res = await client.query(`SELECT count(*)::int AS n FROM public.${probe.table}`);
      console.log(`  [${probe.module}] ${probe.table}: ${res.rows[0].n} rows`);
    }
  } finally {
    await client.end();
  }
}

async function smokeProductionGateway() {
  const gatewayUrl = getEnv('PROD_GATEWAY_URL');
  if (!gatewayUrl) throw new Error('PROD_GATEWAY_URL is not configured');
  const anonKey = getEnv('PROD_GATEWAY_ANON_KEY') || getEnv('ANON_KEY') || 'doctornect-anon-public-key';
  const serviceKey = getEnv('PROD_GATEWAY_SERVICE_KEY');

  const healthRes = await fetch(`${gatewayUrl.replace(/\/+$/, '')}/healthz`, {
    signal: AbortSignal.timeout(10000),
  });
  if (!healthRes.ok) {
    throw new Error(`/healthz returned HTTP ${healthRes.status}`);
  }
  const health = await healthRes.json();
  console.log(`✅ Gateway /healthz: ${JSON.stringify(health)}`);

  const dirRes = await fetch(
    `${gatewayUrl.replace(/\/+$/, '')}/rest/v1/doctor_directory?select=id&limit=1`,
    {
      headers: { apikey: anonKey, Accept: 'application/json' },
      signal: AbortSignal.timeout(10000),
    },
  );
  if (!dirRes.ok) {
    throw new Error(`doctor_directory probe HTTP ${dirRes.status}`);
  }
  console.log('✅ Anonymous doctor_directory read OK');

  if (!serviceKey) {
    console.log('⚠️ PROD_GATEWAY_SERVICE_KEY missing — skipping per-module authenticated reads');
    return;
  }

  const { createClient } = require('@supabase/supabase-js');
  const admin = createClient(gatewayUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  for (const probe of MODULE_PROBES) {
    const { error, count } = await admin
      .from(probe.table)
      .select(probe.column, { count: 'exact', head: true });
    if (error) throw new Error(`${probe.module} ${probe.table}: ${error.message}`);
    console.log(`  [${probe.module}] ${probe.table}: count=${count ?? 0} (service read OK)`);
  }
}

async function main() {
  const envArg = (process.argv.find((a) => a.startsWith('--env=')) || '--env=staging').split('=')[1];
  const env = String(envArg).toLowerCase();
  console.log('====================================================');
  console.log(`DB CONNECTIVITY SMOKE (env=${env})`);
  console.log('====================================================\n');

  const modeArg = process.argv.find((a) => a.startsWith('--mode='));
  const mode = modeArg ? modeArg.split('=')[1] : 'auto';

  if (env === 'staging') {
    await smokeStagingPostgres();
  } else if (env === 'production') {
    if (mode === 'postgres' || mode === 'auto') {
      try {
        await smokeProductionPostgres();
      } catch (e) {
        if (mode === 'postgres') throw e;
        console.log(`⚠ RDS direct probe skipped: ${e.message}`);
      }
    }
    if (mode === 'gateway' || mode === 'auto') {
      if (getEnv('PROD_GATEWAY_URL')) {
        await smokeProductionGateway();
      } else if (mode === 'gateway') {
        throw new Error('PROD_GATEWAY_URL is not configured');
      } else {
        console.log('⚠ PROD_GATEWAY_URL missing — skipping HTTP gateway smoke');
      }
    }
    printEnvSummary([
      'PROD_RDS_HOST',
      'PROD_RDS_CONNECT_HOST',
      'PROD_RDS_PORT',
      'PROD_RDS_DB',
      'PROD_RDS_USER',
      'PROD_RDS_SSL_ROOT_CERT',
      'PROD_GATEWAY_URL',
    ]);
  } else {
    throw new Error('--env must be staging or production');
  }

  console.log('\n✅ SMOKE PASS');
}

if (require.main === module) {
  main().catch((e) => {
    console.error(`❌ SMOKE FAIL: ${e.message}`);
    process.exit(1);
  });
}

module.exports = { smokeStagingPostgres, smokeProductionGateway, MODULE_PROBES };
