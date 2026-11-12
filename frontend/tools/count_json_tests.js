'use strict';
const fs = require('fs');
const lines = fs.readFileSync(process.argv[2] || 0, 'utf8').split(/\r?\n/).filter(Boolean);
let visible = 0;
let loading = 0;
let passed = 0;
let failed = 0;
let skipped = 0;
for (const line of lines) {
  if (!line.startsWith('{')) continue;
  let ev;
  try {
    ev = JSON.parse(line);
  } catch {
    continue;
  }
  if (ev.type === 'testStart') {
    if (ev.hidden) loading++;
    else visible++;
  }
  if (ev.type === 'testDone') {
    if (ev.result === 'success') passed++;
    else if (ev.result === 'failure' || ev.result === 'error') failed++;
    else if (ev.result === 'skipped') skipped++;
  }
}
const total = passed + failed + skipped;
console.log(JSON.stringify({ visible, loading, total, passed, failed, skipped }, null, 2));
