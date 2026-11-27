#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..', 'frontend', 'lib');
const counts = { files: 0, sites: 0, accessibleWrapper: 0 };

function walk(dir) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p);
    else if (ent.name.endsWith('.dart')) {
      const text = fs.readFileSync(p, 'utf8');
      const iconButtons = (text.match(/IconButton\s*\(/g) || []).length;
      const accessible = (text.match(/AccessibleIconButton/g) || []).length;
      if (iconButtons > 0) {
        counts.files += 1;
        counts.sites += iconButtons;
        counts.accessibleWrapper += accessible;
      }
    }
  }
}

walk(root);
counts.remainingEstimate = counts.sites - counts.accessibleWrapper;
process.stdout.write(`${JSON.stringify(counts, null, 2)}\n`);