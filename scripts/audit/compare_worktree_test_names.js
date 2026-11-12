#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const re = /\btest(?:Widgets)?\s*\(\s*['"]([^'"]+)['"]/g;

function namesFromRev(rev) {
  const set = new Set();
  if (rev === 'WORKTREE') {
    function walk(dir) {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith('.dart')) {
          const rel = path.relative(path.join(ROOT, 'frontend/test'), p).replace(/\\/g, '/');
          const src = fs.readFileSync(p, 'utf8');
          let m;
          while ((m = re.exec(src)) !== null) {
            set.add(`${rel} :: ${m[1]}`);
          }
        }
      }
    }
    walk(path.join(ROOT, 'frontend/test'));
    return set;
  }
  const files = execSync(`git ls-tree -r --name-only ${rev} frontend/test`, {
    cwd: ROOT,
    encoding: 'utf8',
  })
    .trim()
    .split('\n')
    .filter((f) => f.endsWith('.dart'));
  for (const f of files) {
    const src = execSync(`git show ${rev}:${f}`, {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 20 * 1024 * 1024,
    });
    let m;
    const rel = f.replace(/^frontend\/test\//, '');
    while ((m = re.exec(src)) !== null) {
      set.add(`${rel} :: ${m[1]}`);
    }
  }
  return set;
}

const oldRev = process.argv[2] || '5107d14';
const old = namesFromRev(oldRev);
const neu = namesFromRev('WORKTREE');
const onlyInOld = [...old].filter((x) => !neu.has(x)).sort();
const onlyInNew = [...neu].filter((x) => !old.has(x)).sort();
console.log(
  JSON.stringify(
    { oldRev, countOld: old.size, countNew: neu.size, onlyInOld, onlyInNew },
    null,
    2,
  ),
);
