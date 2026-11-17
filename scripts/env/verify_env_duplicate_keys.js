'use strict';

const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { verifyRootEnvFilesNoDuplicateKeys, formatDuplicateEnvReport } = require('../lib/env_duplicate_keys');

function main() {
  const root = findRepoRoot();
  const failures = verifyRootEnvFilesNoDuplicateKeys(root);
  if (!failures.length) {
    console.log('✅ No duplicate keys in root .env or .env.example');
    process.exit(0);
  }
  console.error('❌ Duplicate env keys (names and line numbers only):\n');
  for (const f of failures) {
    console.error(formatDuplicateEnvReport(f.file, f.duplicates));
  }
  console.error(
    `\nRemove duplicate assignments; keep one line per key. Production keys (PROD_*, REPLAY_*, PGRST_*, etc.) also block scripts at load time.`,
  );
  process.exit(1);
}

main();
