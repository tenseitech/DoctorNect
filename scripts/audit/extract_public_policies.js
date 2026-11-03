'use strict';
const fs = require('fs');
const path = require('path');

const migDir = path.resolve(__dirname, '../../db/migrations');
const files = fs.readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort();

const policies = new Map();

function extractPolicies(sql, file) {
  const upper = sql.toUpperCase();
  let i = 0;
  while (i < sql.length) {
    const idx = upper.indexOf('CREATE POLICY', i);
    if (idx === -1) break;
    const rest = sql.slice(idx);
    const nameMatch = rest.match(/^CREATE POLICY\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?(\w+)/i);
    if (!nameMatch) {
      i = idx + 13;
      continue;
    }
    const policyname = nameMatch[1];
    const tablename = nameMatch[2];
    let depth = 0;
    let end = idx;
    let started = false;
    for (let j = idx; j < sql.length; j++) {
      const c = sql[j];
      if (c === '(') {
        depth++;
        started = true;
      } else if (c === ')') {
        depth--;
      } else if (c === ';' && started && depth === 0) {
        end = j + 1;
        break;
      }
    }
    const chunk = sql.slice(idx, end);
    const cmdMatch = chunk.match(/FOR\s+(SELECT|INSERT|UPDATE|DELETE|ALL)/i);
    const cmd = cmdMatch ? cmdMatch[1].toUpperCase() : 'ALL';
    const usingMatch = chunk.match(/USING\s*\(([\s\S]*?)\)\s*(?:WITH CHECK|$)/i);
    const withMatch = chunk.match(/WITH CHECK\s*\(([\s\S]*?)\)\s*;/i);
    policies.set(`${tablename}:${policyname}`, {
      tablename,
      policyname,
      cmd,
      qual: (usingMatch?.[1] || '').replace(/\s+/g, ' ').trim(),
      with_check: (withMatch?.[1] || '').replace(/\s+/g, ' ').trim(),
      source: file,
    });
    i = end;
  }

  const dropRe = /DROP POLICY IF EXISTS\s+"?([^"\s]+)"?\s+ON\s+(?:public\.)?(\w+)/gi;
  let m;
  while ((m = dropRe.exec(sql)) !== null) {
    policies.delete(`${m[2]}:${m[1]}`);
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

console.log('# Derived from db/migrations/*.sql (final CREATE POLICY wins per table/policyname)');
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
