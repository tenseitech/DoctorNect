'use strict';

const fs = require('fs');
const { execSync } = require('child_process');

const files = execSync('git ls-files "frontend/**/*.dart"', { encoding: 'utf8' }).split('\n').map(s => s.trim()).filter(Boolean);

for (const f of files) {
  if (!fs.existsSync(f)) continue;
  const content = fs.readFileSync(f, 'utf8');
  const lines = content.split('\n');
  lines.forEach((l, idx) => {
    if (l.includes('.from(') && (l.includes('labs') || l.includes('medical_stores') || l.includes('ambulances') || l.includes('patients') || l.includes('doctors'))) {
      console.log(`${f}:${idx + 1}: ${l.trim()}`);
    }
  });
}
