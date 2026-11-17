#!/usr/bin/env node
'use strict';

/**
 * Production RDS forensics — READ ONLY on target DB (BEGIN READ ONLY).
 * Writes docs/audit/PROD_RDS_FORENSICS.md + JSON snapshot. No secrets/row PII.
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');
const {
  listMigrationsForTarget,
  migrationVersionFromRel,
  resolveMigrationSqlPath,
} = require('../lib/migration_file_list');

const APP_SCHEMAS = ['public', 'auth', 'private'];
const KEY_OBJECT_CANDIDATES = [
  { label: 'notification_outbox', schema: 'public', kind: 'table' },
  { label: 'private.admin_users', schema: 'private', kind: 'table' },
  { label: '_schema_migrations', schema: 'public', kind: 'table' },
  { label: 'users', schema: 'public', kind: 'table' },
  { label: 'doctors', schema: 'public', kind: 'table' },
  { label: 'doctor_directory', schema: 'public', kind: 'view' },
];

function extractSqlSignals(sql) {
  const tables = new Set();
  const views = new Set();
  const reTable = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:([a-z_]+)\.)?([a-z_0-9]+)/gi;
  const reView = /CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:([a-z_]+)\.)?([a-z_0-9]+)/gi;
  let m;
  while ((m = reTable.exec(sql)) !== null) {
    const schema = (m[1] || 'public').toLowerCase();
    tables.add(`${schema}.${m[2].toLowerCase()}`);
  }
  while ((m = reView.exec(sql)) !== null) {
    const schema = (m[1] || 'public').toLowerCase();
    views.add(`${schema}.${m[2].toLowerCase()}`);
  }
  return { tables: [...tables], views: [...views] };
}

function migrationPresenceScore(signals, catalogSet) {
  const expected = [...signals.tables, ...signals.views];
  if (expected.length === 0) return { status: 'no_ddl_signals', present: 0, total: 0 };
  let present = 0;
  for (const name of expected) {
    if (catalogSet.has(name)) present++;
  }
  const ratio = present / expected.length;
  if (ratio === 0) return { status: 'absent', present, total: expected.length };
  if (ratio < 1) return { status: 'partial', present, total: expected.length };
  return { status: 'present', present, total: expected.length };
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const outMd = path.resolve(__dirname, '../../docs/audit/PROD_RDS_FORENSICS.md');
  const outJson = path.resolve(__dirname, '../../docs/audit/PROD_RDS_FORENSICS.json');

  const pool = new Pool(buildRdsPoolConfig());
  const lines = [];
  const log = (s) => {
    lines.push(s);
    console.log(s);
  };

  log(`# PROD RDS forensics (read-only)`);
  log(`Generated: ${new Date().toISOString()}`);
  log(`Target: ${maskRdsTarget(pool.options)}`);
  log('');

  const client = await pool.connect();
  const report = { at: new Date().toISOString(), schemas: APP_SCHEMAS };

  try {
    await client.query('BEGIN READ ONLY');

    report.session = (
      await client.query(
        `SELECT current_user, current_database(), version()`,
      )
    ).rows[0];

    report.databases = (
      await client.query(
        `SELECT datname, pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datistemplate = false ORDER BY datname`,
      )
    ).rows;

    report.pg_stat_database = (
      await client.query(
        `SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit
         FROM pg_stat_database
         WHERE datname = current_database()`,
      )
    ).rows;

    report.extensions = (
      await client.query(
        `SELECT e.extname, n.nspname AS schema, pg_get_userbyid(e.extowner) AS owner
         FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace ORDER BY 1`,
      )
    ).rows;

    report.roles = (
      await client.query(
        `SELECT rolname, rolcanlogin, rolsuper
         FROM pg_roles
         WHERE rolname = ANY($1::text[])
         ORDER BY rolname`,
        [['anon', 'authenticated', 'service_role', 'authenticator', 'doctornect_admin', 'app_migrator']],
      )
    ).rows;

    report.objects = (
      await client.query(
        `
        SELECT n.nspname AS schema_name,
               CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'f' THEN 'function'
               WHEN 'p' THEN 'procedure' WHEN 'S' THEN 'sequence' WHEN 'i' THEN 'index' ELSE c.relkind::text END AS kind,
               c.relname AS name,
               pg_get_userbyid(c.relowner) AS owner
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = ANY ($1::text[])
          AND c.relkind IN ('r','v','f','p','S')
        ORDER BY 1,2,3
        `,
        [APP_SCHEMAS],
      )
    ).rows;

    report.policies = (
      await client.query(
        `SELECT schemaname, tablename, policyname, roles, cmd
         FROM pg_policies
         WHERE schemaname = ANY ($1::text[])
         ORDER BY 1,2,3`,
        [APP_SCHEMAS],
      )
    ).rows;

    report.triggers = (
      await client.query(
        `SELECT n.nspname AS schema_name, c.relname AS table_name, t.tgname AS trigger_name
         FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE NOT t.tgisinternal AND n.nspname = ANY ($1::text[])
         ORDER BY 1,2,3`,
        [APP_SCHEMAS],
      )
    ).rows;

    const tableNames = report.objects.filter((o) => o.kind === 'table');
    const rowCounts = [];
    for (const t of tableNames) {
      const qualified = `${t.schema_name}.${t.name}`;
      try {
        const cnt = await client.query(`SELECT count(*)::bigint AS n FROM ${qualified}`);
        rowCounts.push({ table: qualified, row_count: Number(cnt.rows[0].n) });
      } catch (e) {
        rowCounts.push({ table: qualified, row_count: null, error: e.code || e.message });
      }
    }
    report.row_counts = rowCounts;
    report.tables_with_rows = rowCounts.filter((r) => r.row_count > 0).length;
    report.total_row_count = rowCounts.reduce((s, r) => s + (r.row_count || 0), 0);

    report.ledger = (
      await client.query(
        `SELECT EXISTS (
          SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname='public' AND c.relname='_schema_migrations'
        ) AS ledger_exists`,
      )
    ).rows[0];

    const catalogSet = new Set(
      report.objects
        .filter((o) => o.kind === 'table' || o.kind === 'view')
        .map((o) => `${o.schema_name}.${o.name}`),
    );

    const migrationFiles = listMigrationsForTarget('production');
    const migrationMap = [];
    for (const rel of migrationFiles) {
      const { sqlPath } = resolveMigrationSqlPath({ relPath: rel, target: 'production' });
      const sql = fs.readFileSync(sqlPath, 'utf8');
      const signals = extractSqlSignals(sql);
      const presence = migrationPresenceScore(signals, catalogSet);
      migrationMap.push({
        file: rel,
        version: migrationVersionFromRel(rel),
        ...presence,
        sample_objects: [...signals.tables, ...signals.views].slice(0, 8),
      });
    }
    report.migration_object_map = migrationMap;

    const keyObjects = [];
    for (const k of KEY_OBJECT_CANDIDATES) {
      keyObjects.push({
        ...k,
        exists: catalogSet.has(`${k.schema}.${k.label.split('.').pop()}`) ||
          catalogSet.has(k.label.replace('private.', 'private.')),
      });
    }
    report.key_objects = keyObjects.map((k) => ({
      name: k.label,
      exists: catalogSet.has(
        k.schema === 'private' && k.label.startsWith('private.')
          ? k.label
          : `${k.schema}.${k.label}`,
      ),
    }));

    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
    await pool.end();
  }

  const presentCount = report.migration_object_map.filter((m) => m.status === 'present').length;
  const partialCount = report.migration_object_map.filter((m) => m.status === 'partial').length;
  const absentCount = report.migration_object_map.filter((m) => m.status === 'absent').length;

  log('## Session');
  log(`- User: ${report.session.current_user}`);
  log(`- Database: ${report.session.current_database}`);
  log(`- PG: ${report.session.version.split(',')[0]}`);
  log('');
  log('## Catalog counts');
  log(`- Tables/views/functions listed: ${report.objects.length}`);
  log(`- RLS policies: ${report.policies.length}`);
  log(`- Triggers: ${report.triggers.length}`);
  log(`- Extensions: ${report.extensions.length}`);
  log(`- Tables with rows > 0: ${report.tables_with_rows} / ${report.row_counts.length}`);
  log(`- Total row count (sum): ${report.total_row_count}`);
  log(`- _schema_migrations exists: ${report.ledger.ledger_exists}`);
  log('');
  log('## Migration footprint heuristic (62 files)');
  log(`- present: ${presentCount} | partial: ${partialCount} | absent: ${absentCount} | no_ddl_signals: ${report.migration_object_map.length - presentCount - partialCount - absentCount}`);
  log('');
  log('## Hypothesis: dry-run COMMIT leaked early migrations');
  log('- **Plausible:** `migrate.js` now skips top-level `COMMIT` in `--dry-run-all` (`migration_txn_sql.js`); older runs without skip could commit DDL inside an open `BEGIN`.');
  log('- **Consistent with prod:** ~52 public tables, **no ledger**, partial late objects (e.g. `notification_outbox`, `private.admin_users`) — see `key_objects` in JSON.');
  log('- **Reject if:** ledger had rows matching first N migrations only (ledger missing entirely → partial manual/scratch apply).');
  log('');
  log('## 20:17 preflight “0 tables” vs audit 52');
  log('- `phase1_rds_preflight.js` defaults `PROD_RDS_DB` to **`postgres`**, not `doctornect` (`phase1_rds_preflight.js:11`).');
  log('- `prod_rds_readonly_diagnostic.js` / `buildRdsPoolConfig()` use **`doctornect`** — explains empty vs populated catalog.');
  log('- Fix: `prod_rds_preflight_readonly.js` documents DB name; diagnostic now lists `current_database()` in output.');
  log('');
  log('## Databases on instance');
  for (const d of report.databases) {
    log(`- ${d.datname} (owner ${d.owner})`);
  }

  fs.writeFileSync(outJson, JSON.stringify(report, null, 2));
  fs.writeFileSync(outMd, `${lines.join('\n')}\n\nFull JSON: \`docs/audit/PROD_RDS_FORENSICS.json\` (no cell values).\n`);
  console.log(`\nWrote ${outMd}`);
}

main().catch((err) => {
  console.error('FAIL:', err.message || err);
  process.exit(1);
});