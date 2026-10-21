const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '../..');

function walk(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      if (file !== 'node_modules' && file !== '.git' && file !== '.dart_tool' && file !== 'build') {
        walk(fullPath, fileList);
      }
    } else {
      fileList.push(fullPath);
    }
  }
  return fileList;
}

const collectionsFound = new Map();
const storageUsages = [];
const triggerUsages = [];

// Regexes
const collectionRegex = /\.collection\(['"]([^'"]+)['"]\)/g;
const firestoreTriggerRegex = /functions(\.region\([^)]+\))?\.firestore\.document\(['"]([^'"]+)['"]\)/g;
const storageRegex = /(FirebaseStorage|storage\(\)|firebase_storage)/gi;

const allFiles = [
  ...walk(path.join(repoRoot, 'frontend', 'lib')),
  ...walk(path.join(repoRoot, 'backend', 'functions'))
];

for (const file of allFiles) {
  const relPath = path.relative(repoRoot, file).replace(/\\/g, '/');
  if (relPath.includes('test/') || relPath.endsWith('.test.js')) continue;

  const content = fs.readFileSync(file, 'utf8');

  let match;
  while ((match = collectionRegex.exec(content)) !== null) {
    const collName = match[1];
    if (!collectionsFound.has(collName)) {
      collectionsFound.set(collName, new Set());
    }
    collectionsFound.get(collName).add(relPath);
  }

  while ((match = firestoreTriggerRegex.exec(content)) !== null) {
    triggerUsages.push({ file: relPath, pattern: match[2] });
  }

  if (storageRegex.test(content)) {
    storageUsages.push(relPath);
  }
}

console.log('=== COLLECTIONS FOUND ===');
for (const [coll, files] of Array.from(collectionsFound.entries()).sort()) {
  console.log(`- ${coll} (used in ${files.size} files)`);
  for (const f of files) {
    console.log(`    ${f}`);
  }
}

console.log('\n=== FIRESTORE TRIGGERS FOUND ===');
for (const trig of triggerUsages) {
  console.log(`- ${trig.pattern} in ${trig.file}`);
}

console.log('\n=== FIREBASE STORAGE USAGE FILES ===');
for (const f of new Set(storageUsages)) {
  console.log(`- ${f}`);
}
