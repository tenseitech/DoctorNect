#!/usr/bin/env node
'use strict';

/**
 * Production RDS read-only preflight (all non-system schemas).
 * Delegates to prod_rds_readonly_diagnostic.js for full catalog facts.
 */

const path = require('path');
const { spawnSync } = require('child_process');

const diagnostic = path.join(__dirname, 'prod_rds_readonly_diagnostic.js');

const res = spawnSync(process.execPath, [diagnostic], {
  stdio: 'inherit',
  cwd: path.resolve(__dirname, '../..'),
});

process.exit(res.status ?? 1);