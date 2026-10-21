'use strict';
const { execSync } = require('child_process');

// Targets read from gitignored demo_phones.json or default target array
let numbers = [];
try {
  const cfg = require('./demo_phones.json');
  if (Array.isArray(cfg)) numbers = cfg;
  else if (cfg.phones && Array.isArray(cfg.phones)) numbers = cfg.phones;
  else if (typeof cfg === 'object') numbers = Object.values(cfg).flat();
} catch (_) {
  // Fallback to legacy targets
  numbers = ['7058809803', '7666892394', '9359503874', '9409858233', '9307583929'];
}

console.log('=== WORKING TREE MATCHES (FILE PATHS ONLY) ===');
const workingTreeFiles = new Set();
for (const num of numbers) {
  try {
    const out = execSync(`git grep -l "${num}"`, { encoding: 'utf8' });
    out.trim().split('\n').filter(Boolean).forEach(f => workingTreeFiles.add(f.trim()));
  } catch (_) {}
}
for (const file of Array.from(workingTreeFiles).sort()) {
  console.log(`FILE: ${file}`);
}

console.log('\n=== GIT HISTORY COMMITS AND FILES (HASHES & PATHS ONLY) ===');
const commitMap = new Map();
for (const num of numbers) {
  try {
    const out = execSync(`git log --all -S"${num}" --name-only --format="COMMIT:%H"`, { encoding: 'utf8' });
    let currentCommit = null;
    for (const line of out.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      if (trimmed.startsWith('COMMIT:')) {
        currentCommit = trimmed.slice(7);
      } else if (currentCommit) {
        if (!commitMap.has(currentCommit)) {
          commitMap.set(currentCommit, new Set());
        }
        commitMap.get(currentCommit).add(trimmed);
      }
    }
  } catch (_) {}
}

for (const [commit, files] of commitMap.entries()) {
  console.log(`COMMIT: ${commit}`);
  for (const f of Array.from(files).sort()) {
    console.log(`  file: ${f}`);
  }
}
