#!/usr/bin/env node
'use strict';
/** Flag duplicate CREATE POLICY names across db/migrations (no file edits). */
const fs = require('fs');
const path = require('path');

const MIG = path.join(__dirname, '../../db/migrations');
const files = fs.readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort();
const policyByName = new Map();

for (const f of files) {
  const text = fs.readFileSync(path.join(MIG, f), 'utf8');
  const re = /create\s+policy\s+"([^"]+)"/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    const name = m[1];
    if (!policyByName.has(name)) policyByName.set(name, []);
    policyByName.get(name).push(f);
  }
}

const dupes = [...policyByName.entries()].filter(([, arr]) => arr.length > 1);
console.log(JSON.stringify({
  migrationFiles: files.length,
  uniquePolicyNames: policyByName.size,
  duplicatePolicyNames: dupes.map(([name, migrations]) => ({ name, migrations })),
}, null, 2));
