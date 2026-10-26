const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const searchDirs = [
  path.join(rootDir, 'frontend', 'lib'),
  path.join(rootDir, 'backend', 'functions'),
];

const patterns = [
  'cloud_firestore',
  'FirebaseFirestore',
  'firebase_storage',
  'FirebaseStorage',
  'getFirestore',
  'admin.firestore()',
  'admin.storage()',
];

function walkDir(dir, fileList = []) {
  if (!fs.existsSync(dir)) return fileList;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'build') {
        walkDir(fullPath, fileList);
      }
    } else if (entry.isFile() && (entry.name.endsWith('.dart') || entry.name.endsWith('.js') || entry.name.endsWith('.ts'))) {
      fileList.push(fullPath);
    }
  }
  return fileList;
}

const allFiles = [];
for (const dir of searchDirs) {
  walkDir(dir, allFiles);
}

const results = {};
for (const pattern of patterns) {
  results[pattern] = { matches: 0, files: 0, fileNames: [] };
}

for (const file of allFiles) {
  const content = fs.readFileSync(file, 'utf8');
  for (const pattern of patterns) {
    let count = 0;
    let pos = 0;
    while ((pos = content.indexOf(pattern, pos)) !== -1) {
      count++;
      pos += pattern.length;
    }
    if (count > 0) {
      results[pattern].matches += count;
      results[pattern].files++;
      results[pattern].fileNames.push(path.relative(rootDir, file));
    }
  }
}

console.log('=== Firestore / Firebase Storage Reference Counts ===');
console.table(Object.entries(results).map(([pattern, data]) => ({
  pattern,
  matchCount: data.matches,
  fileCount: data.files,
})));
