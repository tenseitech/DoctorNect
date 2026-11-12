'use strict';

const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');

const PLACEHOLDER_OK = /^(|your-|placeholder|changeme|xxx|<.*>|example|test-|dummy|fake|none|false|true|\d+)$/i;

function looksSecret(key, value) {
  const v = String(value || '').trim();
  if (!v) return false;
  if (PLACEHOLDER_OK.test(v)) return false;
  if (/your-|example\.com|your-project/i.test(v)) return false;
  if (key.includes('EXAMPLE')) return false;

  if (/^-----BEGIN (RSA |EC )?PRIVATE KEY-----/m.test(v)) return true;
  if (key.includes('PASSWORD') && v.length >= 8 && !/^\*+$/.test(v)) return true;
  if ((key.includes('SECRET') || key.includes('SERVICE_ROLE') || key.includes('SERVICE_KEY')) && v.length >= 24) return true;
  if (key.startsWith('AWS_') && key.includes('KEY') && v.length >= 16 && !v.startsWith('your')) return true;
  if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/m.test(v)) return true;
  if (/^postgresql:\/\/.+:.+@/i.test(v) && !v.includes('****') && !/\[PASSWORD\]/i.test(v)) return true;
  return false;
}

function main() {
  const root = findRepoRoot();
  const examplePath = path.join(root, '.env.example');
  const parsed = parseEnvFile(examplePath);
  const flagged = [];
  for (const [key, value] of Object.entries(parsed)) {
    if (looksSecret(key, value)) flagged.push(key);
  }
  if (flagged.length) {
    console.error('❌ .env.example may contain real secrets (variable names only):');
    flagged.forEach((k) => console.error(`  - ${k}`));
    process.exit(1);
  }
  console.log('✅ .env.example secret heuristic OK');
}

main();
