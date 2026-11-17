'use strict';

/**
 * Static: objects defined in RDS-skipped migrations vs 20261020000001 consolidated.
 * No DB. Outputs missing objects with source file:line.
 */

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');

const SKIPPED_BASES = [
  '20260923000002_doctornect_rls.sql',
  '20260925000001_sync_bridge_infra.sql',
  '20260930000001_fix_security_advisor_warnings.sql',
  '20260930000002_admin_users_table.sql',
  '20260930000003_users_integrity.sql',
  '20260930000004_access_gap_fixes.sql',
  '20260930000006_column_locks.sql',
  '20261001000002_harden_auth_provisioning.sql',
  '20261002000001_is_super_admin_null_safe.sql',
  '20261008000001_firebase_uid_identity.sql',
];

const CONSOLIDATED = '20261020000001_consolidated_firebase_schema_and_rls.sql';

function lineNo(content, index) {
  return content.slice(0, index).split(/\r?\n/).length;
}

function extractObjects(relPath, content) {
  const objs = [];
  const add = (kind, key, index, detail) => {
    objs.push({ kind, key, file: relPath, line: lineNo(content, index), detail });
  };

  const policyRe = /CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+((?:public\.)?[a-zA-Z0-9_.]+)/gi;
  let m;
  while ((m = policyRe.exec(content)) !== null) {
    add('policy', `policy:${m[2]}.${m[1]}`, m.index, m[0].slice(0, 80));
  }

  const policyUnquotedRe = /CREATE\s+POLICY\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_.]+)/gi;
  while ((m = policyUnquotedRe.exec(content)) !== null) {
    if (m[1].toLowerCase() === 'if') continue;
    add('policy', `policy:${m[2]}.${m[1]}`, m.index, m[0].slice(0, 80));
  }

  const fnRe = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-zA-Z0-9_.]+)\s*\(/gi;
  while ((m = fnRe.exec(content)) !== null) {
    add('function', `function:${m[1].toLowerCase()}`, m.index, m[0].slice(0, 80));
  }

  const rlsRe = /ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_.]+)\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/gi;
  while ((m = rlsRe.exec(content)) !== null) {
    add('rls_enable', `rls:${m[1].toLowerCase()}`, m.index, m[0]);
  }

  const trigRe = /CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER\s+([a-zA-Z0-9_]+)/gi;
  while ((m = trigRe.exec(content)) !== null) {
    add('trigger', `trigger:${m[1].toLowerCase()}`, m.index, m[0].slice(0, 80));
  }

  const grantRe = /^\s*GRANT\s+.+$/gim;
  while ((m = grantRe.exec(content)) !== null) {
    const line = m[0].trim();
    if (/^GRANT\s+USAGE\s+ON\s+SCHEMA/i.test(line)) continue;
    add('grant', `grant:${line.replace(/\s+/g, ' ').slice(0, 120)}`, m.index, line);
  }

  return objs;
}

function normalizeTable(t) {
  const s = String(t || '').toLowerCase();
  return s.startsWith('public.') ? s.slice(7) : s;
}

function consolidatedHas(consolidatedLower, obj) {
  const c = consolidatedLower;
  if (obj.kind === 'policy') {
    const [, rest] = obj.key.split('policy:');
    const dot = rest.lastIndexOf('.');
    const table = normalizeTable(rest.slice(0, dot));
    const name = rest.slice(dot + 1).toLowerCase();
    const patterns = [
      `create policy "${name}" on ${table}`,
      `create policy ${name} on ${table}`,
      `drop policy if exists "${name}" on ${table}`,
      `create policy "${name}" on public.${table}`,
    ];
    return patterns.some((p) => c.includes(p));
  }
  if (obj.kind === 'function') {
    const fn = obj.key.replace('function:', '');
    if (c.includes(`function ${fn}(`)) return true;
    const short = fn.split('.').pop();
    const altPrivate = `function private.${short}(`;
    const altPublic = `function public.${short}(`;
    if (c.includes(altPrivate) || c.includes(altPublic)) return true;
    return false;
  }
  if (obj.kind === 'rls_enable') {
    const tbl = obj.key.replace('rls:', '');
    return c.includes(`enable row level security`) && c.includes(tbl);
  }
  if (obj.kind === 'trigger') {
    const name = obj.key.replace('trigger:', '');
    return c.includes(`trigger ${name}`) || c.includes(`trigger ${name} `);
  }
  if (obj.kind === 'grant') {
    const g = obj.detail.toLowerCase();
    const onMatch = g.match(/\s+on\s+([a-z0-9_.]+)/i);
    if (onMatch && c.includes(onMatch[1].toLowerCase())) {
      if (g.includes(' to authenticated') && c.includes('grant') && c.includes('authenticated')) {
        return c.includes(onMatch[1].toLowerCase());
      }
    }
    return c.includes(g.slice(0, 40));
  }
  return false;
}

function main() {
  const root = findRepoRoot();
  const migDir = path.join(root, 'db/migrations');
  const consolidatedPath = path.join(migDir, CONSOLIDATED);
  const consolidated = fs.readFileSync(consolidatedPath, 'utf8');
  const consolidatedLower = consolidated.toLowerCase();

  const missing = [];
  const seen = new Set();

  for (const base of SKIPPED_BASES) {
    const rel = base;
    const full = path.join(migDir, base);
    const content = fs.readFileSync(full, 'utf8');
    for (const obj of extractObjects(rel, content)) {
      const dedupe = `${obj.kind}|${obj.key}`;
      if (seen.has(dedupe)) continue;
      seen.add(dedupe);
      if (!consolidatedHas(consolidatedLower, obj)) {
        missing.push(obj);
      }
    }
  }

  const outPath = path.join(root, 'docs/audit/CONSOLIDATED_MISSING_FROM_SKIPPED.txt');
  const lines = [
    '# Missing in 20261020000001 vs RDS-skipped migration head objects',
    `# Generated: ${new Date().toISOString().slice(0, 10)}`,
    `# Missing count: ${missing.length}`,
    '',
  ];
  for (const obj of missing) {
    lines.push(`${obj.file}:${obj.line}\t${obj.kind}\t${obj.key}`);
  }
  fs.writeFileSync(outPath, `${lines.join('\n')}\n`);
  console.log(`Wrote ${outPath} (${missing.length} missing)`);
  if (missing.length) {
    console.log('First 15:');
    missing.slice(0, 15).forEach((o) => console.log(`  ${o.file}:${o.line} ${o.kind} ${o.key}`));
  }
}

if (require.main === module) {
  main();
}

module.exports = { extractObjects, consolidatedHas, SKIPPED_BASES };