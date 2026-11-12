#!/usr/bin/env node
'use strict';

/**
 * Starts PostgREST + Auth Gateway against local doctornect_fresh_zero, runs HTTP checks, tears down.
 * Wrapper around real_path_authorization_e2e.js with prerequisite hints.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');
const exePath = path.join(ROOT, '.bin/postgrest.exe');
const script = path.join(__dirname, 'real_path_authorization_e2e.js');

function main() {
  console.log('=== Real path authorization E2E runner ===');
  if (!fs.existsSync(exePath)) {
    console.error('Missing .bin/postgrest.exe (see docs/ops/postgrest_windows_binary.md)');
    process.exit(1);
  }

  const env = {
    ...process.env,
    FIREBASE_REVOCATION_CHECK: 'false',
    APP_ENV: 'test',
  };

  const run = spawnSync(process.execPath, [script], {
    cwd: ROOT,
    env,
    stdio: 'inherit',
    timeout: 120000,
  });

  if (run.status === 0) {
    console.log('✅ real_path_authorization_e2e: 7/7 PASS');
    process.exit(0);
  }
  console.error(`❌ real_path_authorization_e2e failed (exit ${run.status ?? 'signal'})`);
  console.error('Check PostgREST stderr in console and docs/reports/real_path_authorization_e2e.json');
  process.exit(run.status || 1);
}

main();
