#!/usr/bin/env node
'use strict';

/**
 * Apply RDS bootstrap 01-03 to doctornect DB as doctornect_admin (RDS-like local).
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const adminUrl =
  process.env.RDSLIKE_ADMIN_URL ||
  `postgresql://rdsadmin:${process.env.RDSLIKE_PG_PASSWORD || 'test'}@127.0.0.1:${process.env.RDSLIKE_PG_PORT || '5442'}/doctornect`;
const migratorUrl =
  process.env.RDSLIKE_MIGRATOR_URL ||
  `postgresql://doctornect_admin:test@127.0.0.1:${process.env.RDSLIKE_PG_PORT || '5442'}/doctornect`;

const bootDir = path.resolve(__dirname, '../../db/rds_bootstrap');

async function main() {
  const rdsadminUrl = adminUrl;
  const superClient = new Client({ connectionString: rdsadminUrl });
  const client = new Client({ connectionString: migratorUrl });
  await superClient.connect();
  await client.connect();
  try {
  const file01 = path.join(bootDir, '01_roles_and_extensions.sql');
    process.stdout.write('apply 01_roles_and_extensions.sql (as rdsadmin) ... ');
    await superClient.query(fs.readFileSync(file01, 'utf8'));
    console.log('ok');
    for (const file of ['02_auth_shim.sql', '03_legacy_compat.sql']) {
      const sql = fs.readFileSync(path.join(bootDir, file), 'utf8');
      process.stdout.write(`apply ${file} (as doctornect_admin) ... `);
      await client.query(sql);
      console.log('ok');
    }
    const postgresRole = await client.query(
      `SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') AS exists`,
    );
    console.log(`postgres role exists: ${postgresRole.rows[0].exists}`);
  } finally {
    await client.end();
    await superClient.end();
  }
  console.log(`adminUrl: ${adminUrl.replace(/:[^:@]+@/, ':****@')}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});