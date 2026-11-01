#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const logPath = process.argv[2] || path.join(__dirname, '../../docs/_emulator_test_run.log');
const outPath = process.argv[3] || path.join(__dirname, '../../docs/audit/baseline_failing_tests.txt');
const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
const names = new Set();
for (const line of lines) {
  const m = line.match(/^\s*✖\s+(.+?)\s*\(\d+/);
  if (m) names.add(m[1].trim());
}
const header = [
  '# Backend npm test failures under Firestore+Storage emulators (demo-doctornect-test)',
  '# Captured: 2026-10-31. Totals: 735 tests, 591 pass, 139 fail, 5 skipped (Docker Postgres off).',
  '# Command: npx firebase-tools emulators:exec --only firestore,storage --project demo-doctornect-test',
  '#          npm test --prefix backend/functions',
  '# Diff this file after SQL/rules/config cleanup phases.',
  '',
].join('\n');
fs.writeFileSync(outPath, `${header}${[...names].sort().map((n) => `FAIL :: ${n}`).join('\n')}\n`);
console.log(JSON.stringify({ uniqueFailures: names.size, outPath }, null, 2));
