'use strict';

/**
 * Create PROD_RDS_DB if missing (connects to postgres maintenance DB first).
 * Usage: node scripts/db/rds_create_database.js --confirm=<PROD_RDS_HOST>
 */

const { Client } = require('pg');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

const DB_NAME = (getEnv('PROD_RDS_DB') || 'doctornect').trim();

async function main() {
  const host = getEnv('PROD_RDS_HOST');
  if (!process.argv.some((a) => a.startsWith('--confirm='))) {
    console.error(`Add --confirm=${getHostFingerprint(host)}`);
    process.exit(1);
  }
  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'Create application database',
    allowDestructive: true,
    targetHost: host,
  });

  const maintCfg = buildRdsPoolConfig({ database: 'postgres' });
  console.log(`Maintenance connect: ${maskRdsTarget(maintCfg)}`);
  const client = new Client(maintCfg);
  await client.connect();
  try {
    const exists = await client.query(`SELECT 1 FROM pg_database WHERE datname = $1`, [DB_NAME]);
    if (exists.rows.length) {
      console.log(`✔ Database "${DB_NAME}" already exists — no-op.`);
      return;
    }
    const safe = DB_NAME.replace(/[^a-zA-Z0-9_]/g, '');
    if (safe !== DB_NAME) {
      throw new Error('PROD_RDS_DB contains invalid characters');
    }
    await client.query(`CREATE DATABASE ${safe} ENCODING 'UTF8'`);
    console.log(`✔ Created database "${DB_NAME}".`);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
