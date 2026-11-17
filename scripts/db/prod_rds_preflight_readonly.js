#!/usr/bin/env node
'use strict';

/**
 * Production RDS read-only preflight (all non-system schemas).
 * Uses database from buildRdsPoolConfig() (default **doctornect**), NOT postgres.
 * Delegates to prod_rds_readonly_diagnostic.js — always check `current_database()` in output.
 */

const path = require('path');
const { spawnSync } = require('child_process');

const diagnostic = path.join(__dirname, 'prod_rds_readonly_diagnostic.js');

const res = spawnSync(process.execPath, [diagnostic], {
  stdio: 'inherit',
  cwd: path.resolve(__dirname, '../..'),
});

process.exit(res.status ?? 1);