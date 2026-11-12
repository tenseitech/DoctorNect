#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { findRepoRoot } = require('../lib/repo_root');
const { scanTextForInfraFingerprints } = require('../lib/infra_url_policy');

const SKIP_PATH_PREFIXES = [
  'docs/archive/',
  'baseline_functions.json',
];

const SKIP_PATH_PARTS = [
  '/node_modules/',
  '\\node_modules\\',
  '/.git/',
  '/.env',
  '.pem',
  'package-lock.json',
  'pnpm-lock.yaml',
  '.png',
  '.jpg',
  '.jar',
  '.aab',
  '.apk',
  'windows/flutter/ephemeral',
  'linux/flutter/ephemeral',
];

function shouldScan(rel) {
  const p = rel.replace(/\\/g, '/');
  if (p === '.env' || p.endsWith('/.env')) return false;
  if (SKIP_PATH_PREFIXES.some((prefix) => p === prefix || p.startsWith(prefix))) return false;
  return !SKIP_PATH_PARTS.some((s) => p.includes(s.replace(/\\/g, '/')));
}

function main() {
  const root = findRepoRoot();
  const tracked = execSync('git ls-files', { cwd: root, encoding: 'utf8' })
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .filter(shouldScan);

  const allHits = [];
  for (const rel of tracked) {
    const full = path.join(root, rel);
    if (!fs.existsSync(full) || !fs.statSync(full).isFile()) continue;
    let text;
    try {
      text = fs.readFileSync(full, 'utf8');
    } catch {
      continue;
    }
    if (text.includes('\u0000')) continue;
    const hits = scanTextForInfraFingerprints(text, rel);
    allHits.push(...hits);
  }

  if (allHits.length) {
    console.error('❌ Committed infra fingerprints (use staging-project-ref / example-db.xxxxxxxx... placeholders only):');
    const seen = new Set();
    for (const h of allHits) {
      const key = `${h.path}:${h.kind}:${h.value}`;
      if (seen.has(key)) continue;
      seen.add(key);
      console.error(`  - [${h.kind}] ${h.value} in ${h.path}`);
    }
    process.exit(1);
  }
  console.log('✅ No forbidden RDS / Supabase project refs in tracked files');
}

main();
