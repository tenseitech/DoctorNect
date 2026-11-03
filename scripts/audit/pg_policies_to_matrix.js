'use strict';
/**
 * Usage:
 *   psql "$STAGING_SUPABASE_DB_URL" -f scripts/audit/pg_policies_export.sql --csv > pg_policies.csv
 *   node scripts/audit/pg_policies_to_matrix.js pg_policies.csv > docs/audit/RLS_POLICY_GAP_MATRIX_LIVE.md
 */
const fs = require('fs');

const path = process.argv[2];
if (!path) {
  console.error('Usage: node pg_policies_to_matrix.js <pg_policies.csv>');
  process.exit(1);
}

const raw = fs.readFileSync(path, 'utf8');
const lines = raw.split(/\r?\n/).filter(Boolean);
const header = lines.shift();

function parseCsvLine(line) {
  const out = [];
  let cur = '';
  let inQ = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') {
      if (inQ && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else inQ = !inQ;
    } else if (c === ',' && !inQ) {
      out.push(cur);
      cur = '';
    } else cur += c;
  }
  out.push(cur);
  return out;
}

function classify(qual, withCheck) {
  const blob = `${qual || ''} ${withCheck || ''}`;
  if (!blob.includes('current_profile_id()')) return 'n/a';
  const gaps = [];
  if (/doctor_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_doctor\(\)/.test(blob)) {
    gaps.push('GAP: doctor_id without is_verified_doctor()');
  }
  if (/lab_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_lab\(\)/.test(blob)) {
    gaps.push('GAP: lab_id without is_verified_lab()');
  }
  if (/medical_store_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_medical_store\(\)/.test(blob)) {
    gaps.push('GAP: medical_store_id without is_verified_medical_store()');
  }
  if (/store_id\s*=\s*private\.current_profile_id\(\)/.test(blob) && !/is_verified_medical_store\(\)/.test(blob)) {
    gaps.push('GAP: store_id without is_verified_medical_store()');
  }
  if (gaps.length) return gaps.join('; ');
  if (/owner_uid|patient_id\s*=\s*private\.current_profile_id\(\)/.test(blob)) return 'OK: self/onboarding';
  return 'REVIEW: uses current_profile_id()';
}

console.log('# Live pg_policies matrix (staging export)');
console.log('');
console.log('| schemaname | tablename | policyname | cmd | classification | qual | with_check |');

for (const line of lines) {
  const [schemaname, tablename, policyname, cmd, qual, withCheck] = parseCsvLine(line);
  const esc = (s) => String(s || '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
  console.log(
    `| ${schemaname} | ${tablename} | ${policyname} | ${cmd} | ${classify(qual, withCheck)} | ${esc(qual).slice(0, 200)} | ${esc(withCheck).slice(0, 200)} |`,
  );
}
