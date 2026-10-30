'use strict';

const fs = require('fs');
const path = require('path');
let Pool;
try {
  Pool = require('pg').Pool;
} catch (_) {
  Pool = require('../node_modules/pg').Pool;
}
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

const SYSTEM_CONFIG_SEEDS = [
  {
    key: 'patient_module_status',
    value: {
      status: 'active',
      message: 'Normal operational state',
      allow_writes: true,
    },
  },
  {
    key: 'promoted_ads',
    value: {
      enabled: true,
      price_per_day: 300,
      pricing_tiers: {
        '24': 300,
        '72': 750,
        '168': 1500,
        '720': 5000,
      },
      max_active_banners: 10,
    },
  },
];

async function main() {
  const args = process.argv.slice(2);
  const isExecute = args.includes('--execute');
  const isDryRun = !isExecute || args.includes('--dry-run');

  const targetArg = args.find(a => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging';

  const adminUidArg = args.find(a => a.startsWith('--admin-uid='));
  const adminUid = adminUidArg ? adminUidArg.split('=')[1].trim() : null;

  console.log('================================================================');
  console.log(`DoctorNect: Production Minimum Seed Pipeline`);
  console.log(`Target: ${target.toUpperCase()} | Mode: ${isDryRun ? 'DRY-RUN (Simulated)' : 'EXECUTE (Live Write)'}`);
  console.log('================================================================\n');

  let dbUrl;
  let poolConfig;

  if (target === 'production' || target === 'rehearsal') {
    const host = getEnv('PROD_RDS_HOST');
    assertDatabaseGuard({
      targetKind: 'production',
      operationName: 'Seed Production Minimum',
      allowDestructive: false,
      targetHost: host,
    });
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
  } else if (target === 'staging') {
    dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    const targetHost = getHostFingerprint(dbUrl);
    if (!isDryRun) {
      assertDatabaseGuard({
        targetKind: 'staging',
        operationName: 'Seed Production Minimum on Staging',
        allowDestructive: true,
        targetHost,
      });
    }
    poolConfig = { connectionString: dbUrl };
  } else {
    console.error(`Invalid target: ${target}. Must be staging, rehearsal, or production.`);
    process.exit(1);
  }

  console.log(`Connecting to: ${maskConnectionString(dbUrl)}...`);
  const pool = new Pool(poolConfig);
  const client = await pool.connect();

  try {
    console.log('\n--- 1. Verification of Zero Application Data Invariant ---');
    const tables = ['users', 'patients', 'doctors', 'appointments', 'prescriptions', 'medical_stores', 'labs', 'ambulances'];
    for (const tbl of tables) {
      try {
        const countRes = await client.query(`SELECT count(*)::int AS cnt FROM public.${tbl};`);
        console.log(`Table public.${tbl}: ${countRes.rows[0].cnt} rows`);
      } catch (err) {
        console.log(`Table public.${tbl}: (not yet created or not accessible)`);
      }
    }

    console.log('\n--- 2. Required System Configuration Seeds ---');
    for (const seed of SYSTEM_CONFIG_SEEDS) {
      console.log(`Key: "${seed.key}" -> Value: ${JSON.stringify(seed.value)}`);
    }

    console.log('\n--- 3. First-Admin Bootstrap (private.admin_users) ---');
    if (adminUid) {
      console.log(`Admin UID provided via CLI argument: "${adminUid}"`);
    } else {
      console.log('No --admin-uid=<UID> provided. First admin bootstrap will be skipped.');
      console.log('Note: To bootstrap super-admin, pass --admin-uid=<FIREBASE_AUTH_UID>.');
    }

    if (isDryRun) {
      console.log('\n[DRY-RUN COMPLETE] No database modifications were written.');
      console.log('To apply changes live, pass --execute flag.');
      return;
    }

    console.log('\n--- Applying Seeds in Single Transaction ---');
    await client.query('BEGIN');

    // 1. Seed system_config
    for (const seed of SYSTEM_CONFIG_SEEDS) {
      await client.query(
        `INSERT INTO public.system_config (config_key, config_value, updated_at)
         VALUES ($1, $2::jsonb, NOW())
         ON CONFLICT (config_key) DO UPDATE
         SET config_value = EXCLUDED.config_value, updated_at = NOW();`,
        [seed.key, JSON.stringify(seed.value)]
      );
      console.log(`✔ Seeded system_config: ${seed.key}`);
    }

    // 2. Bootstrap first admin if provided
    if (adminUid) {
      await client.query(
        `INSERT INTO private.admin_users (user_id, granted_by, granted_at)
         VALUES ($1, 'production_bootstrap', NOW())
         ON CONFLICT (user_id) DO NOTHING;`,
        [adminUid]
      );
      console.log(`✔ Bootstrapped initial admin in private.admin_users: ${adminUid}`);
    }

    await client.query('COMMIT');
    console.log('\n✔ All minimum seeds committed successfully.');

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('\n❌ Seed operation failed, transaction rolled back:', err);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
