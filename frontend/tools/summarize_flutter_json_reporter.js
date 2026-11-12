'use strict';
/**
 * Parses `flutter test --reporter json` NDJSON (may be prefixed by pub output).
 * Visible/hidden: uses testDone.hidden (loaders mark hidden:true; real tests omit it).
 */
const fs = require('fs');
const path = process.argv[2];
if (!path) {
  console.error('Usage: node summarize_flutter_json_reporter.js <flutter_test_--reporter_json.ndjson>');
  process.exit(1);
}
function readReportText(p) {
  const buf = fs.readFileSync(p);
  // PowerShell Tee-Object may write UTF-16 LE with BOM
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) {
    return buf.slice(2).toString('utf16le');
  }
  return buf.toString('utf8');
}

let s = readReportText(path);
const proto = s.indexOf('{"protocolVersion"');
if (proto >= 0) s = s.slice(proto);
const lines = s
  .split(/\n/)
  .map((l) => l.replace(/\r$/, ''))
  .filter((l) => l.startsWith('{'));
let visibleStarts = 0;
let loadingStarts = 0;
let visibleDone = 0;
let hiddenDone = 0;
let passed = 0;
let failed = 0;
let skipped = 0;
for (const line of lines) {
  let ev;
  try {
    ev = JSON.parse(line);
  } catch {
    continue;
  }
  if (ev.type === 'testStart' && ev.test && typeof ev.test.name === 'string') {
    if (ev.test.name.startsWith('loading ')) loadingStarts++;
    else visibleStarts++;
  }
  if (ev.type === 'testDone') {
    if (ev.hidden === true) hiddenDone++;
    else visibleDone++;
    if (ev.result === 'success') passed++;
    else if (ev.result === 'failure' || ev.result === 'error') failed++;
    else if (ev.result === 'skipped') skipped++;
  }
}
const total = passed + failed + skipped;
console.log(
  JSON.stringify(
    {
      testStartsNonLoading: visibleStarts,
      testStartsLoading: loadingStarts,
      testDoneVisible: visibleDone,
      testDoneHidden: hiddenDone,
      passed,
      failed,
      skipped,
      total,
    },
    null,
    2,
  ),
);
