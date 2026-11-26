'use strict';

/**
 * Read-only: PostgREST roles + authenticator membership grants on production RDS.
 * Usage: PROD RDS tunnel up, then:
 *   node scripts/ops/check_rds_postgrest_authenticator_readonly.js --target=production --confirm=<host-fingerprint>
 */

const { Client } = require('pg');
const path = require('path');
const fs = require('fs');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');
const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
const { assertProductionRdsTarget } = require('../lib/rds_connect_guard');
const { assertDatabaseGuard, getHostFingerprint } = require('../lib/env_guard');

const REQUIRED_ROLES = ['anon', 'authenticated', 'service_role', 'authenticator'];
const AUTH_MEMBER_OF = ['anon', 'authenticated', 'service_role'];

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const targetArg = process.argv.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'production';
  if (target !== 'production') {
    throw new Error('--target=production only');
  }

  const host = getEnv('PROD_RDS_HOST');
  if (!process.argv.some((a) => a.startsWith('--confirm='))) {
    console.error(`Add --confirm=${getHostFingerprint(host)} for read-only authenticator check.`);
    process.exit(1);
  }

  assertDatabaseGuard({
    targetKind: 'production',
    operationName: 'PostgREST authenticator read-only check',
    allowDestructive: false,
    targetHost: host,
  });

  const cfg = buildRdsPoolConfig({ database: getEnv('PROD_RDS_DB') || 'doctornect' });
  assertProductionRdsTarget(cfg);

  const client = new Client(cfg);
  const gaps = [];
  try {
    await client.connect();
    await client.query('BEGIN READ ONLY');

    const roles = await client.query(
      `SELECT rolname, rolcanlogin, rolinherit
       FROM pg_roles
       WHERE rolname = ANY ($1::text[])
       ORDER BY rolname`,
      [REQUIRED_ROLES],
    );
    const have = new Map(roles.rows.map((r) => [r.rolname, r]));

    for (const name of REQUIRED_ROLES) {
      if (!have.has(name)) {
        gaps.push(`missing role: ${name}`);
        continue;
      }
      const r = have.get(name);
      if (name === 'authenticator' && !r.rolcanlogin) {
        gaps.push('authenticator exists but rolcanlogin=false');
      }
    }

    for (const member of AUTH_MEMBER_OF) {
      if (!have.has('authenticator') || !have.has(member)) continue;
      const m = await client.query(
        `SELECT pg_has_role('authenticator'::regrole, $1::regrole, 'member') AS ok`,
        [member],
      );
      if (!m.rows[0].ok) {
        gaps.push(`authenticator not member of ${member}`);
      }
    }

    await client.query('COMMIT');
  } finally {
    await client.end().catch(() => {});
  }

  if (gaps.length === 0) {
    console.log('OK: PostgREST roles and authenticator memberships present.');
    process.exit(0);
  }

  console.log('GAPS:');
  for (const g of gaps) console.log(`  - ${g}`);

  const repairPath = path.join(__dirname, '..', '..', 'db', 'rds_bootstrap', '05_postgrest_authenticator_repair.sql');
  if (!fs.existsSync(repairPath)) {
    console.log(`\nRepair SQL template missing at ${repairPath} — use db/rds_bootstrap/01_roles_and_extensions.sql`);
  } else {
    console.log(`\nApply manually when approved: ${repairPath}`);
  }
  process.exit(1);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});