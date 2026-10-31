#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const REPO_DIR = path.resolve(__dirname, '../../frontend/lib/core/firebase/repositories');

function findMethodClose(lines, openBraceIdx) {
  let depth = 0;
  for (let j = openBraceIdx; j < lines.length; j += 1) {
    for (const ch of lines[j]) {
      if (ch === '{') depth += 1;
      if (ch === '}') depth -= 1;
    }
    if (depth === 0 && j > openBraceIdx) return j;
  }
  return lines.length - 1;
}

function pruneFile(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const methodMatch = line.match(/^(\s*)(?:@\w+\([^)]*\)\s*)?(Future<|Stream<|void |bool |String |int |List<|Map<|\w+[\w<>, ]*)\s+\w+\s*\(/);
    if (methodMatch && !line.trim().startsWith('class ') && !line.includes('=>')) {
      const indent = methodMatch[1];
      let j = i;
      while (j < lines.length && !lines[j].includes('{')) j += 1;
      if (j >= lines.length) {
        out.push(line);
        i += 1;
        continue;
      }
      const openBrace = j;
      const closeBrace = findMethodClose(lines, openBrace);

      let k = openBrace + 1;
      let returnStart = -1;
      while (k <= closeBrace) {
        const trimmed = lines[k].trimStart();
        if (trimmed.startsWith('return Supabase')) {
          returnStart = k;
          break;
        }
        k += 1;
      }

      if (returnStart >= 0) {
        let endReturn = returnStart;
        while (endReturn <= closeBrace && !lines[endReturn].includes(';')) {
          endReturn += 1;
        }
        out.push(...lines.slice(i, openBrace + 1));
        out.push(...lines.slice(returnStart, endReturn + 1));
        out.push(`${indent}}`);
        if (closeBrace + 1 < lines.length && lines[closeBrace + 1].trim() === '') {
          i = closeBrace + 2;
        } else {
          i = closeBrace + 1;
        }
        continue;
      }

      out.push(...lines.slice(i, closeBrace + 1));
      i = closeBrace + 1;
      continue;
    }
    out.push(line);
    i += 1;
  }

  let result = out.join('\n');
  const hadFirestore = result.includes('FirebaseFirestore');
  if (!hadFirestore) {
    result = result.replace(/^import 'package:cloud_firestore\/cloud_firestore\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/\.\.\/config\/doctor_patient_cutover_flag\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_paths\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_query_limits\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_read_helper\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/mappers\/[^']+\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firebase_bootstrap\.dart';\r?\n/gm, '');
  }

  // Drop private helpers that only served Firestore
  result = result.replace(/\n\s*(?:Query<Map<String, dynamic>>|List<[^>]+> _recordsFromSnapshot)[\s\S]*?\n\s\}\n/g, '\n');

  fs.writeFileSync(filePath, result, 'utf8');
  return true;
}

for (const f of fs.readdirSync(REPO_DIR).filter((x) => x.endsWith('.dart'))) {
  pruneFile(path.join(REPO_DIR, f));
  console.log('pruned', f);
}
