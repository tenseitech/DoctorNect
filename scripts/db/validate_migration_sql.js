'use strict';

const fs = require('fs');
const path = require('path');

let parse;
try {
  ({ parse } = require('libpg-query'));
} catch (_) {
  try {
    ({ parse } = require(path.resolve(__dirname, '../../backend/functions/node_modules/libpg-query')));
  } catch (err) {
    console.error('CRITICAL: libpg-query is required to validate migration SQL.');
    console.error(err.message);
    process.exit(1);
  }
}

async function validateAllMigrations() {
  const migrationsDir = path.resolve(__dirname, '../../db/migrations');
  if (!fs.existsSync(migrationsDir)) {
    console.error(`Migrations directory not found: ${migrationsDir}`);
    process.exit(1);
  }

  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  console.log(`\n======================================================`);
  console.log(`DoctorNect Migration SQL Validator (libpg-query AST parser)`);
  console.log(`Scanning ${files.length} migration files in db/migrations/`);
  console.log(`======================================================\n`);

  let failures = 0;
  let totalStatements = 0;

  for (const file of files) {
    const fullPath = path.join(migrationsDir, file);
    const sqlContent = fs.readFileSync(fullPath, 'utf8');

    try {
      const result = await parse(sqlContent);
      const stmtCount = Array.isArray(result?.stmts) ? result.stmts.length : 0;
      totalStatements += stmtCount;
      console.log(`PASS  ${file} (${stmtCount} statements)`);
    } catch (parseErr) {
      failures++;
      console.error(`FAIL  ${file}`);
      console.error(`      Error: ${parseErr.message}`);
      if (parseErr.cursorPosition) {
        console.error(`      Cursor position: ${parseErr.cursorPosition}`);
      }
    }
  }

  console.log(`\n------------------------------------------------------`);
  console.log(`Validation Summary:`);
  console.log(`  Total Migration Files: ${files.length}`);
  console.log(`  Total Parsed AST Statements: ${totalStatements}`);
  console.log(`  Failures: ${failures}`);
  console.log(`------------------------------------------------------\n`);

  if (failures > 0) {
    process.exit(1);
  }
}

validateAllMigrations().catch((err) => {
  console.error('Unexpected validation failure:', err);
  process.exit(1);
});
