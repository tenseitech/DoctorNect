'use strict';

const fs = require('fs');
const path = require('path');

function findRepoRoot(startDir = __dirname) {
  let dir = path.resolve(startDir);
  for (let i = 0; i < 12; i++) {
    const marker = path.join(dir, '.env.example');
    if (fs.existsSync(marker)) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error('Could not find repo root (.env.example marker missing)');
}

module.exports = { findRepoRoot };
