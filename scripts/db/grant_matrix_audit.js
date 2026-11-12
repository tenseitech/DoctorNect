'use strict';

/**
 * Export anon / authenticated / service_role grants (tables + functions) from a database.
 * Local-only by default. Pass --target=staging --confirm-live-data only when operator approves.
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const gatewayConfig = require('../../services/api-gateway/src/config');

const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

function freshUrl() {
  const base = getEnv('LOCAL_FRESH_DB_URL') || getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  if (getEnv('LOCAL_FRESH_DB_URL')) return base;
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

async function fetchGrantMatrix(client) {
  const tables = await client.query(`
    SELECT grantee, table_name, string_agg(DISTINCT privilege_type, ',' ORDER BY privilege_type) AS privileges
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND grantee IN ('anon', 'authenticated', 'service_role')
    GROUP BY grantee, table_name
    ORDER BY table_name, grantee;
  `);

  const routines = await client.query(`
    SELECT grantee, routine_name AS name,
           string_agg(DISTINCT privilege_type, ',' ORDER BY privilege_type) AS privileges
    FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public'
      AND grantee IN ('anon', 'authenticated', 'service_role')
    GROUP BY grantee, routine_name
    ORDER BY routine_name, grantee;
  `);

  const sequences = await client.query(`
    SELECT grantee, object_name AS name,
           string_agg(DISTINCT privilege_type, ',' ORDER BY privilege_type) AS privileges
    FROM information_schema.usage_privileges
    WHERE object_schema = 'public'
      AND object_type = 'SEQUENCE'
      AND grantee IN ('anon', 'authenticated', 'service_role')
    GROUP BY grantee, object_name
    ORDER BY object_name, grantee;
  `);

  const version = await client.query(`SELECT version()`);

  return {
    pgVersion: version.rows[0].version,
    tables: tables.rows,
    routines: routines.rows,
    sequences: sequences.rows,
  };
}

function matrixToMap(rows, keyField) {
  const m = new Map();
  for (const r of rows) {
    m.set(`${r[keyField]}:${r.grantee}`, r.privileges);
  }
  return m;
}

function diffMaps(a, b, labelA, labelB) {
  const diffs = [];
  const keys = new Set([...a.keys(), ...b.keys()]);
  for (const k of keys) {
    const va = a.get(k);
    const vb = b.get(k);
    if (va === vb) continue;
    if (!va) diffs.push({ key: k, kind: 'missing_in_a', a: labelA, b: labelB, staging: vb });
    else if (!vb) diffs.push({ key: k, kind: 'missing_in_b', a: labelA, b: labelB, local: va });
    else diffs.push({ key: k, kind: 'privilege_mismatch', local: va, staging: vb });
  }
  return diffs;
}

function auditAnonSurprises(matrix) {
  const allowedAnonTables = new Set([
    'doctor_directory',
    'lab_catalog_tests',
    'system_config',
    'review_public',
  ]);
  const surprises = [];
  for (const row of matrix.tables) {
    if (row.grantee !== 'anon') continue;
  const privs = row.privileges || '';
  if (!allowedAnonTables.has(row.table_name) && !row.table_name.startsWith('pg_')) {
      surprises.push({ table: row.table_name, privileges: privs, reason: 'not in gateway anon allowlist' });
    }
  }
  return surprises;
}

async function main() {
  const args = process.argv.slice(2);
  const compareStaging = args.includes('--compare-staging');
  if (compareStaging && !args.includes('--confirm-live-data')) {
    console.error('Refusing --compare-staging without --confirm-live-data (operator must approve live DB access).');
    process.exit(1);
  }

  const outPath = path.resolve(__dirname, '../../docs/reports/grant_matrix_local.json');

  const localClient = new Client({
    connectionString: freshUrl(),
    ssl: getEnv('LOCAL_FRESH_DB_URL') ? undefined : undefined,
  });
  await localClient.connect();
  const local = await fetchGrantMatrix(localClient);
  await localClient.end();

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  const report = { generatedAt: new Date().toISOString(), local };

  if (compareStaging) {
    const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL');
    if (!stagingUrl) {
      console.error('STAGING_SUPABASE_DB_URL missing');
      process.exit(1);
    }
    const sClient = new Client({ connectionString: stagingUrl, ssl: { rejectUnauthorized: false } });
    await sClient.connect();
    report.staging = await fetchGrantMatrix(sClient);
    await sClient.end();

    report.tableDiffs = diffMaps(
      matrixToMap(local.tables, 'table_name'),
      matrixToMap(report.staging.tables, 'table_name'),
      'local',
      'staging',
    );
    report.routineDiffs = diffMaps(
      matrixToMap(local.routines, 'name'),
      matrixToMap(report.staging.routines, 'name'),
      'local',
      'staging',
    );
  } else {
    const cached = path.resolve(__dirname, '../../docs/reports/fresh_local_vs_staging_schema_diff.json');
    if (fs.existsSync(cached)) {
      const parsed = JSON.parse(fs.readFileSync(cached, 'utf8'));
      const grantMissing = (parsed.diffs || []).filter((d) => d.category === 'GRANT_MISSING');
      const grantExtra = (parsed.diffs || []).filter((d) => d.category === 'GRANT_EXTRA');
      report.cachedParityGrantMissing = grantMissing.length;
      report.cachedParityGrantExtra = grantExtra.length;
      report.note =
        'Staging not queried (operator policy). Use cached schema_diff GRANT counts; re-run with --compare-staging --confirm-live-data when approved.';
    }
  }

  report.anonSurprises = auditAnonSurprises(local);
  report.gatewayServiceRoleTables = gatewayConfig.serviceRoleOnlyTables;
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));

  console.log('Grant matrix audit');
  console.log(`Local DB: ${maskConnectionString(freshUrl())}`);
  console.log(`PG: ${local.pgVersion.split(',')[0]}`);
  console.log(`Table grant rows: ${local.tables.length}, routines: ${local.routines.length}, sequences: ${local.sequences.length}`);
  console.log(`Anon surprises: ${report.anonSurprises.length}`);
  if (report.tableDiffs) console.log(`Live staging table diffs: ${report.tableDiffs.length}`);
  if (report.cachedParityGrantMissing != null) {
    console.log(`Cached parity GRANT_MISSING (staging has, local lacked at diff time): ${report.cachedParityGrantMissing}`);
  }
  console.log(`Wrote ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
