const fs = require('fs');
const path = require('path');

const inv = require('./firestore_storage_inventory.json');

const filesMap = {};
for (const item of inv.libNonTest) {
  const normFile = item.file.replace(/\\/g, '/');
  if (!filesMap[normFile]) filesMap[normFile] = [];
  filesMap[normFile].push({ line: item.line, snippet: item.snippet });
}

const report = [];

for (const [filePath, occs] of Object.entries(filesMap)) {
  const fullPath = path.resolve(__dirname, '..', filePath);
  let content = '';
  if (fs.existsSync(fullPath)) {
    content = fs.readFileSync(fullPath, 'utf8');
  }

  // Determine role/module
  let moduleName = 'Core / Shared';
  if (filePath.includes('/doctor/')) moduleName = 'Doctor';
  else if (filePath.includes('/patient/')) moduleName = 'Patient';
  else if (filePath.includes('/pharmacy/')) moduleName = 'Pharmacy';
  else if (filePath.includes('/lab/')) moduleName = 'Lab';
  else if (filePath.includes('/ambulance/')) moduleName = 'Ambulance';

  // Determine runtime reachability
  let category = '';
  let rationale = '';

  const isUI = filePath.includes('/widgets/') || filePath.includes('/screens/') || filePath.includes('/presentation/');
  const hasCutoverGuard = content.includes('DoctorPatientCutoverFlag.isEnabled') || content.includes('USE_SUPABASE_DB_DOCTOR_PATIENT');
  const hasDebugHook = content.includes('debugFirestore') || content.includes('@visibleForTesting');

  if (isUI) {
    category = 'Runtime-Reachable (UI)';
    rationale = 'Active UI presentation screen/widget directly referencing Firestore';
  } else if (hasCutoverGuard) {
    category = 'Guarded Legacy (Dead in Cutover)';
    rationale = 'Guarded by DoctorPatientCutoverFlag.isEnabled; executes Supabase branch at runtime';
  } else if (filePath.includes('/repositories/')) {
    category = 'Legacy Repository';
    rationale = 'Legacy repository implementation or fallback branch';
  } else if (filePath.includes('/services/')) {
    category = 'Service';
    rationale = 'Service-level Firestore or Storage reference';
  } else {
    category = 'Other / Shared Utility';
    rationale = 'Shared utility, model, or helper';
  }

  report.push({
    file: filePath,
    module: moduleName,
    lineCount: occs.length,
    firstLine: occs[0].line,
    lines: occs.map(o => o.line).join(', '),
    category,
    rationale
  });
}

// Sort by category, then module, then file
report.sort((a, b) => a.category.localeCompare(b.category) || a.module.localeCompare(b.module) || a.file.localeCompare(b.file));

fs.writeFileSync(path.join(__dirname, 'detailed_lib_firestore_classification.json'), JSON.stringify(report, null, 2));

console.log(`Classified ${report.length} files:`);
const catCounts = {};
for (const r of report) {
  catCounts[r.category] = (catCounts[r.category] || 0) + 1;
}
console.table(catCounts);
