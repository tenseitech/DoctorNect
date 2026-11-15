#!/usr/bin/env node
'use strict';

/**
 * Parses db/migrations/*.sql for RLS enablement and policy names (staging schema source).
 * Output: docs/audit/RLS_TABLE_INVENTORY.json
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const MIG_DIR = path.join(ROOT, 'db', 'migrations');
const RDS_DIR = path.join(ROOT, 'db', 'migrations', 'rds');
const OUT = path.join(ROOT, 'docs', 'audit', 'RLS_TABLE_INVENTORY.json');

function listSql(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).map((f) => path.join(dir, f));
}

function scanFile(filePath) {
  const sql = fs.readFileSync(filePath, 'utf8');
  const tables = new Map();

  const enableRe = /ALTER TABLE (?:IF EXISTS )?(?:public\.)?(\w+)\s+ENABLE ROW LEVEL SECURITY/gi;
  let m;
  while ((m = enableRe.exec(sql)) !== null) {
    const t = m[1];
    if (!tables.has(t)) tables.set(t, { rls_enabled: true, policies: [], files: [] });
    tables.get(t).files.push(path.basename(filePath));
  }

  const policyRe = /CREATE POLICY "?([^"\s]+)"? ON (?:public\.)?(\w+)/gi;
  while ((m = policyRe.exec(sql)) !== null) {
    const [, pol, table] = m;
    if (!tables.has(table)) tables.set(table, { rls_enabled: false, policies: [], files: [] });
    const row = tables.get(table);
    if (!row.policies.includes(pol)) row.policies.push(pol);
    if (!row.files.includes(path.basename(filePath))) row.files.push(path.basename(filePath));
  }

  return tables;
}

function main() {
  const merged = new Map();
  for (const f of [...listSql(MIG_DIR), ...listSql(RDS_DIR)]) {
    for (const [table, info] of scanFile(f)) {
      const prev = merged.get(table) || { rls_enabled: false, policies: [], files: [] };
      merged.set(table, {
        rls_enabled: prev.rls_enabled || info.rls_enabled,
        policies: [...new Set([...prev.policies, ...info.policies])].sort(),
        files: [...new Set([...prev.files, ...info.files])].sort(),
      });
    }
  }

  const rows = [...merged.entries()]
    .map(([table, info]) => ({ table, ...info, policy_count: info.policies.length }))
  .sort((a, b) => a.table.localeCompare(b.table));

  const withoutRls = rows.filter((r) => !r.rls_enabled);

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(
    OUT,
    JSON.stringify({ generated: new Date().toISOString(), tables: rows, without_rls: withoutRls }, null, 2),
    'utf8',
  );

  console.log(`Wrote ${OUT} (${rows.length} tables, ${withoutRls.length} without ENABLE RLS in migrations)`);
}

main();