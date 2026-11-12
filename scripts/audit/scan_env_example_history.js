#!/usr/bin/env node
'use strict';

/**
 * Scan git history of env example templates for values that look real (names only in output).
 * Never prints secret values.
 */

const { execSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const FILES = [
  'backend/functions/.env.example',
  'backend/functions/.secret.local.example',
  '.env.migration.example',
  'backend/functions/.env.migration.example',
];

const PLACEHOLDER =
  /^(your[-_]|changeme|xxx|placeholder|example|todo|replace|insert|<|\(|\)|none|test[-_]?key?|dummy|sk_test|pk_test|localhost|127\.0\.0\.1|postgres:\/\/postgres:postgres)/i;

function looksReal(name, rawVal) {
  const val = String(rawVal || '').trim();
  if (!val || val.length === 0) return false;
  if (val.startsWith('#')) return false;
  if (PLACEHOLDER.test(val)) return false;
  if (/^your-project-ref\.supabase\.co$/i.test(val)) return false;
  if (val === 'your-anon-key' || val === 'your-service-role-key') return false;

  if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(val)) return true;
  if (/^rzp_live_/i.test(val)) return true;
  if (/^AKIA[0-9A-Z]{16}$/.test(val)) return true;
  if (/\.supabase\.co/i.test(val) && !/your-project-ref/i.test(val)) return true;
  if (val.length >= 32 && /^[A-Za-z0-9+/=_-]+$/.test(val)) return true;
  if (/^postgres(ql)?:\/\//i.test(val) && !/127\.0\.0\.1|localhost|:54322/.test(val)) {
    return true;
  }
  if (/password|secret|token|apikey|api_key/i.test(name) && val.length >= 12 && !PLACEHOLDER.test(val)) {
    return true;
  }
  return false;
}

function parseAddedLines(patch) {
  const added = [];
  for (const line of patch.split('\n')) {
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    const body = line.slice(1).trim();
    if (!body || body.startsWith('#')) continue;
    const eq = body.indexOf('=');
    if (eq === -1) continue;
    const key = body.slice(0, eq).trim();
    if (!key || key.startsWith('#')) continue;
    const val = body.slice(eq + 1).trim();
    added.push({ key, val });
  }
  return added;
}

function main() {
  const existingFiles = FILES.filter((f) => {
    try {
      execSync(`git --no-pager cat-file -e HEAD:${f}`, { cwd: ROOT, stdio: 'ignore' });
      return true;
    } catch {
      return fsExists(f);
    }
  });

  function fsExists(f) {
    try {
      require('fs').accessSync(path.join(ROOT, f));
      return true;
    } catch {
      return false;
    }
  }

  const hits = [];
  for (const file of FILES) {
    let log;
    try {
      log = execSync(`git --no-pager log --all -p --follow -- "${file}"`, {
        cwd: ROOT,
        encoding: 'utf8',
        maxBuffer: 50 * 1024 * 1024,
      });
    } catch {
      continue;
    }
    let commit = 'unknown';
    for (const line of log.split('\n')) {
      if (line.startsWith('commit ')) {
        commit = line.slice(7).trim();
      } else if (line.startsWith('diff --git')) {
        // next commit block handled by commit line
      }
      if (line.startsWith('+') && !line.startsWith('+++')) {
        const body = line.slice(1).trim();
        if (body.startsWith('#')) continue;
        const eq = body.indexOf('=');
        if (eq === -1) continue;
        const key = body.slice(0, eq).trim();
        if (!key || key.startsWith('#')) continue;
        const val = body.slice(eq + 1).trim();
        if (looksReal(key, val)) {
          hits.push({ commit, file, key });
        }
      }
    }
  }

  const dedup = new Map();
  for (const h of hits) {
    dedup.set(`${h.commit}:${h.file}:${h.key}`, h);
  }

  for (const h of dedup.values()) {
    console.log(`${h.commit}\t${h.file}\tvalue looks real: ${h.key} only`);
  }
}

main();
