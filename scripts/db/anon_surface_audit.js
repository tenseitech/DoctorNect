'use strict';

/**
 * Verifies Postgres role `anon` can SELECT only the public discovery allowlist and cannot EXECUTE
 * any function in schema public. Intended for CI/staging/RDS-rehearsal; uses a rolled-back transaction.
 *
 * Requires a session-capable connection (port 5432 / direct — not Supabase transaction pooler 6543).
 *
 * Usage:
 *   node scripts/db/anon_surface_audit.js --target=staging
 *   node scripts/db/anon_surface_audit.js --target=replay
 *   node scripts/db/anon_surface_audit.js --target=production
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { assertSessionCapableConnection, SESSION_CONNECTION_DOC } = require('../lib/db_connection_guard');

const ALLOWLIST_TABLES = new Set([
  'doctor_directory',
  'lab_catalog_tests',
  'system_config',
  'review_public',
]);

const SYSTEM_CONFIG_PUBLIC_KEYS = ['patient_module_status', 'promoted_ads'];

function resolvePoolConfig(target) {
  if (target === 'replay' || target === 'replay_check') {
    assertDatabaseGuard({ targetKind: 'replay', operationName: 'anon surface audit', allowDestructive: false });
    const dbUrl = getEnv('REPLAY_DB_URL');
    return { poolConfig: { connectionString: dbUrl }, dbUrl };
  }
  if (target === 'staging') {
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'anon surface audit', allowDestructive: false });
    const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
    return { poolConfig: { connectionString: dbUrl }, dbUrl };
  }
  if (target === 'rehearsal' || target === 'production') {
    assertDatabaseGuard({
      targetKind: 'production',
      operationName: `anon surface audit (${target})`,
      allowDestructive: false,
    });
    const host = getEnv('PROD_RDS_HOST');
    const port = parseInt(getEnv('PROD_RDS_PORT') || '5432', 10);
    const database = target === 'rehearsal' ? 'doctornect_rehearsal' : (getEnv('PROD_RDS_DB') || 'postgres');
    const user = getEnv('PROD_RDS_USER') || 'postgres';
    const password = getEnv('PROD_RDS_PASSWORD');
    const certPath = getEnv('PROD_RDS_SSL_ROOT_CERT') || path.resolve(__dirname, '../../infra/aws/global-bundle.pem');
    const poolConfig = {
      host,
      port,
      database,
      user,
      password,
      ssl: { rejectUnauthorized: true, ca: fs.readFileSync(certPath) },
    };
    return { poolConfig, dbUrl: `postgresql://${user}:****@${host}:${port}/${database}` };
  }
  throw new Error(`Unknown target: ${target}`);
}

/**
 * Run SQL inside SAVEPOINT so expected permission errors never abort the outer transaction.
 * @returns {{ ok: boolean, code?: string, message?: string, rowCount?: number, rows?: unknown[] }}
 */
async function probeSql(client, sql, { expectSuccess = true, allowedErrorCodes = ['42501'] } = {}) {
  const sp = `sp_${Math.random().toString(36).slice(2, 10)}`;
  await client.query(`SAVEPOINT ${sp}`);
  try {
    const res = await client.query(sql);
    await client.query(`RELEASE SAVEPOINT ${sp}`);
    if (!expectSuccess) {
      return {
        ok: false,
        message: `Expected failure (${allowedErrorCodes.join('|')}) but query succeeded`,
      };
    }
    return {
      ok: true,
      code: '00000',
      rowCount: res.rowCount,
      rows: res.rows,
    };
  } catch (err) {
    await client.query(`ROLLBACK TO SAVEPOINT ${sp}`);
    await client.query(`RELEASE SAVEPOINT ${sp}`);
    const code = err.code || 'ERR';
    if (expectSuccess) {
      return { ok: false, code, message: err.message, unexpected: true };
    }
    if (allowedErrorCodes.includes(code)) {
      return { ok: true, code, message: err.message };
    }
    return { ok: false, code, message: err.message, unexpected: true };
  }
}

