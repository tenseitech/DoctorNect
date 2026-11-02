#!/usr/bin/env node
'use strict';
/** Flag-only A/B/E/F/G scans — no deletes. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '../..');
const SKIP = new Set([
  'node_modules', '.git', 'build', '.dart_tool', '.gradle', 'Pods', 'DerivedData',
  'coverage', '.pub-cache', 'dist', '__pycache__', '.firebase',
]);
const SKIP_PREFIX = ['.agent/', '.agents/', '.cursor/'];

const SUSPICIOUS = /(_old|_bak|_copy|_v2|\.orig|\.tmp)(\.|$)/i;

function skipRel(rel) {
  const n = rel.replace(/\\/g, '/');
  if (SKIP.has(n.split('/')[0])) return true;
  return SKIP_PREFIX.some((p) => n.startsWith(p) || n.includes(`/${p}`));
}

function walk(dir, rel = '') {
  const out = [];
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (SKIP.has(e.name)) continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (skipRel(r)) continue;
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(abs, r));
    else out.push(r.replace(/\\/g, '/'));
  }
  return out;
}

function hashFile(abs) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(abs));
  return h.digest('hex');
}

const files = walk(ROOT);
const byHash = new Map();
for (const rel of files) {
  const abs = path.join(ROOT, rel);
  try {
    const st = fs.statSync(abs);
    if (!st.isFile() || st.size > 2_000_000) continue;
    const h = hashFile(abs);
    if (!byHash.has(h)) byHash.set(h, []);
    byHash.get(h).push(rel);
  } catch (_) {}
}
const exactDupes = [...byHash.entries()].filter(([, g]) => g.length > 1);

const suspiciousNames = files.filter((f) => SUSPICIOUS.test(path.basename(f)));

const lockfiles = files.filter((f) =>
  /^(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|pubspec\.lock)$/i.test(path.basename(f))
);

const firebaseConfigs = files.filter((f) =>
  /firebase\.json|\.firebaserc|firestore\.rules|firestore\.indexes|storage\.rules|analysis_options\.yaml|gradle\.properties|settings\.gradle|\.github\/workflows\//i.test(f)
);

const pubspecPath = path.join(ROOT, 'frontend/pubspec.yaml');
let pubspecAssets = [];
let pubspecFonts = [];
if (fs.existsSync(pubspecPath)) {
  const lines = fs.readFileSync(pubspecPath, 'utf8').split(/\r?\n/);
  let section = null;
  for (const line of lines) {
    if (/^\s*assets:\s*$/.test(line)) section = 'assets';
    else if (/^\s*fonts:\s*$/.test(line)) section = 'fonts';
    else if (/^\S/.test(line) && !line.startsWith(' ')) section = null;
    else if (section === 'assets') {
      const m = line.match(/-\s*(.+)/);
      if (m) pubspecAssets.push(m[1].trim());
    }
  }
}

const assetHashes = new Map();
for (const pattern of pubspecAssets) {
  const glob = pattern.replace(/\*\*/g, '%%').replace(/\*/g, '[^/]+');
  // simple: only direct file paths
  if (!pattern.includes('*')) {
    const abs = path.join(ROOT, 'frontend', pattern);
    if (fs.existsSync(abs) && fs.statSync(abs).isFile()) {
      const h = hashFile(abs);
      if (!assetHashes.has(h)) assetHashes.set(h, []);
      assetHashes.get(h).push(pattern);
    }
  }
}

const out = {
  scannedFiles: files.length,
  exactDuplicateGroups: exactDupes.length,
  exactDuplicateSample: exactDupes.slice(0, 30).map(([h, g]) => ({ hash: h.slice(0, 12), paths: g })),
  suspiciousNameCount: suspiciousNames.length,
  suspiciousNames: suspiciousNames.slice(0, 80),
  lockfiles,
  firebaseRelatedPaths: firebaseConfigs,
  pubspecAssetEntries: pubspecAssets.length,
  duplicateAssetHashGroups: [...assetHashes.entries()].filter(([, g]) => g.length > 1),
};

const outPath = path.join(ROOT, 'docs/audit/_phase1_extended_scan.json');
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
console.log(JSON.stringify({ outPath, ...out, exactDuplicateGroups: out.exactDuplicateGroups }, null, 2));
