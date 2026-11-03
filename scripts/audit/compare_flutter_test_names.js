#!/usr/bin/env node
'use strict';

const fs = require('fs');

function loadNames(path) {
  const raw = fs.readFileSync(path, 'utf8');
  const names = new Set();
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    let ev;
    try {
      ev = JSON.parse(line);
    } catch {
      continue;
    }
    if (ev.type !== 'testStart' || !ev.test || !ev.test.name) continue;
    const n = String(ev.test.name).trim();
    if (n.startsWith('loading ')) continue;
    names.add(n);
  }
  return names;
}

const a = loadNames(process.argv[2]);
const b = loadNames(process.argv[3]);
const onlyA = [...a].filter((x) => !b.has(x)).sort();
const onlyB = [...b].filter((x) => !a.has(x)).sort();
console.log(JSON.stringify({ countA: a.size, countB: b.size, onlyInOld: onlyA, onlyInNew: onlyB }, null, 2));
