const fs = require('fs');
const path = process.argv[2] || 'flutter_test_full.ndjson';
const lines = fs.readFileSync(path, 'utf8').split(/\n/).filter(Boolean);
const names = new Map();
const errors = new Map();
for (const l of lines) {
  try {
    const o = JSON.parse(l);
    if (o.type === 'testStart' && o.test) names.set(o.test.id, o.test.name);
    if (o.type === 'error' && o.testID != null) {
      errors.set(o.testID, (o.error || '') + '\n' + (o.stackTrace || '').slice(0, 300));
    }
  } catch (_) {}
}
for (const l of lines) {
  try {
    const o = JSON.parse(l);
    if (o.type === 'testDone' && o.result === 'error') {
      const id = o.testID;
      console.log('---');
      console.log(names.get(id) || id);
      console.log((errors.get(id) || o.hidden ? 'hidden loader' : '?').slice(0, 400));
    }
  } catch (_) {}
}
