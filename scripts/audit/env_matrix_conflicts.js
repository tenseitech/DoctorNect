#!/usr/bin/env node
'use strict';
/** Compare env keys across files; report duplicate keys and value hash mismatches (no values). */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '../..');
const FILES = [
  '.env',
  '.env.example',
  '.env.migration',
  'backend/functions/.env',
  'backend/functions/.env.example',
  'backend/.env.migration.example',
  'frontend/.env.example',
];

function parseEnv(filePath) {
  const map = new Map();
  if (!fs.existsSync(filePath)) return map;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const key = t.slice(0, eq).trim();
    const val = t.slice(eq + 1).trim();
    const hash = crypto.createHash('sha256').update(val).digest('hex').slice(0, 16);
    map.set(key, hash);
  }
  return map;
}

const byKey = new Map();
for (const rel of FILES) {
  const abs = path.join(ROOT, rel);
  const m = parseEnv(abs);
  for (const [key, hash] of m) {
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push({ file: rel, valueHash: hash });
  }
}

const multiFile = [];
const conflicts = [];
for (const [key, entries] of byKey) {
  if (entries.length > 1) {
    const hashes = new Set(entries.map((e) => e.valueHash));
    multiFile.push({ key, files: entries.map((e) => e.file) });
    if (hashes.size > 1) {
      conflicts.push({
        key,
        files: entries.map((e) => ({ file: e.file, valueHash: e.valueHash })),
      });
    }
  }
}

console.log(JSON.stringify({
  filesScanned: FILES.filter((f) => fs.existsSync(path.join(ROOT, f))),
  keysAcrossFiles: byKey.size,
  keysInMultipleFiles: multiFile.length,
  valueConflicts: conflicts.length,
  valueConflictSample: conflicts.slice(0, 40),
  aliasGroups: {
    supabaseServiceRole: multiFile.filter((x) =>
      ['SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_KEY', 'SERVICE_ROLE_KEY'].includes(x.key)),
    supabaseUrl: multiFile.filter((x) =>
      ['SUPABASE_URL', 'STAGING_SUPABASE_URL', 'PGRST_URL'].includes(x.key)),
    s3Bucket: multiFile.filter((x) =>
      ['S3_BUCKET', 'S3_BUCKET_NAME', 'AWS_S3_VAULT_BUCKET'].includes(x.key)),
  },
}, null, 2));
