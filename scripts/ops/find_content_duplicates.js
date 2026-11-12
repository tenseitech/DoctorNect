'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '../..');
const MIN_SIZE = 1024; // skip tiny files

function sha256(filePath) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(filePath));
  return h.digest('hex');
}

const tracked = execSync('git ls-files', { cwd: ROOT, encoding: 'utf8' })
  .split('\n')
  .map((l) => l.trim())
  .filter(Boolean);

const byHash = new Map();
for (const rel of tracked) {
  const abs = path.join(ROOT, rel);
  if (!fs.existsSync(abs)) continue;
  const st = fs.statSync(abs);
  if (!st.isFile() || st.size < MIN_SIZE) continue;
  const hash = sha256(abs);
  if (!byHash.has(hash)) byHash.set(hash, []);
  byHash.get(hash).push({ rel, size: st.size });
}

const dups = [...byHash.entries()].filter(([, files]) => files.length > 1);
dups.sort((a, b) => b[1][0].size - a[1][0].size);

console.log(`Identical tracked files (>=${MIN_SIZE} bytes): ${dups.length} hash groups`);
for (const [hash, files] of dups.slice(0, 40)) {
  console.log(`\nSHA256 ${hash.slice(0, 12)}… size=${files[0].size}`);
  for (const f of files) console.log(`  ${f.rel}`);
}
