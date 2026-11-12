/**
 * DoctorNect: Firebase Identity Smoke Test Runner
 * 
 * Usage:
 *   node backend/scripts/run_firebase_identity_smoke_test.js
 * 
 * Executes backend/supabase/tests/firebase_identity_smoke_test.sql against the local
 * Supabase Postgres database (via docker exec supabase_db_doctor) and validates that
 * all simulated Firebase JWT claims, RLS policies, column locks, atomic booking, and
 * 22P02 immunity assertions pass.
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SQL_FILE = path.resolve(__dirname, '../supabase/tests/firebase_identity_smoke_test.sql');

if (!fs.existsSync(SQL_FILE)) {
  console.error(`ERROR: SQL smoke test file not found at ${SQL_FILE}`);
  process.exit(1);
}

console.log('Running Firebase Identity Smoke Test against local database...');
console.log(`Test script: ${SQL_FILE}\n`);

try {
  const sqlContent = fs.readFileSync(SQL_FILE, 'utf8');
  const output = execSync('docker exec -i supabase_db_doctor psql -U postgres -d postgres', {
    input: sqlContent,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe']
  });

  console.log(output);

  // Validate results table
  const lines = output.split('\n');
  const resultRows = lines.filter(l => /^\s*5[a-z0-9-]+\s*\|/.test(l));

  if (resultRows.length === 0) {
    console.error('FAIL: No smoke test results were returned from psql execution.');
    process.exit(1);
  }

  const failedRows = resultRows.filter(l => l.includes('| FAIL'));

  if (failedRows.length > 0) {
    console.error(`\nFAILED: ${failedRows.length} test(s) failed:`);
    failedRows.forEach(r => console.error(r));
    process.exit(1);
  }

  console.log(`\nSUCCESS: All ${resultRows.length} smoke tests PASSED cleanly.`);
  process.exit(0);
} catch (err) {
  console.error('Execution error:', err.stderr ? err.stderr.toString() : err.message);
  process.exit(1);
}