async function runAnonSurfaceAudit(options = {}) {
  const args = process.argv.slice(2);
  const targetArg = args.find((a) => a.startsWith('--target='));
  const target = options.targetOverride || (targetArg ? targetArg.split('=')[1].toLowerCase() : 'staging');

  const { poolConfig, dbUrl } = resolvePoolConfig(target);
  assertSessionCapableConnection(dbUrl, 'anon_surface_audit.js');

  console.log(`\nDoctorNect anon surface audit (target=${target})`);
  console.log(`Connection: ${maskConnectionString(dbUrl)}`);
  console.log(`${SESSION_CONNECTION_DOC}\n`);

  const pool = new Pool(poolConfig);
  const client = await pool.connect();
  const failures = [];

  try {
    const roleCheck = await client.query(
      `SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') AS has_anon;`,
    );
    if (!roleCheck.rows[0].has_anon) {
      console.log('Role anon absent — skipping anon checks (OK for RDS bootstrap before roles migration).');
      return { skipped: true, failures: [] };
    }

    await client.query('BEGIN');
    await client.query(`SET LOCAL ROLE anon;`);
    await client.query(`SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);`);

    const relRes = await client.query(`
      SELECT c.relname AS name, c.relkind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind IN ('r', 'v', 'm', 'f', 'p')
      ORDER BY c.relname;
    `);

    for (const row of relRes.rows) {
      const table = row.name;
      const probe = await probeSql(client, `SELECT 1 FROM public."${table}" LIMIT 0;`, {
        expectSuccess: ALLOWLIST_TABLES.has(table),
        allowedErrorCodes: ['42501'],
      });
      const shouldAllow = ALLOWLIST_TABLES.has(table);
      if (shouldAllow && !probe.ok) {
        failures.push(
          `ALLOWLIST DENIED: public.${table} — ${probe.code}: ${probe.message}`,
        );
      }
      if (!shouldAllow && probe.ok && probe.code === '00000') {
        failures.push(`UNEXPECTED ALLOW: public.${table} SELECT succeeded for anon`);
      }
      if (!shouldAllow && !probe.ok && probe.unexpected) {
        failures.push(
          `UNEXPECTED ERROR on public.${table}: ${probe.code}: ${probe.message}`,
        );
      }
    }

    for (const key of SYSTEM_CONFIG_PUBLIC_KEYS) {
      const probe = await probeSql(
        client,
        `SELECT 1 FROM public.system_config WHERE config_key = '${key}' LIMIT 1;`,
        { expectSuccess: true },
      );
      if (!probe.ok) {
        failures.push(`system_config key '${key}' not readable by anon — ${probe.code}: ${probe.message}`);
      }
    }

    const blockedProbe = await probeSql(
      client,
      `SELECT config_key FROM public.system_config WHERE config_key = 'demo_accounts' LIMIT 1;`,
      { expectSuccess: true },
    );
    if (!blockedProbe.ok && blockedProbe.unexpected) {
      failures.push(`system_config demo_accounts probe failed — ${blockedProbe.code}: ${blockedProbe.message}`);
    } else if (blockedProbe.ok && blockedProbe.rows && blockedProbe.rows.length > 0) {
      failures.push('system_config demo_accounts leaked rows to anon');
    }

    const fnRes = await client.query(`
      SELECT p.oid::regprocedure::text AS sig, p.oid
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prokind = 'f';
    `);

    for (const row of fnRes.rows) {
      const privRes = await client.query(
        `SELECT has_function_privilege('anon', $1::oid, 'EXECUTE') AS anon_exec;`,
        [row.oid],
      );
      if (privRes.rows[0]?.anon_exec === true) {
        failures.push(`anon EXECUTE granted on ${row.sig}`);
        continue;
      }

      const publicExecRes = await client.query(
        `
        SELECT EXISTS (
          SELECT 1
          FROM aclexplode(
            COALESCE(
              (SELECT proacl FROM pg_proc WHERE oid = $1::oid),
              acldefault('f', (SELECT relowner FROM pg_proc WHERE oid = $1::oid))
            )
          ) AS acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'EXECUTE'
        ) AS public_exec;
        `,
        [row.oid],
      );
      if (publicExecRes.rows[0]?.public_exec === true) {
        failures.push(`PUBLIC EXECUTE granted on ${row.sig}`);
      }
    }

    await client.query('ROLLBACK');
  } finally {
    client.release();
    await pool.end();
  }

  if (failures.length) {
    console.error('FAILURES:');
    for (const f of failures) console.error(`  - ${f}`);
    process.exitCode = 1;
  } else {
    console.log('PASS: anon surface matches allowlist and public functions are not executable.');
  }

  return { skipped: false, failures };
}

if (require.main === module) {
  runAnonSurfaceAudit().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { runAnonSurfaceAudit, ALLOWLIST_TABLES, SYSTEM_CONFIG_PUBLIC_KEYS, probeSql };
