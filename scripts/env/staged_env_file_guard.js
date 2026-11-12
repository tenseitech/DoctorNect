#!/usr/bin/env node
'use strict';

/**
 * Pre-commit / local guard: fail if any env-style file other than `.env.example` is staged.
 */

const { execSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const ALLOW_STAGED = new Set(['.env.example']);

function isEnvStyle(rel) {
  const base = path.basename(rel).toLowerCase();
  if (base === '.env.example') return true;
  if (base === '.env') return true;
  if (base.endsWith('.env')) return true;
  if (base.startsWith('.env.')) return true;
  return rel.includes('/.env') || rel.includes('\\.env');
}

function main() {
  let out = '';
  try {
    out = execSync('git diff --cached --name-only', { cwd: ROOT, encoding: 'utf8' });
  } catch {
    console.log('ℹ No git repo or nothing staged');
    process.exit(0);
  }

  const bad = [];
  for (const line of out.split(/\r?\n/)) {
    const rel = line.trim().replace(/\\/g, '/');
    if (!rel) continue;
    if (!isEnvStyle(rel)) continue;
    if (ALLOW_STAGED.has(path.basename(rel))) continue;
    bad.push(rel);
  }

  if (bad.length) {
    console.error('Staged env-style files are not allowed (use repo root .env locally; commit only .env.example):');
    for (const f of bad) console.error(`  - ${f}`);
    process.exit(1);
  }
  console.log('✅ Staged env file guard OK');
}

main();
