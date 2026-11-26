#!/usr/bin/env node
'use strict';
/** Print logical RDS endpoint for tunnel TLS/SSM (prefer *.rds.amazonaws.com over 127.0.0.1). */
const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');

const root = findRepoRoot();
const envPath = path.join(root, '.env');
if (!fs.existsSync(envPath)) process.exit(1);
const hosts = [];
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const m = line.match(/^\s*PROD_RDS_HOST\s*=\s*(.*)\s*$/);
  if (!m) continue;
  let v = m[1].trim();
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
  hosts.push(v);
}
const pick =
  hosts.find((h) => h && /\.rds\.amazonaws\.com$/i.test(h)) ||
  hosts.find((h) => h && !/^127\.0\.0\.1$/i.test(h) && !/^localhost$/i.test(h)) ||
  hosts[hosts.length - 1] ||
  '';
process.stdout.write(pick);