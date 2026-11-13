'use strict';

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');
const { verifyRootEnvFilesNoDuplicateKeys, formatDuplicateEnvReport } = require('../lib/env_duplicate_keys');

function envKeys(filePath) {
  return new Set(Object.keys(parseEnvFile(filePath)));
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

  const examplePath = path.join(root, '.env.example');
  const envPath = path.join(root, '.env');

  const exampleKeys = envKeys(examplePath);
  const envReal = fs.existsSync(envPath) ? envKeys(envPath) : new Set();

  const missingInExample = [...envReal].filter((k) => !exampleKeys.has(k)).sort();
  const missingInEnv = [...exampleKeys].filter((k) => !envReal.has(k)).sort();

  let fail = false;
  if (missingInExample.length) {
    fail = true;
    console.error(`Keys in .env missing from .env.example (${missingInExample.length}):`);
    missingInExample.forEach((k) => console.error(`  - ${k}`));
  }
  if (missingInEnv.length) {
    fail = true;
    console.error(`Keys in .env.example missing from .env (${missingInEnv.length}) — add placeholders or fill .env:`);
    missingInEnv.forEach((k) => console.error(`  - ${k}`));
  }
  if (!fail) {
    console.log(`✅ .env and .env.example key parity OK (${exampleKeys.size} keys)`);
  }
  process.exit(fail ? 1 : 0);
}

main();
