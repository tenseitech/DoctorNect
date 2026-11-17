'use strict';

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');

const root = findRepoRoot();
const target = path.join(root, 'backend', 'functions', '.env');
if (fs.existsSync(target)) {
  fs.unlinkSync(target);
  console.log('Removed generated backend/functions/.env');
}
