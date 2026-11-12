#!/usr/bin/env node
'use strict';
/** Phase 0 inventory — no secret values, names/paths only. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '../..');
const SKIP_DIRS = new Set([
  'node_modules', '.git', 'build', '.dart_tool', '.gradle', 'Pods',
  'DerivedData', '.idea', 'coverage', '.pub-cache', 'dist', '__pycache__',
]);

function walk(dir, rel = '') {
  const out = [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (SKIP_DIRS.has(e.name)) continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) {
      out.push({ type: 'dir', path: r });
      out.push(...walk(abs, r));
    } else {
      out.push({ type: 'file', path: r.replace(/\\/g, '/') });
    }
  }
  return out;
}

function parseEnvKeys(filePath) {
  const keys = [];
  if (!fs.existsSync(filePath)) return keys;
  const content = fs.readFileSync(filePath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const m = t.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=/);
    if (m) keys.push(m[1]);
  }
  return keys;
}

function fileHash(abs) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(abs));
  return h.digest('hex');
}

const all = walk(ROOT);
const files = all.filter((x) => x.type === 'file');
const dirs = all.filter((x) => x.type === 'dir');

const entryPoints = {
  flutterMain: fs.existsSync(path.join(ROOT, 'frontend/lib/main.dart')),
  functionsIndex: fs.existsSync(path.join(ROOT, 'backend/functions/index.js')),
  firebaseJson: fs.existsSync(path.join(ROOT, 'firebase.json')),
  pubspec: fs.existsSync(path.join(ROOT, 'frontend/pubspec.yaml')),
  dbMigrations: fs.existsSync(path.join(ROOT, 'db/migrations')),
  migrationCount: fs.existsSync(path.join(ROOT, 'db/migrations'))
    ? fs.readdirSync(path.join(ROOT, 'db/migrations')).filter((f) => f.endsWith('.sql')).length
    : 0,
};

const envCandidates = [
  '.env', '.env.example', '.env.migration',
  'backend/functions/.env', 'backend/functions/.env.example',
  'backend/.env.migration.example', 'frontend/.env.example',
];

const envMatrix = {};
for (const rel of envCandidates) {
  const abs = path.join(ROOT, rel);
  const tracked = (() => {
    try {
      const { execSync } = require('child_process');
      execSync(`git ls-files --error-unmatch "${rel.replace(/\\/g, '/')}"`, {
        cwd: ROOT,
        stdio: 'ignore',
      });
      return true;
    } catch {
      return false;
    }
  })();
  envMatrix[rel] = {
    exists: fs.existsSync(abs),
    tracked,
    keys: fs.existsSync(abs) ? parseEnvKeys(abs) : [],
  };
}

// Exact duplicate hashes (non-binary heuristic: skip >2MB)
const hashMap = new Map();
for (const f of files) {
  const abs = path.join(ROOT, f.path);
  let st;
  try {
    st = fs.statSync(abs);
  } catch {
    continue;
  }
  if (st.size > 2 * 1024 * 1024) continue;
  const ext = path.extname(f.path).toLowerCase();
  if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.woff', '.woff2', '.ttf', '.pdf'].includes(ext)) continue;
  try {
    const hash = fileHash(abs);
    if (!hashMap.has(hash)) hashMap.set(hash, []);
    hashMap.get(hash).push(f.path);
  } catch {
    /* unreadable */
  }
}
const exactDupes = [...hashMap.entries()].filter(([, paths]) => paths.length > 1);

const suffixPatterns = ['_old', '_backup', '_new', '_copy', '_v2', ' final', '(1)', '.bak', '.orig', '.tmp'];
const nearDupes = files.filter((f) => {
  const base = path.basename(f.path).toLowerCase();
  return suffixPatterns.some((s) => base.includes(s.replace(' ', ''))) || f.path.includes('_to_review');
});

console.log(JSON.stringify({
  counts: { files: files.length, dirs: dirs.length, trackedGitFiles: 1670 },
  entryPoints,
  topLevelDirs: fs.readdirSync(ROOT, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !SKIP_DIRS.has(d.name))
    .map((d) => d.name),
  envMatrix,
  exactDuplicateGroups: exactDupes.length,
  exactDuplicateSample: exactDupes.slice(0, 30).map(([hash, paths]) => ({ hash: hash.slice(0, 12), paths })),
  nearDuplicateCandidates: nearDupes.slice(0, 50).map((f) => f.path),
}, null, 2));
