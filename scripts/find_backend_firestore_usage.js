const fs = require('fs');
const path = require('path');

const indexContent = fs.readFileSync('backend/functions/index.js', 'utf8');
const lines = indexContent.split('\n');
const exportsList = [];

for (const l of lines) {
  const m = l.match(/exports\.([a-zA-Z0-9_]+)\s*=\s*(.+)/);
  if (m) {
    exportsList.push({ name: m[1], definition: m[2] });
  }
}

const functionFiles = fs.readdirSync('backend/functions').filter(f => f.endsWith('.js') && !f.includes('test'));
const firestoreUsage = [];

for (const f of functionFiles) {
  const full = path.join('backend/functions', f);
  const content = fs.readFileSync(full, 'utf8');
  if (content.includes('admin.firestore()') || content.includes('getFirestore()') || content.includes('db.collection') || content.includes('firestore')) {
    const fnLines = content.split('\n');
    const cols = new Set();
    const calls = [];
    fnLines.forEach((l, idx) => {
      const match = l.match(/collection\(['"]([^'"]+)['"]\)/);
      if (match) {
        cols.add(match[1]);
        calls.push({ line: idx + 1, col: match[1], text: l.trim() });
      }
    });
    if (calls.length > 0) {
      firestoreUsage.push({ file: f, collections: Array.from(cols), count: calls.length, samples: calls.slice(0, 5) });
    }
  }
}

console.log('Exported functions in backend/functions/index.js:', exportsList.length);
console.log('Files with Firestore calls:', firestoreUsage.map(u => ({ file: u.file, cols: u.collections })));

fs.writeFileSync('scripts/firestore_backend_usage.json', JSON.stringify({ exportsList, firestoreUsage }, null, 2));
