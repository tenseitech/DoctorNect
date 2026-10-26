const fs = require('fs');
const path = require('path');
const inv = require('./firestore_storage_inventory.json');

const filesMap = {};
for (const item of inv.libNonTest) {
  if (!filesMap[item.file]) filesMap[item.file] = [];
  filesMap[item.file].push({ line: item.line, snippet: item.snippet });
}

console.log('Unique files in lib/ using Firestore / Storage:', Object.keys(filesMap).length);
const categorized = {
  doctor: [],
  patient: [],
  pharmacy: [],
  lab: [],
  ambulance: [],
  core: []
};

for (const [file, occurrences] of Object.entries(filesMap)) {
  const norm = file.replace(/\\/g, '/');
  let cat = 'core';
  if (norm.includes('doctor')) cat = 'doctor';
  else if (norm.includes('patient')) cat = 'patient';
  else if (norm.includes('pharmacy') || norm.includes('store')) cat = 'pharmacy';
  else if (norm.includes('lab')) cat = 'lab';
  else if (norm.includes('ambulance')) cat = 'ambulance';

  categorized[cat].push({ file: norm, count: occurrences.length, lines: occurrences });
}

fs.writeFileSync(path.join(__dirname, 'classified_lib_firestore.json'), JSON.stringify(categorized, null, 2));
console.log('Classification summary:');
for (const [k, v] of Object.entries(categorized)) {
  console.log(`- ${k}: ${v.length} files`);
}
