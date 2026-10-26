'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

function findPgTool(toolName) {
  const commonPaths = [
    toolName,
    `C:\\Program Files\\PostgreSQL\\17\\bin\\${toolName}.exe`,
    `C:\\Program Files\\PostgreSQL\\16\\bin\\${toolName}.exe`,
  ];
  for (const p of commonPaths) {
    try {
      execSync(`"${p}" --version`, { stdio: 'ignore' });
      return p;
    } catch (_) {}
  }
  return null;
}

function runBackup(backupDir) {
  const dbUrl = getEnv('PROD_SUPABASE_DB_URL') || getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.error('FATAL: No Supabase DB URL found in environment.');
    process.exit(1);
  }

  const pgDump = findPgTool('pg_dump');
  if (!pgDump) {
    console.error('\n[BLOCKED] pg_dump is not available on PATH or in standard PostgreSQL paths.');
    console.error('Action: Operator must install PostgreSQL 17 client tools (see MANUAL_ACTIONS.md Item 1).');
    process.exit(1);
  }

  console.log(`\n=== Running pg_dump using ${pgDump} ===`);
  console.log(`Target: ${maskConnectionString(dbUrl)}`);
  console.log(`Destination: ${backupDir}`);

  // 1. schema_public_with_acl.sql (schema only, public + private schemas, no owner)
  const schemaWithAclFile = path.join(backupDir, 'schema_public_with_acl.sql');
  console.log('Dumping schema_public_with_acl.sql...');
  execSync(`"${pgDump}" --schema-only --no-owner --schema=public --schema=private --dbname="${dbUrl}" --file="${schemaWithAclFile}"`);
  console.log(`Created ${schemaWithAclFile} (${(fs.statSync(schemaWithAclFile).size / 1024).toFixed(1)} KB)`);

  // 2. schema_public_no_acl.sql (schema only, no owner, no privileges)
  const schemaNoAclFile = path.join(backupDir, 'schema_public_no_acl.sql');
  console.log('Dumping schema_public_no_acl.sql...');
  execSync(`"${pgDump}" --schema-only --no-owner --no-privileges --schema=public --schema=private --dbname="${dbUrl}" --file="${schemaNoAclFile}"`);
  console.log(`Created ${schemaNoAclFile} (${(fs.statSync(schemaNoAclFile).size / 1024).toFixed(1)} KB)`);

  // 3. full.dump (custom format, schema + data, no owner)
  const fullDumpFile = path.join(backupDir, 'full.dump');
  console.log('Dumping full.dump (custom format)...');
  execSync(`"${pgDump}" --format=custom --no-owner --schema=public --schema=private --dbname="${dbUrl}" --file="${fullDumpFile}"`);
  console.log(`Created ${fullDumpFile} (${(fs.statSync(fullDumpFile).size / 1024).toFixed(1)} KB)`);

  console.log('\nAll pg_dump files generated successfully!');
}

if (require.main === module) {
  const dirs = fs.readdirSync('backups').filter(d => d.startsWith('supabase_')).sort();
  const latestDir = dirs.length ? path.resolve('backups', dirs[dirs.length - 1]) : null;
  if (!latestDir) {
    console.error('No backup directory found. Run phase2_catalog_export.js first.');
    process.exit(1);
  }
  runBackup(latestDir);
}

module.exports = { runBackup, findPgTool };
