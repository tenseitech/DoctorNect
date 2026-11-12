#!/usr/bin/env node
'use strict';

/**
 * CI-safe env policy checks (no local .env required).
 */

const { execSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

function run(script) {
  execSync(`node ${path.join('scripts/env', script)}`, { cwd: ROOT, stdio: 'inherit' });
}

function main() {
  run('verify_env_file_policy.js');
  run('guard_env_example_secrets.js');
  // Key parity needs both files — skip in CI when .env is absent
  const hasLocal = require('fs').existsSync(path.join(ROOT, '.env'));
  if (hasLocal) {
    run('verify_env_key_parity.js');
  } else {
    console.log('ℹ Skipping verify_env_key_parity.js (no local .env in CI)');
  }
  console.log('✅ CI env checks OK');
}

main();
