const fs = require('fs');
const path = require('path');
const classified = require('./classified_lib_firestore.json');

for (const [module, files] of Object.entries(classified)) {
  console.log(`\n=== Module: ${module.toUpperCase()} (${files.length} files) ===`);
  for (const f of files) {
    console.log(`- ${f.file} (${f.count} refs):`);
    for (const l of f.lines.slice(0, 3)) {
      console.log(`    L${l.line}: ${l.snippet}`);
    }
  }
}
