#!/usr/bin/env node
'use strict';
/** Map env var names to coarse runtime readers (names only). */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');
const FILES = [
  '.env',
  '.env.example',
  '.env.migration',
  'backend/functions/.env',
  'backend/functions/.env.example',
  'backend/.env.migration.example',
  'frontend/.env.example',
];

function parseEnvKeys(filePath) {
  const keys = new Set();
  if (!fs.existsSync(filePath)) return keys;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    keys.add(t.slice(0, eq).trim());
  }
  return keys;
}

const allKeys = new Set();
const keyFiles = new Map();
for (const rel of FILES) {
  const abs = path.join(ROOT, rel);
  for (const k of parseEnvKeys(abs)) {
    allKeys.add(k);
    if (!keyFiles.has(k)) keyFiles.set(k, []);
    keyFiles.get(k).push(rel);
  }
}

const patterns = [
  { reader: 'backend/functions (process.env)', re: /process\.env\.([A-Z0-9_]+)/g, root: 'backend/functions' },
  { reader: 'backend/scripts (process.env)', re: /process\.env\.([A-Z0-9_]+)/g, root: 'backend/scripts' },
  { reader: 'scripts/ (process.env)', re: /process\.env\.([A-Z0-9_]+)/g, root: 'scripts' },
  { reader: 'services/api-gateway (process.env)', re: /process\.env\.([A-Z0-9_]+)/g, root: 'services/api-gateway' },
  { reader: 'frontend (String.fromEnvironment)', re: /String\.fromEnvironment\(\s*['"]([A-Z0-9_]+)['"]/g, root: 'frontend/lib' },
  { reader: 'frontend (bool.fromEnvironment)', re: /bool\.fromEnvironment\(\s*['"]([A-Z0-9_]+)['"]/g, root: 'frontend/lib' },
  { reader: 'frontend (dotenv via flutter_dotenv)', re: /dotenv\.(?:env|get)\[['"]([A-Z0-9_]+)['"]\]/g, root: 'frontend/lib' },
];

function scanDir(dir, re, reader, out) {
  if (!fs.existsSync(dir)) return;
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    for (const ent of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, ent.name);
      if (ent.isDirectory()) {
        if (['node_modules', 'build', '.dart_tool'].includes(ent.name)) continue;
        stack.push(p);
      } else if (/\.(js|ts|dart)$/.test(ent.name)) {
        const text = fs.readFileSync(p, 'utf8');
        let m;
        re.lastIndex = 0;
        while ((m = re.exec(text)) !== null) {
          const key = m[1];
          if (!out.has(key)) out.set(key, new Set());
          out.get(key).add(reader);
        }
      }
    }
  }
}

const readers = new Map();
for (const { reader, re, root } of patterns) {
  scanDir(path.join(ROOT, root), re, reader, readers);
}

const crypto = require('crypto');
function hashVal(filePath, key) {
  const abs = path.join(ROOT, filePath);
  if (!fs.existsSync(abs)) return null;
  for (const line of fs.readFileSync(abs, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    if (t.slice(0, eq).trim() !== key) continue;
    const val = t.slice(eq + 1).trim();
    return crypto.createHash('sha256').update(val).digest('hex').slice(0, 16);
  }
  return null;
}

const conflicts = [];
for (const key of allKeys) {
  const files = keyFiles.get(key) || [];
  if (files.length < 2) continue;
  const hashes = new Set(files.map((f) => hashVal(f, key)).filter(Boolean));
  if (hashes.size > 1) conflicts.push(key);
}

function filesFor(key) {
  return keyFiles.get(key) || [];
}

const rows = [...conflicts].sort().map((key) => ({
  variable: key,
  files: filesFor(key),
  valuesDiffer: 'yes',
  runtimeReaders: [...(readers.get(key) || [])].sort(),
}));

const payload = { conflictCount: conflicts.length, rows };
const outPath = path.join(ROOT, 'docs/audit/_audit_env_runtime.json');
fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
console.log(JSON.stringify({ written: outPath, conflictCount: conflicts.length }, null, 2));
