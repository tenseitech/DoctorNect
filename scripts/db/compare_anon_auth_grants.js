'use strict';

const fs = require('fs');
const path = require('path');

const report = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../docs/reports/grant_matrix_local.json'), 'utf8'));

function mapRows(rows, grantees) {
  const m = new Map();
  for (const r of rows) {
    if (!grantees.includes(r.grantee)) continue;
    m.set(`${r.table_name}:${r.grantee}`, r.privileges);
  }
  return m;
}

const local = mapRows(report.local.tables, ['anon', 'authenticated']);
const staging = mapRows(report.staging.tables, ['anon', 'authenticated']);

const keys = new Set([...local.keys(), ...staging.keys()]);
const diffs = [];
for (const k of [...keys].sort()) {
  const l = local.get(k);
  const s = staging.get(k);
  if (l === s) continue;
  diffs.push({ key: k, local: l || null, staging: s || null });
}

const out = { anonAuthTableGrantDiffs: diffs.length, diffs };
const outPath = path.resolve(__dirname, '../../docs/reports/anon_authenticated_grant_diff_staging.json');
fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
console.log(`anon/authenticated table grant diffs vs staging: ${diffs.length}`);
for (const d of diffs.slice(0, 30)) console.log(d);
if (diffs.length > 30) console.log(`... +${diffs.length - 30} more (see ${outPath})`);
