'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv } = require('../lib/env_loader');
const { resolveLogicalProdRdsHost } = require('../lib/prod_rds_host_policy');

loadRootEnv();
const bin = 'C:\\Program Files\\PostgreSQL\\18\\bin';
const out = process.argv[2] || `C:\\Users\\khije\\Backups\\doctornect-prod-${new Date().toISOString().slice(0, 10)}`;
fs.mkdirSync(out, { recursive: true });

const tcp = getEnv('PROD_RDS_CONNECT_HOST') || '127.0.0.1';
const logical = resolveLogicalProdRdsHost() || getEnv('PROD_RDS_HOST');
const p = getEnv('PROD_RDS_PORT') || '5434';
const d = getEnv('PROD_RDS_DB');
const u = getEnv('PROD_RDS_USER');
const pemFs = path.resolve(process.cwd(), getEnv('PROD_RDS_SSL_ROOT_CERT') || 'infra/aws/global-bundle.pem');
const pem = pemFs.replace(/\\/g, '/');
const env = {
  ...process.env,
  PGPASSWORD: getEnv('PROD_RDS_PASSWORD'),
  PGSSLMODE: 'verify-full',
  PGSSLROOTCERT: pemFs,
  PGSSLSERVERNAME: getEnv('PROD_RDS_SSL_SERVERNAME') || logical,
};
const conninfo = `dbname=${d} user=${u} hostaddr=${tcp} host=${logical} port=${p} sslmode=verify-full sslrootcert=${pem}`;
const dump = path.join(out, 'doctornect_prod.dump');
const roles = path.join(out, 'roles.sql');

const r1 = spawnSync(path.join(bin, 'pg_dump.exe'), ['-d', conninfo, '-Fc', '-f', dump, '--no-password'], {
  env,
  stdio: ['ignore', 'pipe', 'pipe'],
});
if (r1.status !== 0) {
  console.error('pg_dump FAIL', r1.stderr?.toString().slice(0, 900));
  process.exit(1);
}
let rolesMode = 'doctornect_admin';
const masterUser = getEnv('PROD_RDS_MASTER_USER') || getEnv('PROD_RDS_MASTER_USERNAME');
const masterPass = getEnv('PROD_RDS_MASTER_PASSWORD');
const rolesEnv = { ...env, PGPASSWORD: env.PGPASSWORD };
let rolesConn = conninfo;
const r2 = spawnSync(path.join(bin, 'pg_dumpall.exe'), ['-d', rolesConn, '--roles-only', '-f', roles, '--no-password'], {
  env: rolesEnv,
  stdio: ['ignore', 'pipe', 'pipe'],
});
if (r2.status !== 0 && masterUser && masterPass) {
  rolesMode = 'master';
  rolesConn = `dbname=${d} user=${masterUser} hostaddr=${tcp} host=${logical} port=${p} sslmode=verify-full sslrootcert=${pem}`;
  const masterEnv = { ...env, PGPASSWORD: masterPass };
  const r2b = spawnSync(path.join(bin, 'pg_dumpall.exe'), ['-d', rolesConn, '--roles-only', '-f', roles, '--no-password'], {
    env: masterEnv,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (r2b.status !== 0) {
    console.error('pg_dumpall roles FAIL', r2b.stderr?.toString().slice(0, 500));
    process.exit(2);
  }
} else if (r2.status !== 0) {
  console.error('pg_dumpall roles FAIL (no PROD_RDS_MASTER_* fallback)', r2.stderr?.toString().slice(0, 500));
  process.exit(2);
}
const list = spawnSync(path.join(bin, 'pg_restore.exe'), ['--list', dump], { stdio: ['pipe', 'pipe', 'pipe'] });
const sz = (f) => fs.statSync(f).size;
console.log(
  JSON.stringify({
    out,
    bytes_dump: sz(dump),
    bytes_roles: sz(roles),
    toc_lines: (list.stdout?.toString() || '').split('\n').filter(Boolean).length,
    list_ok: list.status === 0,
    roles_dump_user: rolesMode,
  }),
);