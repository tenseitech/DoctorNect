'use strict';

const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

const functionsDir = path.resolve(__dirname, '../backend/functions');
const testFiles = [
  'test/client_payload_replay.rules.test.js',
  'test/client_read_replay.rules.test.js',
  'test/firestore_directory_and_appointments.rules.test.js',
  'test/firestore_reviews.rules.test.js',
  'test/storage_doctor_kyc.rules.test.js',
  'test/storage_live_app_paths.rules.test.js',
  'test/storage_provider_kyc.rules.test.js',
  'test/sync_dead_letters.rules.test.js',
  'test/doctor_slots_emulator.test.js',
  'test/sync_to_firestore_emulator.test.js',
];

console.log('Running rules and emulator test suites in backend/functions:');
testFiles.forEach(f => console.log(`  - ${f}`));

const child = spawn(
  process.execPath,
  ['--test', '--test-concurrency=1', ...testFiles],
  {
    cwd: functionsDir,
    stdio: 'inherit',
    env: { ...process.env, FIREBASE_PROJECT_ID: 'demo-doctornect-test' },
  }
);

child.on('exit', (code, signal) => {
  if (code !== 0) {
    process.exit(code || 1);
  }
  process.exit(0);
});

