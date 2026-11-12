'use strict';

const { execSync, spawnSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

const revList = execSync('git rev-list --objects --all', {
  cwd: ROOT,
  encoding: 'utf8',
  maxBuffer: 512 * 1024 * 1024,
});

const lines = revList.split('\n').filter(Boolean);
const objects = [];
for (const line of lines) {
  const sp = line.indexOf(' ');
  if (sp === -1) continue;
  const sha = line.slice(0, sp);
  const rest = line.slice(sp + 1);
  if (rest) objects.push({ sha, path: rest });
}

const batch = objects.map((o) => o.sha).join('\n') + '\n';
const check = spawnSync('git', ['cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)'], {
  cwd: ROOT,
  input: batch,
  encoding: 'utf8',
  maxBuffer: 512 * 1024 * 1024,
});

const sizeBySha = new Map();
for (const line of check.stdout.split('\n')) {
  if (!line.trim()) continue;
  const [sha, type, sizeStr] = line.split(' ');
  if (type === 'blob') sizeBySha.set(sha, parseInt(sizeStr, 10));
}

const blobs = objects
  .filter((o) => sizeBySha.has(o.sha))
  .map((o) => ({ ...o, size: sizeBySha.get(o.sha) }))
  .sort((a, b) => b.size - a.size);

console.log('Top 25 blobs in git history (all branches):');
for (const b of blobs.slice(0, 25)) {
  const mb = (b.size / (1024 * 1024)).toFixed(2);
  console.log(`${mb} MiB\t${b.path || b.sha}\t${b.sha.slice(0, 12)}`);
}
