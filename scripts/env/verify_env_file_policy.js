'use strict';

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { verifyRootEnvFilesNoDuplicateKeys, formatDuplicateEnvReport } = require('../lib/env_duplicate_keys');

const EXCLUDED_DIRS = new Set(['node_modules', '.git', 'build', '.dart_tool', '.gradle', 'coverage']);

function walkEnvFiles(dir, root, out) {
  if (!fs.existsSync(dir)) return;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (EXCLUDED_DIRS.has(ent.name)) continue;
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      walkEnvFiles(full, root, out);
      continue;
    }
    const rel = path.relative(root, full).replace(/\\/g, '/');
    if (ent.name === 'flutter_native_integration.env') continue;
    if (/\/ephemeral\//i.test(rel)) continue;
    if (
      ent.name === '.env' ||
      ent.name === '.env.example' ||
      ent.name.startsWith('.env.') ||
      (ent.name.endsWith('.env') && !ent.name.includes('integration'))
    ) {
      out.push(rel);
    }
  }
}

function main() {
  const root = findRepoRoot();
  const dupFailures = verifyRootEnvFilesNoDuplicateKeys(root);
  if (dupFailures.length) {
    console.error('❌ Duplicate env keys (names and line numbers only):\n');
    for (const f of dupFailures) {
      console.error(formatDuplicateEnvReport(f.file, f.duplicates));
    }
    process.exit(1);
  }

  const found = [];
  walkEnvFiles(root, root, found);

  const allowed = new Set(['.env', '.env.example']);
  const violations = found.filter((f) => !allowed.has(f));

  console.log('Env-style files in repo tree:');
  found.forEach((f) => console.log(`  ${f}`));

  if (violations.length) {
    console.error(`\n❌ Policy violation: only root .env and .env.example allowed; found ${violations.length} extra file(s).`);
    violations.forEach((f) => console.error(`  - ${f}`));
    process.exit(1);
  }
  console.log('\n✅ Env file policy: exactly root .env + .env.example');
}

main();
