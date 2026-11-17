'use strict';

/**
 * One-shot: backup local env files outside repo, merge into root .env, write conflict report (names only).
 * Usage: node scripts/env/merge_local_env_files.js --execute
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');

const SOURCES = [
  { file: '.env', precedence: 1, reader: 'root .env (legacy base)' },
  { file: '.env.migration', precedence: 2, reader: 'scripts/lib/env_loader.js (migration layer)' },
  { file: 'backend/functions/.env', precedence: 3, reader: 'Cloud Functions runtime (won on duplicate)' },
];

function main() {
  const execute = process.argv.includes('--execute');
  const root = findRepoRoot();
  const date = new Date().toISOString().slice(0, 10);
  const backupDir = path.join(os.homedir(), `env_backup_${date}`);

  const merged = {};
  const origin = {};
  const conflicts = [];

  for (const src of SOURCES) {
    const full = path.join(root, src.file);
    const data = parseEnvFile(full);
    for (const [key, value] of Object.entries(data)) {
      if (Object.prototype.hasOwnProperty.call(merged, key) && merged[key] !== value) {
        conflicts.push({
          key,
          resolution: `kept ${src.reader}; discarded prior value from ${origin[key]}`,
        });
      }
      merged[key] = value;
      origin[key] = src.reader;
    }
  }

  const report = {
    generatedAt: new Date().toISOString(),
    backupDir,
    conflictCount: conflicts.length,
    conflicts,
    keyCount: Object.keys(merged).length,
  };

  const reportPath = path.join(root, 'docs', 'reports', 'env_merge_conflicts.json');
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

  console.log(`Merged ${report.keyCount} keys; conflicts: ${report.conflictCount}`);
  console.log(`Conflict report (names only): ${reportPath}`);

  if (!execute) {
    console.log('Dry-run. Re-run with --execute to write backup + root .env');
    return;
  }

  fs.mkdirSync(backupDir, { recursive: true });
  for (const src of SOURCES) {
    const full = path.join(root, src.file);
    if (fs.existsSync(full)) {
      const dest = path.join(backupDir, src.file.replace(/[\\/]/g, '__'));
      fs.copyFileSync(full, dest);
    }
  }
  fs.writeFileSync(path.join(backupDir, 'merge_report.json'), JSON.stringify(report, null, 2));

  const existing = fs.readFileSync(path.join(root, '.env'), 'utf8');
  const header = `# Merged by scripts/env/merge_local_env_files.js — backup: ${backupDir}\n`;
  const lines = [header];
  for (const key of Object.keys(merged).sort()) {
    const val = merged[key];
    const escaped = String(val).includes('\n') ? JSON.stringify(val) : val;
    lines.push(`${key}=${escaped}`);
  }
  fs.writeFileSync(path.join(root, '.env'), `${lines.join('\n')}\n`);
  console.log(`Backup: ${backupDir}`);
  console.log('Wrote merged root .env (values not logged).');
}

main();
