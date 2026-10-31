'use strict';
const fs = require('fs');
const files = [
  'docs/ops/REMAINING_WORK.md',
  'docs/ops/PROGRESS.md',
  'docs/ops/CLEANUP_MANIFEST.md',
  'CLEANUP_REPORT.md',
];
function repl(c) {
  return c
    .replace(/`docs\/ops\/test_runs\/[^`]+`/g, '`local test output (re-run the cited command; not stored in git)`')
    .replace(/\(docs\/ops\/test_runs\/[^)]+\)/g, '(local test output — not stored in git)')
    .replace(/docs\/ops\/test_runs\/[^\s`)]+/g, 'local test output (not in repo)');
}
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  fs.writeFileSync(f, repl(fs.readFileSync(f, 'utf8')));
}
