#!/usr/bin/env node
'use strict';
const path = require('path');
const { Client } = require('pg');
const { parseEnvFile } = require('../lib/parse_env_file');
const { findRepoRoot } = require('../lib/repo_root');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const { loadRootEnv } = require('../lib/bootstrap_root_env');

loadRootEnv();
const root = findRepoRoot(path.join(__dirname, '..'));
const fileEnv = parseEnvFile(path.join(root, '.env'));

async function probe(user, password) {
  const cfg = buildRdsPoolConfig({ user });
  cfg.user = user;
  cfg.password = password;
  const client = new Client(cfg);
  try {
    await client.connect();
    await client.query('SELECT 1');
    await client.end();
    return { user, ok: true, sqlstate: null };
  } catch (e) {
    try {
      await client.end();
    } catch (_) {}
    return { user, ok: false, sqlstate: e.code || null };
  }
}

(async () => {
  const masterUserKey = fileEnv.PROD_RDS_MASTER_USER || '(absent)';
  const masterPass = fileEnv.PROD_RDS_MASTER_PASSWORD || '';
  const migratorPass = fileEnv.PROD_RDS_PASSWORD || '';
  console.log('PROD_RDS_MASTER_USER_on_disk', masterUserKey);
  console.log('target_masked', maskRdsTarget(buildRdsPoolConfig()));
  const postgres = await probe('postgres', masterPass);
  const migrator = await probe('doctornect_admin', migratorPass);
  const adminWithMasterPass =
    masterUserKey !== 'postgres' ? await probe('doctornect_admin', masterPass) : null;
  console.log(
    JSON.stringify({ postgres, doctornect_admin_migrator: migrator, doctornect_admin_with_master_password: adminWithMasterPass }, null, 2),
  );
  process.exit(postgres.ok && migrator.ok ? 0 : 1);
})();