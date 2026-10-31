#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '../..');
const SKIP = new Set(['node_modules', '.git', 'build', '.dart_tool', 'backups']);

function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(ent.name)) continue;
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (/\.md$/i.test(ent.name) && p.includes(`${path.sep}docs${path.sep}`)) out.push(p);
  }
  return out;
}

const files = walk(path.join(ROOT, 'docs'));
const byBase = new Map();
for (const f of files) {
  const base = path.basename(f).toLowerCase();
  if (!byBase.has(base)) byBase.set(base, []);
  byBase.get(base).push(path.relative(ROOT, f));
}

const nearNames = [];
for (const f of files) {
  const bn = path.basename(f);
  if (/FINAL|AUDIT|VERIFICATION|REPORT|PHASE_/i.test(bn)) nearNames.push(path.relative(ROOT, f));
}

console.log(JSON.stringify({
  docMdCount: files.length,
  duplicateBasenames: [...byBase.entries()].filter(([, v]) => v.length > 1).map(([k, v]) => ({ name: k, paths: v })),
  auditLikeDocs: nearNames.sort(),
}, null, 2));
