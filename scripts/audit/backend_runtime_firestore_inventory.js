#!/usr/bin/env node
'use strict';

/**
 * Production reachability inventory for Firestore references in Cloud Functions runtime JS.
 * Output: docs/audit/BACKEND_RUNTIME_FIRESTORE_INVENTORY.json
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../../backend/functions');
const SKIP = new Set(['test', 'node_modules']);

const HOT_PATH = new Set([
  'index.js',
  'registration_otp.js',
  'appointment_slots.js',
  'promoted_ads.js',
  'abuse_rate_limit.js',
  'caller_identity.js',
  'cross_role_sync.js',
  'fcm_push.js',
  'in_app_notifications.js',
  'seed_demo_accounts.js',
]);

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name.endsWith('.js')) out.push(p);
  }
  return out;
}

function classify(file, line) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const isTestPath = rel.includes('test/');
  if (isTestPath) return { rel, line, reachable: 'DEAD', reason: 'test-only path' };
  if (rel === 'runtime_app_db.js' || rel === 'firestore_forbidden_guard.js' || rel === 'legacy_db.js') {
    return { rel, line, reachable: 'GUARD', reason: 'forbidden guard' };
  }
  if (line.includes("require('firebase-admin/firestore") || line.includes('firebase-admin/firestore')) {
    return { rel, line: line.trim(), reachable: 'IMPORT', reason: 'admin firestore import' };
  }
  if (line.includes('.collection(') || line.includes('.runTransaction(')) {
    const hot = HOT_PATH.has(rel) || rel === 'index.js';
    return {
      rel,
      line: line.trim().slice(0, 160),
      reachable: hot ? 'LIVE_IF_FLAG_OFF' : 'DEAD_OR_LEGACY',
      reason: hot ? 'export/handler may run if forbidden flag off' : 'non-export helper',
    };
  }
  if (/firestore/i.test(line)) {
    return { rel, line: line.trim().slice(0, 160), reachable: 'COMMENT_OR_STRING', reason: 'grep hit' };
  }
  return null;
}

const files = walk(ROOT);
const hits = [];
for (const file of files) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  if (rel.startsWith('test/')) continue;
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (!/firestore|\.collection\(|getFirestore|getRuntimeAppDb/i.test(line)) return;
    const row = classify(file, line);
    if (row) hits.push({ ...row, lineNo: i + 1 });
  });
}

const outPath = path.resolve(__dirname, '../../docs/audit/BACKEND_RUNTIME_FIRESTORE_INVENTORY.json');
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify({ at: new Date().toISOString(), count: hits.length, hits }, null, 2));

const grepPath = path.resolve(__dirname, '../../docs/audit/BACKEND_RUNTIME_FIRESTORE_GREP.txt');
const lines = hits.map((h) => `${h.rel}:${h.lineNo}:${h.reachable}:${h.line || h.reason}`);
fs.writeFileSync(grepPath, lines.join('\n') + `\n\nTOTAL_LINES=${lines.length}\n`);

console.log(`Wrote ${outPath}`);
console.log(`Wrote ${grepPath} (${lines.length} lines)`);