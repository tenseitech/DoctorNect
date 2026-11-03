'use strict';
const fs = require('fs');
const path = require('path');

const migDir = path.resolve(__dirname, '../../db/migrations');
const files = fs.readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort();

const policies = new Map();

function stripSqlCommentsAndLiterals(sql) {
  let out = '';
  let i = 0;
  while (i < sql.length) {
    if (sql[i] === '-' && sql[i + 1] === '-') {
      while (i < sql.length && sql[i] !== '\n') i++;
      continue;
    }
    if (sql[i] === '$' && sql[i + 1] === '$') {
      const tagEnd = sql.indexOf('$$', i + 2);
      if (tagEnd === -1) break;
      out += ' '.repeat(tagEnd + 2 - i);
      i = tagEnd + 2;
      continue;
    }
    if (sql[i] === "'") {
      out += ' ';
      i++;
      while (i < sql.length) {
        if (sql[i] === "'") {
          if (sql[i + 1] === "'") {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    out += sql[i];
    i++;
  }
  return out;
}

function findBalancedEnd(sql, openParenIdx) {
  let depth = 0;
  for (let j = openParenIdx; j < sql.length; j++) {
    const c = sql[j];
    if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return j;
    }
  }
  return -1;
}

function extractClause(chunk, keyword) {
  const re = new RegExp(`\\b${keyword}\\s*\\(`, 'i');
  const m = re.exec(chunk);
  if (!m) return '';
  const open = m.index + m[0].lastIndexOf('(');
  const close = findBalancedEnd(chunk, open);
  if (close === -1) return '';
  return chunk.slice(open + 1, close).replace(/\s+/g, ' ').trim();
}

function extractPolicies(sql, file) {
  const scan = stripSqlCommentsAndLiterals(sql);
  const upper = scan.toUpperCase();
  const stmtRe = /(?:DROP POLICY IF EXISTS\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?(\w+)|CREATE POLICY\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?(\w+))/gi;
  let m;
  while ((m = stmtRe.exec(scan)) !== null) {
    if (m[1] && m[2]) {
      policies.delete(`${m[2]}:${m[1]}`);
      continue;
    }
    const policyname = m[3];
    const tablename = m[4];
    const idx = m.index;
    const semi = scan.indexOf(';', idx);
    if (semi === -1) continue;
    const chunk = scan.slice(idx, semi + 1);
    const cmdMatch = chunk.match(/FOR\s+(SELECT|INSERT|UPDATE|DELETE|ALL)/i);
    const cmd = cmdMatch ? cmdMatch[1].toUpperCase() : 'ALL';
    policies.set(`${tablename}:${policyname}`, {
      tablename,
      policyname,
      cmd,
      qual: extractClause(chunk, 'USING'),
      with_check: extractClause(chunk, 'WITH CHECK'),
      source: file,
    });
  }
}

for (const file of files) {
  extractPolicies(fs.readFileSync(path.join(migDir, file), 'utf8'), file);
}

function classify(row) {
  const blob = `${row.qual} ${row.with_check}`;
  if (!blob.includes('current_profile_id()')) {
    return 'n/a';
  }
  const checks = [];
  if (/doctor_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_doctor\(\)/.test(blob)) {
    checks.push('GAP: doctor_id without is_verified_doctor()');
  }
  if (/lab_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_lab\(\)/.test(blob)) {
    checks.push('GAP: lab_id without is_verified_lab()');
  }
  if (/medical_store_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_medical_store\(\)/.test(blob)) {
    checks.push('GAP: medical_store_id without is_verified_medical_store()');
  }
  if (/store_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_medical_store\(\)/.test(blob)) {
    checks.push('GAP: store_id without is_verified_medical_store()');
  }
  if (/owner_uid\s*=\s*\(auth\.jwt\(\)/.test(blob) || /patient_id\s*=\s*private\.current_profile_id\(\)/.test(blob)) {
    return checks.length ? checks.join('; ') : 'OK: self/onboarding row';
  }
  if (/doctor_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && /is_verified_doctor\(\)/.test(blob)) {
    return 'OK: verified doctor';
  }
  return checks.length ? checks.join('; ') : 'REVIEW: uses current_profile_id()';
}

const rows = [...policies.values()].sort(
  (a, b) => a.tablename.localeCompare(b.tablename) || a.policyname.localeCompare(b.policyname),
);

console.log('# Derived from db/migrations/*.sql (CREATE/DROP applied in file order; $$ bodies stripped)');
console.log('# Prefer live inventory: scripts/audit/pg_policies_export.sql + pg_policies_to_matrix.js');
console.log('# Previous matrix missed policies when DROP+CREATE appeared in the same migration (drops ran after creates).');
console.log('');
console.log('| schemaname | tablename | policyname | cmd | classification | qual | with_check |');
console.log('|------------|-----------|------------|-----|----------------|------|------------|');
for (const row of rows) {
  const c = classify(row);
  const esc = (s) => s.replace(/\|/g, '\\|').slice(0, 200);
  console.log(
    `| public | ${row.tablename} | ${row.policyname} | ${row.cmd} | ${c} | ${esc(row.qual)} | ${esc(row.with_check)} |`,
  );
}
