#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../frontend/lib');
const ROLES = ['doctor', 'patient', 'pharmacy', 'lab', 'ambulance'];
const map = new Map();

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p);
    else if (ent.name.endsWith('.dart')) {
      const rel = path.relative(ROOT, p).replace(/\\/g, '/');
      const roleHits = ROLES.filter((r) => rel.includes(`/features/${r}/`) || rel.startsWith(`features/${r}/`));
      if (roleHits.length === 0) continue;
      const base = ent.name;
      if (!map.has(base)) map.set(base, []);
      map.get(base).push({ rel, roles: roleHits });
    }
  }
}

walk(ROOT);

const crossRole = [];
for (const [base, entries] of map) {
  const roles = new Set(entries.flatMap((e) => e.roles));
  if (entries.length > 1 && roles.size > 1) {
    crossRole.push({ file: base, roleCount: roles.size, paths: entries.map((e) => e.rel) });
  }
}

crossRole.sort((a, b) => b.paths.length - a.paths.length);
console.log(JSON.stringify({ crossRoleBasenameGroups: crossRole.length, top: crossRole.slice(0, 30) }, null, 2));
