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

async function identity(user, password) {
  const cfg = buildRdsPoolConfig({ user });
  cfg.user = user;
  cfg.password = password;
  const client = new Client(cfg);
  try {
    await client.connect();
    const id = await client.query(`
      SELECT current_user, current_database() AS db, inet_server_port() AS server_port, left(version(), 70) AS version`);
    const priv = await client.query(
      `SELECT rolname, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = current_user`,
    );
    const extPriv = await client.query(
      `SELECT has_database_privilege(current_user, current_database(), 'CREATE') AS can_create_in_db`,
    );
    const superMember = await client.query(`
      SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        JOIN pg_roles u ON u.oid = m.member
        WHERE r.rolname = 'rds_superuser' AND u.rolname = current_user
      ) AS member_of_rds_superuser`);
    const canCreateExtension = superMember.rows[0].member_of_rds_superuser;
    await client.end();
    return {
      current_user: id.rows[0].current_user,
      current_database: id.rows[0].db,
      server_port: id.rows[0].server_port,
      version: id.rows[0].version,
      ssl: Boolean(cfg.ssl),
      rolcreaterole: priv.rows[0]?.rolcreaterole,
      rolcreatedb: priv.rows[0]?.rolcreatedb,
      member_of_rds_superuser: superMember.rows[0].member_of_rds_superuser,
      can_create_in_db: extPriv.rows[0].can_create_in_db,
      can_create_extension_effective: canCreateExtension,
    };
  } catch (e) {
    try {
      await client.end();
    } catch (_) {}
    return { error: e.code || null };
  }
}

(async () => {
  const masterUserKey = fileEnv.PROD_RDS_MASTER_USER || '(absent)';
  const masterPass = fileEnv.PROD_RDS_MASTER_PASSWORD || '';
  const migratorPass = fileEnv.PROD_RDS_PASSWORD || '';
  console.log('PROD_RDS_MASTER_USER_on_disk', masterUserKey);
  console.log('PROD_RDS_DB_on_disk', fileEnv.PROD_RDS_DB || '(absent)');
  console.log('target_masked', maskRdsTarget(buildRdsPoolConfig()));

  const postgres =
    masterUserKey === 'postgres'
      ? await probe('postgres', masterPass)
      : { user: 'postgres', ok: null, sqlstate: null, skipped: true, note: 'RDS master is not postgres on this instance' };

  const migrator = await probe('doctornect_admin', migratorPass);
  const masterLogin =
    masterUserKey === 'doctornect_admin'
      ? await probe('doctornect_admin', masterPass)
      : masterUserKey === 'postgres'
        ? postgres
        : await probe(masterUserKey, masterPass);

  let ident = null;
  if (migrator.ok || masterLogin.ok) {
    const pw = migrator.ok ? migratorPass : masterPass;
    ident = await identity('doctornect_admin', pw);
  }

  console.log(
    JSON.stringify(
      { postgres_probe: postgres, doctornect_admin_migrator: migrator, master_login: masterLogin, identity: ident },
      null,
      2,
    ),
  );

  const ok =
    migrator.ok &&
    masterLogin.ok &&
    (postgres.skipped || postgres.ok);
  process.exit(ok ? 0 : 1);
})();