#!/usr/bin/env node
'use strict';

/**
 * QA-05 — Flutter line coverage gate (lib/ only).
 * Run after: cd frontend && flutter test --coverage
 */
const fs = require('fs');
const path = require('path');

const lcovPath = path.join(__dirname, '..', '..', 'frontend', 'coverage', 'lcov.info');
const minLinePercent = Number(process.env.FLUTTER_COVERAGE_MIN_LINES || '28');

if (!fs.existsSync(lcovPath)) {
  console.error(`Missing ${lcovPath} — run flutter test --coverage first.`);
  process.exit(1);
}

const content = fs.readFileSync(lcovPath, 'utf8');
let lf = 0;
let lh = 0;

for (const block of content.split('end_of_record')) {
  if (!block.includes('SF:')) continue;
  const sf = block.match(/^SF:(.+)$/m);
  if (!sf) continue;
  const file = sf[1].replace(/\\/g, '/');
  if (!file.includes('lib/')) continue;
  const lfM = block.match(/^LF:(\d+)$/m);
  const lhM = block.match(/^LH:(\d+)$/m);
  if (lfM && lhM) {
    lf += Number(lfM[1]);
    lh += Number(lhM[1]);
  }
}

const pct = lf === 0 ? 0 : (100 * lh) / lf;
const report = {
  scope: 'frontend/lib',
  linesFound: lf,
  linesHit: lh,
  linePercent: Number(pct.toFixed(2)),
  minRequired: minLinePercent,
  pass: pct >= minLinePercent,
};

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
process.exit(report.pass ? 0 : 1);