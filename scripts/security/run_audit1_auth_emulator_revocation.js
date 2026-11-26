'use strict';

/**
 * SEC-04: Firebase Auth Emulator + Admin revocation (local integration, not production).
 */
const { spawnSync } = require('child_process');
const path = require('path');

const repoRoot = path.join(__dirname, '..', '..');
const testFile = path.join(repoRoot, 'services', 'api-gateway', 'test', 'firebase_revocation_emulator_integration.test.js');

const child = spawnSync(
  'npx',
  [
    '-y',
    'firebase-tools@14.4.0',
    'emulators:exec',
    '--only',
    'auth',
    '--project',
    'demo-doctornect-kyc',
    '--',
    process.execPath,
    '--test',
    testFile,
  ],
  {
    cwd: repoRoot,
    env: {
      ...process.env,
      FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
      RUN_FIREBASE_AUTH_EMULATOR_INTEGRATION: '1',
      FIREBASE_PROJECT_ID: 'demo-doctornect-kyc',
    },
    stdio: 'inherit',
    shell: true,
  },
);

process.exit(child.status === null ? 1 : child.status);