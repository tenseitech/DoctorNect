'use strict';

const path = require('path');
const { findRepoRoot } = require('./repo_root');
const { parseEnvFile } = require('./parse_env_file');

let loaded = false;

/**
 * Load repo root `.env` into process.env (does not override existing process.env keys).
 */
function loadRootEnv(options = {}) {
  if (loaded && !options.force) return findRepoRoot();
  const root = findRepoRoot(options.startDir);
  const envPath = path.join(root, '.env');
  const parsed = parseEnvFile(envPath, { failOnProductionDuplicateKeys: true });
  for (const [key, value] of Object.entries(parsed)) {
    if (options.override || process.env[key] === undefined || String(process.env[key]).trim() === '') {
      process.env[key] = value;
    }
  }
  loaded = true;
  return root;
}

module.exports = { loadRootEnv, findRepoRoot };
