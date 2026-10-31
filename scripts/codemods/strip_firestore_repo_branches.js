#!/usr/bin/env node
'use strict';

/**
 * Removes Firestore fallback branches from repository Dart files that start with
 *   if (DoctorPatientCutoverFlag.isEnabled) { ... return ...; }
 * and deletes the remaining Firestore implementation in that method.
 *
 * Keeps only the Supabase delegation block body (unwrap to direct return).
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const REPO_DIR = path.join(ROOT, 'frontend/lib/core/firebase/repositories');

const files = fs.readdirSync(REPO_DIR).filter((f) => f.endsWith('.dart'));

function stripFile(filePath) {
  let src = fs.readFileSync(filePath, 'utf8');
  const original = src;

  // Pattern: if (DoctorPatientCutoverFlag.isEnabled[ && ...]) { return ...; }
  src = src.replace(
    /if\s*\(\s*DoctorPatientCutoverFlag\.isEnabled(?:[^)]*)\)\s*\{\s*return\s+([\s\S]*?);\s*\}\s*\n/g,
    (match, inner) => {
      const trimmed = inner.trim();
      return `return ${trimmed};\n`;
    },
  );

  // Pattern: if (DoctorPatientCutoverFlag.isEnabled) { return expr; }  (stream)
  src = src.replace(
    /if\s*\(\s*DoctorPatientCutoverFlag\.isEnabled(?:[^)]*)\)\s*\{\s*return\s+([^;]+);\s*\}\s*\n/g,
    'return $1;\n',
  );

  // Remove unused firestore imports if cloud_firestore no longer referenced
  if (!src.includes('FirebaseFirestore') && !src.includes('FirestoreReadHelper') && !src.includes('Query<')) {
    src = src.replace(/^import 'package:cloud_firestore\/cloud_firestore\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/firestore_paths\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/firestore_query_limits\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/firestore_read_helper\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/mappers\/[^']+\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/\.\.\/config\/doctor_patient_cutover_flag\.dart';\n/m, '');
    src = src.replace(/^import '\.\.\/firebase_bootstrap\.dart';\n/m, '');
  }

  if (src !== original) {
    fs.writeFileSync(filePath, src, 'utf8');
    return true;
  }
  return false;
}

let changed = 0;
for (const f of files) {
  if (stripFile(path.join(REPO_DIR, f))) {
    console.log('stripped:', f);
    changed += 1;
  }
}
console.log(`Done. ${changed}/${files.length} files modified.`);
