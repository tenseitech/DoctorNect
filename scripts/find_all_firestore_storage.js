const fs = require('fs');
const path = require('path');

const patterns = [
  'cloud_firestore',
  'FirebaseFirestore',
  'firebase_storage',
  'FirebaseStorage',
  'getFirestore',
  'admin.firestore',
  'admin.storage'
];

function scanDir(dir, results = []) {
  if (!fs.existsSync(dir)) return results;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'build') {
        scanDir(fullPath, results);
      }
    } else if (entry.name.endsWith('.dart') || entry.name.endsWith('.js') || entry.name.endsWith('.ts')) {
      const content = fs.readFileSync(fullPath, 'utf8');
      const lines = content.split('\n');
      lines.forEach((line, idx) => {
        for (const pat of patterns) {
          if (line.includes(pat)) {
            results.push({
              file: fullPath,
              lineNum: idx + 1,
              pattern: pat,
              snippet: line.trim()
            });
            break;
          }
        }
      });
    }
  }
  return results;
}

const libResults = scanDir(path.join(__dirname, '../frontend/lib'));
const testResults = scanDir(path.join(__dirname, '../frontend/test'));
const backendNonTest = scanDir(path.join(__dirname, '../backend/functions')).filter(r => !r.file.includes('test'));
const backendTest = scanDir(path.join(__dirname, '../backend/functions/test'));

fs.writeFileSync(path.join(__dirname, 'firestore_storage_inventory.json'), JSON.stringify({
  libNonTest: libResults.map(r => ({ file: path.relative(path.join(__dirname, '..'), r.file), line: r.lineNum, snippet: r.snippet })),
  test: testResults.map(r => ({ file: path.relative(path.join(__dirname, '..'), r.file), line: r.lineNum, snippet: r.snippet })),
  backendNonTest: backendNonTest.map(r => ({ file: path.relative(path.join(__dirname, '..'), r.file), line: r.lineNum, snippet: r.snippet })),
  backendTest: backendTest.map(r => ({ file: path.relative(path.join(__dirname, '..'), r.file), line: r.lineNum, snippet: r.snippet }))
}, null, 2));

console.log('Scanned inventory:');
console.log('lib/ (non-test):', libResults.length, 'matches in', new Set(libResults.map(r => r.file)).size, 'files');
console.log('test/ (frontend):', testResults.length, 'matches in', new Set(testResults.map(r => r.file)).size, 'files');
console.log('backend/functions (non-test):', backendNonTest.length, 'matches in', new Set(backendNonTest.map(r => r.file)).size, 'files');
console.log('backend/functions/test:', backendTest.length, 'matches in', new Set(backendTest.map(r => r.file)).size, 'files');
