'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '../..');

function getGitCommitDate(relPath) {
  try {
    const out = execSync(`git log -1 --format="%ci" -- "${relPath}"`, {
      cwd: rootDir,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    }).trim();
    return out || 'Untracked';
  } catch (_) {
    return 'Unknown';
  }
}

function scanCandidates() {
  const candidates = [];

  // 1. Root audit and superseded reports
  const keptRootDocs = new Set([
    'README.md',
    'ENVIRONMENTS.md',
    'PRE_LAUNCH_CHECKLIST.md',
    'DEVICE_SMOKE_TEST_CHECKLIST.md',
    'DOCTORNECT_VERIFICATION_REPORT.md',
    'RDS_PRODUCTION_CHECKLIST.md',
  ]);

  const rootEntries = fs.readdirSync(rootDir);
  for (const entry of rootEntries) {
    const fullPath = path.join(rootDir, entry);
    const stat = fs.statSync(fullPath);

    if (stat.isFile()) {
      // Generated logs
      if (entry.endsWith('.log') && !entry.startsWith('.git')) {
        candidates.push({
          path: entry,
          size: stat.size,
          lastCommitDate: getGitCommitDate(entry),
          reason: 'Generated audit/run log at repo root',
          category: 'GENERATED_LOG',
        });
      }
      // Generated baseline JSON files
      else if (['baseline_functions.json', 'live_functions.json', 'client_postgrest_usage.json'].includes(entry)) {
        candidates.push({
          path: entry,
          size: stat.size,
          lastCommitDate: getGitCommitDate(entry),
          reason: 'Generated JSON output from audit rounds; superseded or moved to .artifacts/',
          category: 'GENERATED_JSON',
        });
      }
      // Superseded docs
      else if (entry.endsWith('.md') && !keptRootDocs.has(entry) && !entry.startsWith('.')) {
        candidates.push({
          path: entry,
          size: stat.size,
          lastCommitDate: getGitCommitDate(entry),
          reason: 'Superseded audit/milestone report (superseded by DOCTORNECT_VERIFICATION_REPORT.md)',
          category: 'SUPERSEDED_DOC',
        });
      }
    }
  }

  // 2. Scan backend/functions for .bak or backup files
  const functionsDir = path.join(rootDir, 'backend/functions');
  if (fs.existsSync(functionsDir)) {
    for (const f of fs.readdirSync(functionsDir)) {
      if (f.includes('.bak') || f.includes('_old') || f.endsWith('.log')) {
        const fullPath = path.join(functionsDir, f);
        const stat = fs.statSync(fullPath);
        if (stat.isFile()) {
          const relPath = path.relative(rootDir, fullPath).replace(/\\/g, '/');
          candidates.push({
            path: relPath,
            size: stat.size,
            lastCommitDate: getGitCommitDate(relPath),
            reason: 'Temporary backup or debug log file in backend/functions',
            category: 'BACKUP_OR_LOG',
          });
        }
      }
    }
  }

  // 3. Scan frontend/lib for zero-importer Dart files
  const libDir = path.join(rootDir, 'frontend/lib');
  const allDartFiles = [];

  function collectDartFiles(dir) {
    for (const item of fs.readdirSync(dir)) {
      const full = path.join(dir, item);
      if (fs.statSync(full).isDirectory()) {
        collectDartFiles(full);
      } else if (item.endsWith('.dart')) {
        allDartFiles.push(full);
      }
    }
  }
  if (fs.existsSync(libDir)) {
    collectDartFiles(libDir);
  }

  // Read all dart files across lib and test to build import index
  const allCodeFiles = [...allDartFiles];
  const testDir = path.join(rootDir, 'frontend/test');
  function collectTestFiles(dir) {
    if (!fs.existsSync(dir)) return;
    for (const item of fs.readdirSync(dir)) {
      const full = path.join(dir, item);
      if (fs.statSync(full).isDirectory()) {
        collectTestFiles(full);
      } else if (item.endsWith('.dart')) {
        allCodeFiles.push(full);
      }
    }
  }
  collectTestFiles(testDir);

  const codeContents = allCodeFiles.map((f) => ({
    path: f,
    content: fs.readFileSync(f, 'utf8'),
  }));

  for (const dartFile of allDartFiles) {
    const filename = path.basename(dartFile);
    const relLibPath = path.relative(libDir, dartFile).replace(/\\/g, '/');
    const fullRelPath = path.relative(rootDir, dartFile).replace(/\\/g, '/');

    // Entry points that must never be considered dead
    if (
      filename.startsWith('main') ||
      filename.includes('firebase_options') ||
      relLibPath.startsWith('core/bootstrap')
    ) {
      continue;
    }

    const packageImport = `package:medibond/${relLibPath}`;
    const fileImportPattern = filename;

    let importCount = 0;
    for (const { path: cPath, content } of codeContents) {
      if (cPath === dartFile) continue;
      if (content.includes(packageImport) || content.includes(fileImportPattern)) {
        importCount++;
      }
    }

    if (importCount === 0) {
      const stat = fs.statSync(dartFile);
      candidates.push({
        path: fullRelPath,
        size: stat.size,
        lastCommitDate: getGitCommitDate(fullRelPath),
        reason: 'Zero inbound imports across frontend/lib and frontend/test',
        category: 'UNUSED_DART_FILE',
      });
    }
  }

  return candidates;
}

const candidates = scanCandidates();
console.log(JSON.stringify(candidates, null, 2));
