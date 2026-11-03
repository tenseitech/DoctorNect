#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

function names(rev) {
  const files = execSync(`git --no-pager ls-tree -r --name-only ${rev} frontend/test`, {
    cwd: ROOT,
    encoding: 'utf8',
  })
    .trim()
    .split('\n')
    .filter((f) => f.endsWith('.dart'));

  const set = new Set();
  const re = /\btest(?:Widgets)?\s*\(\s*['"]([^'"]+)['"]/g;
  for (const f of files) {
    const src = execSync(`git --no-pager show ${rev}:${f}`, {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 12 * 1024 * 1024,
    });
    let m;
    while ((m = re.exec(src)) !== null) {
      set.add(`${f.replace(/^frontend\/test\//, '')} :: ${m[1]}`);
    }
  }
  return set;
}

const oldRev = process.argv[2] || '5107d14';
const newRev = process.argv[3] || 'HEAD';
const old = names(oldRev);
const neu = names(newRev);
const onlyInOld = [...old].filter((x) => !neu.has(x)).sort();
const onlyInNew = [...neu].filter((x) => !old.has(x)).sort();
console.log(
  JSON.stringify(
    { oldRev, newRev, countOld: old.size, countNew: neu.size, onlyInOld, onlyInNew },
    null,
    2,
  ),
);
