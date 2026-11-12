#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const logPath = process.argv[2] || path.join(__dirname, '../../docs/_emulator_test_run.log');

function defaultOutPath() {
  const runsDir = path.join(__dirname, '../../docs/audit/_runs');
  fs.mkdirSync(runsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(runsDir, `backend_failures_${stamp}.txt`);
}

function assertSafeOutPath(outPath) {
  const base = path.basename(outPath).toLowerCase();
  if (base.startsWith('baseline_') && base.endsWith('.txt')) {
    console.error(
      `Refusing to write baseline file: ${outPath}\n`
      + 'Use docs/audit/_runs/ (default) or another non-baseline path.',
    );
    process.exit(1);
  }
}

const outPath = process.argv[3] || defaultOutPath();
assertSafeOutPath(outPath);

if (!fs.existsSync(logPath)) {
  console.error(`Log file not found: ${logPath}`);
  process.exit(1);
}

const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
const names = new Set();
for (const line of lines) {
  const m = line.match(/^\s*✖\s+(.+?)\s*\(\d+/);
  if (m) names.add(m[1].trim());
}
const header = [
  '# Backend npm test failures extracted from emulator/unit test log',
  `# Source log: ${path.relative(path.join(__dirname, '../..'), logPath).replace(/\\/g, '/')}`,
  `# Captured: ${new Date().toISOString().slice(0, 10)}`,
  '# Diff against docs/audit/baseline_failing_tests.txt manually after cleanup phases.',
  '',
].join('\n');
fs.writeFileSync(outPath, `${header}${[...names].sort().map((n) => `FAIL :: ${n}`).join('\n')}\n`);
console.log(JSON.stringify({ uniqueFailures: names.size, outPath }, null, 2));
