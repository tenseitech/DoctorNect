#!/usr/bin/env node
'use strict';

/**
 * Read-only effective grants via has_table_privilege / relacl (works for migrator; not information_schema).
 * Usage: node scripts/db/rds_role_grants_matrix.js --target=replay [--confirm-live-data]
 * Output: docs/audit-local/rds_role_grants_matrix_<ts>.json (not committed)
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { bootstrapMutatingScript } = require('../lib/mutating_script_bootstrap');

const ROLES = ['anon', 'authenticated', 'service_role', 'authenticator'];
const PRIVS = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'];

function resolveDbUrl(target) {
  if (target === 'replay' || target === 'replay_check') {
    const base = getEnv('REPLAY_DB_URL') || getEnv('LOCAL_FRESH_DB_URL');
    if (!base) throw new Error('Set REPLAY_DB_URL or LOCAL_FRESH_DB_URL');
    const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
    if (target === 'replay_check') u.pathname = '/replay_check';
    return u.toString();
  }
  const { buildRdsPoolConfig } = require('../lib/rds_pool_config');
  const cfg = buildRdsPoolConfig();
  return `postgresql://${encodeURIComponent(cfg.user)}@${cfg.host}:${cfg.port}/${encodeURIComponent(cfg.database)}`;
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const targetArg = process.argv.find((a) => a.startsWith('--target='));
  const target = targetArg ? targetArg.split('=')[1] : 'replay_check';
  if (target !== 'production') {
    bootstrapMutatingScript('scripts/db/rds_role_grants_matrix.js');
  }

  const dbUrl = resolveDbUrl(target);
  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();
  const out = {
    captured_at: new Date().toISOString(),
    target,
    db_mask: maskConnectionString(dbUrl),
    tables: [],
  };

  try {
    const readOnly = target === 'production';
    if (readOnly) await client.query('BEGIN READ ONLY');

    const tables = await client.query(`
      SELECT n.nspname AS schema_name, c.relname AS table_name, c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = ANY ($1::text[])
        AND c.relkind IN ('r', 'v', 'm')
      ORDER BY 1, 2
    `, [['public', 'auth', 'private']]);

    for (const row of tables.rows) {
      const fq = `${row.schema_name}.${row.table_name}`;
      const grants = {};
      for (const role of ROLES) {
        grants[role] = {};
        for (const priv of PRIVS) {
          const r = await client.query(
            `SELECT has_table_privilege($1::regrole, $2::regclass, $3) AS ok`,
            [role, fq, priv],
          );
          if (r.rows[0].ok) grants[role][priv] = true;
        }
      }
      const acl = await client.query(
        `SELECT relacl::text AS relacl FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relname = $2`,
        [row.schema_name, row.table_name],
      );
      out.tables.push({
        object: fq,
        kind: row.relkind,
        relacl: acl.rows[0]?.relacl || null,
        grants,
      });
    }

    if (readOnly) await client.query('COMMIT');
  } finally {
    client.release();
    await pool.end();
  }

  const dir = path.join(__dirname, '../../docs/audit-local');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `rds_role_grants_matrix_${target}_${Date.now()}.json`);
  fs.writeFileSync(file, JSON.stringify(out, null, 2));
  console.log(`Wrote ${file} (${out.tables.length} objects)`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error('FAIL:', e.message || e);
    process.exit(1);
  });
}