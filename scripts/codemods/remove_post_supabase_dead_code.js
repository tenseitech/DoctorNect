#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const REPO_DIR = path.resolve(__dirname, '../../frontend/lib/core/firebase/repositories');

const METHOD_HEAD =
  /^(\s*)(?:@\w+(?:\([^)]*\))?\s*)*((?:Future|Stream|void|bool|String|int|double|num|List|Map|Set|dynamic)[^(\n]*)\s+\w+\s*\(/;

function findMethodClose(lines, openBraceIdx) {
  let depth = 1;
  for (let j = openBraceIdx + 1; j < lines.length; j += 1) {
    for (const ch of lines[j]) {
      if (ch === '{') depth += 1;
      if (ch === '}') depth -= 1;
    }
    if (depth === 0) return j;
  }
  return lines.length - 1;
}

function findMethodBodyOpenBrace(lines, startIdx) {
  let paren = 0;
  let started = false;
  for (let j = startIdx; j < lines.length; j += 1) {
    const line = lines[j];
    for (const ch of line) {
      if (ch === '(') {
        paren += 1;
        started = true;
      } else if (ch === ')') {
        paren -= 1;
      }
    }
    if (started && paren === 0 && /\)\s*(?:async\s*)?\{\s*$/.test(line.trim())) {
      return j;
    }
  }
  return -1;
}

function findReturnStatementEnd(lines, returnStart, closeBrace) {
  let paren = 0;
  for (let k = returnStart; k <= closeBrace; k += 1) {
    const line = lines[k];
    for (let c = 0; c < line.length; c += 1) {
      const ch = line[c];
      if (ch === '(') paren += 1;
      if (ch === ')') paren -= 1;
      if (ch === ';' && paren === 0) return k;
    }
  }
  return closeBrace;
}

function stripFile(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  const out = [];
  let i = 0;
  let changed = false;

  while (i < lines.length) {
    const line = lines[i];
    const methodMatch = line.match(METHOD_HEAD);
    if (methodMatch && !line.trim().startsWith('class ')) {
      const openBrace = findMethodBodyOpenBrace(lines, i);
      if (openBrace >= 0) {
        const closeBrace = findMethodClose(lines, openBrace);
        let returnStart = -1;
        for (let k = openBrace + 1; k <= closeBrace; k += 1) {
          const t = lines[k].trimStart();
          if (t.startsWith('return Supabase') || t.startsWith('return supabase')) {
            returnStart = k;
            break;
          }
        }
        if (returnStart >= 0) {
          const returnEnd = findReturnStatementEnd(lines, returnStart, closeBrace);
          out.push(...lines.slice(i, openBrace + 1));
          out.push(...lines.slice(returnStart, returnEnd + 1));
          out.push(`${methodMatch[1]}}`);
          i = closeBrace + 1;
          changed = true;
          continue;
        }
        out.push(...lines.slice(i, closeBrace + 1));
        i = closeBrace + 1;
        continue;
      }
    }
    out.push(line);
    i += 1;
  }

  let result = out.join('\n');
  if (!result.includes('FirebaseFirestore')) {
    result = result.replace(/^import 'package:cloud_firestore\/cloud_firestore\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/\.\.\/config\/doctor_patient_cutover_flag\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_paths\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_query_limits\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firestore_read_helper\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/mappers\/[^']+\.dart';\r?\n/gm, '');
    result = result.replace(/^import '\.\.\/firebase_bootstrap\.dart';\r?\n/gm, '');
  }

  if (changed) {
    fs.writeFileSync(filePath, result, 'utf8');
  }
  return changed;
}

let n = 0;
for (const f of fs.readdirSync(REPO_DIR).filter((x) => x.endsWith('.dart'))) {
  if (stripFile(path.join(REPO_DIR, f))) {
    console.log('cleaned', f);
    n += 1;
  }
}
console.log(`Done. ${n} files cleaned.`);
