'use strict';

const fs = require('fs');
const path = require('path');

const rpcs = [
  'accept_ambulance_request',
  'book_appointment_atomic',
  'cancel_ambulance_trip',
  'complete_ambulance_trip',
  'create_prescription_atomic',
  'decrement_review_helpful_count',
  'get_ambulance_trip_location',
  'increment_review_helpful_count',
  'reschedule_appointment_atomic',
  'update_ambulance_location',
  'update_lab_booking_status',
  'update_lab_order_status',
  'update_pharmacy_delivery_status',
];

const migrationsDir = path.resolve(__dirname, '../../db/migrations');
const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();

console.log('================================================================');
console.log('DOCTORNECT: AUDIT CLIENT RPC SECURITY AND OWNERSHIP CHECKS');
console.log('================================================================\n');

const auditResults = {};

for (const rpc of rpcs) {
  const matches = [];
  for (const file of files) {
    const fullPath = path.join(migrationsDir, file);
    const content = fs.readFileSync(fullPath, 'utf8');
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // match CREATE OR REPLACE FUNCTION [public.]<rpc>
      const createMatch = line.match(new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${rpc}\\s*\\(`, 'i'));
      if (createMatch) {
        // Find end of definition ($$ LANGUAGE ... or END; $$)
        let endIdx = i + 1;
        while (endIdx < lines.length && !lines[endIdx].includes('$$ LANGUAGE') && !lines[endIdx].match(/^\s*\$\$\s*;/)) {
          endIdx++;
        }
        const funcBody = lines.slice(i, Math.min(lines.length, endIdx + 5)).join('\n');

        const isDefiner = /SECURITY\s+DEFINER/i.test(funcBody);
        const isInvoker = /SECURITY\s+INVOKER/i.test(funcBody);
        const searchPathMatch = funcBody.match(/SET\s+search_path\s*=\s*['"]?([^;\n]*)['"]?/i);

        // Extract auth.uid() or auth.jwt() checks
        const authChecks = [];
        for (let j = i; j <= endIdx && j < lines.length; j++) {
          const l = lines[j];
          if (/auth\.(?:uid|jwt)\s*\(\)/i.test(l) || /current_profile_id\s*\(\)/i.test(l) || /is_super_admin\s*\(\)/i.test(l)) {
            authChecks.push({ line: j + 1, code: l.trim() });
          }
        }

        matches.push({
          file,
          line: i + 1,
          security: isDefiner ? 'SECURITY DEFINER' : (isInvoker ? 'SECURITY INVOKER' : 'DEFAULT (INVOKER)'),
          searchPath: searchPathMatch ? searchPathMatch[0].trim() : 'NONE (INSECURE)',
          authChecks,
        });
      }
    }
  }

  auditResults[rpc] = matches;
}

for (const [rpc, matches] of Object.entries(auditResults)) {
  console.log(`----------------------------------------------------------------`);
  console.log(`RPC: public.${rpc}`);
  if (matches.length === 0) {
    console.log(`  STATUS: NOT DEFINED IN MIGRATIONS (Client-Side Fallback)`);
    if (rpc === 'cancel_ambulance_trip') {
      console.log(`  NOTE: Database migration implements 'cancel_ambulance_broadcast' instead.`);
    } else if (rpc.includes('review_helpful_count')) {
      console.log(`  NOTE: Database migration implements trigger 'fn_sync_review_helpful_count' on review_votes.`);
    }
  } else {
    // Show latest migration definition
    const latest = matches[matches.length - 1];
    console.log(`  Latest Definition: db/migrations/${latest.file}:${latest.line}`);
    console.log(`  Execution Security: ${latest.security}`);
    console.log(`  Search Path:        ${latest.searchPath}`);
    console.log(`  Auth/Ownership Check Lines:`);
    if (latest.authChecks.length === 0) {
      console.log(`    (No explicit auth.uid()/jwt() checks detected in function lines)`);
    } else {
      for (const check of latest.authChecks) {
        console.log(`    L${check.line}: ${check.code}`);
      }
    }
    if (matches.length > 1) {
      console.log(`  Historical versions (${matches.length - 1} prior):`);
      for (let m = 0; m < matches.length - 1; m++) {
        console.log(`    - db/migrations/${matches[m].file}:${matches[m].line} (${matches[m].security})`);
      }
    }
  }
}

// Special check for reschedule_appointment_atomic in least_privilege migration
console.log('\n================================================================');
console.log('CALLER CHECK IN reschedule_appointment_atomic (db/migrations/20261025000001_least_privilege_grants_and_rls.sql)');
console.log('================================================================');
const lpContent = fs.readFileSync(path.join(migrationsDir, '20261025000001_least_privilege_grants_and_rls.sql'), 'utf8');
const lpLines = lpContent.split('\n');
for (let i = 221; i <= 248; i++) {
  console.log(`${i + 1}: ${lpLines[i]}`);
}
