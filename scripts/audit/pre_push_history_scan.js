#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const crypto = require('crypto');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

const TARGET_COMMITS = {
  '73860fc8e9293721c7b5bf8ff5ce1e688e558b3e': [
    { file: 'backend/functions/.env.example', key: 'S3_BUCKET' },
    { file: 'backend/functions/.env.example', key: 'S3_BUCKET_NAME' },
    { file: 'backend/functions/.env.example', key: 'AWS_S3_VAULT_BUCKET' },
  ],
  b1a700fbdf43a5a75dab33751244d3283b31042d: [
    { file: 'backend/functions/.env.example', key: 'SUPABASE_WEBHOOK_SECRET' },
  ],
  '36e2177aa3ee3f74d10c56323df836222873c972': [
    { file: '.env.migration.example', key: 'STAGING_SUPABASE_DB_URL' },
    { file: '.env.migration.example', key: 'SUPABASE_URL' },
  ],
};

const PLACEHOLDER =
  /^(your[-_]|changeme|xxx|placeholder|example|todo|replace|insert|<|\)|none|test[-_]?key?|dummy|sk_test|pk_test|localhost|127\.0\.0\.1|postgres:\/\/postgres:postgres)/i;

function looksReal(name, rawVal) {
  const val = String(rawVal || '').trim();
  if (!val) return false;
  if (PLACEHOLDER.test(val)) return false;
  if (/^your-project-ref\.supabase\.co$/i.test(val)) return false;
  if (val === 'your-anon-key' || val === 'your-service-role-key') return false;
  if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(val)) return true;
  if (/^rzp_live_/i.test(val)) return true;
  if (/^AKIA[0-9A-Z]{16}$/.test(val)) return true;
  if (/\.supabase\.co/i.test(val) && !/your-project-ref/i.test(val)) return true;
  if (val.length >= 32 && /^[A-Za-z0-9+/=_-]+$/.test(val)) return true;
  if (/^postgres(ql)?:\/\//i.test(val) && !/127\.0\.0\.1|localhost|:54322/.test(val)) return true;
  if (/password|secret|token|apikey|api_key/i.test(name) && val.length >= 12 && !PLACEHOLDER.test(val)) {
    return true;
  }
  return false;
}

function parseEnvAtCommit(commit, file) {
  let content;
  try {
    content = execSync(`git --no-pager show ${commit}:${file}`, {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 2 * 1024 * 1024,
    });
  } catch {
    return null;
  }
  const env = {};
  for (const line of content.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    env[t.slice(0, eq).trim()] = t.slice(eq + 1).trim();
  }
  return env;
}

function hostHash8(val) {
  let host = String(val || '').trim();
  try {
    if (/^postgres(ql)?:\/\//i.test(host)) {
      const u = new URL(host.replace(/^postgresql:/i, 'http:'));
      host = u.hostname;
    } else if (/^https?:\/\//i.test(host)) {
      host = new URL(host).hostname;
    } else if (host.includes('.supabase.co')) {
      host = host.replace(/^https?:\/\//, '').split('/')[0];
    }
  } catch {
    /* keep raw */
  }
  if (!host) return { h40: 'no', h80: 'no' };
  const h = crypto.createHash('sha256').update(host, 'utf8').digest('hex').slice(0, 8).toLowerCase();
  return {
    h40: h === '40d01c23' ? 'yes' : 'no',
    h80: h === '800db356' ? 'yes' : 'no',
  };
}

function onOrigin(commit) {
  const out = execSync(`git --no-pager branch -r --contains ${commit}`, {
    cwd: ROOT,
    encoding: 'utf8',
  }).trim();
  return out.length > 0 ? 'yes' : 'no';
}

function passwordLengthClass(name, val) {
  const v = String(val || '').trim();
  if (!/password|secret|token|key/i.test(name)) return 'n/a';
  if (!v) return 'empty';
  if (v.length < 8) return 'short';
  if (looksReal(name, v)) return 'real-looking-len';
  return 'placeholder-looking-len';
}

function scanPickaxe(pattern, flag) {
  const cmd = `git --no-pager log --remotes=origin --format="== %h" --name-only ${flag}${pattern} --`;
  let out;
  try {
    out = execSync(cmd, { cwd: ROOT, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  } catch (e) {
    out = e.stdout || '';
  }
  const blocks = out.split(/^== /m).filter(Boolean);
  const hits = [];
  for (const block of blocks) {
    const lines = block.trim().split('\n');
    const hash = lines[0].trim();
    const files = lines.slice(1).filter((l) => l.trim() && !l.startsWith('=='));
    for (const f of files) {
      hits.push({ hash, file: f.trim(), pattern: `${flag}${pattern}` });
    }
  }
  return hits;
}

function classifyHit(commit, file) {
  try {
    const content = execSync(`git --no-pager show ${commit}:${file}`, {
      cwd: ROOT,
      encoding: 'utf8',
      maxBuffer: 4 * 1024 * 1024,
    });
    const lines = content.split('\n');
    for (const line of lines) {
      if (/eyJhbGci|rzp_live_|AKIA[0-9A-Z]{16}|postgres(ql)?:\/\/[^:/@]+:[^@\[\s]{6,}@/i.test(line)) {
        const eq = line.indexOf('=');
        const key = eq > 0 ? line.slice(0, eq).trim() : '(inline)';
        const val = eq > 0 ? line.slice(eq + 1).trim() : line;
        return looksReal(key, val) ? 'real-looking' : 'placeholder-looking';
      }
    }
  } catch {
    return 'unverified';
  }
  return 'unverified';
}

const rows = [];
for (const [commit, items] of Object.entries(TARGET_COMMITS)) {
  const origin = onOrigin(commit);
  for (const { file, key } of items) {
    const env = parseEnvAtCommit(commit, file);
    const val = env ? env[key] : '';
    const real = env && key in env ? (looksReal(key, val) ? 'real-looking' : 'placeholder-looking') : 'missing';
    const hashes = hostHash8(val);
    rows.push({
      commit: commit.slice(0, 8),
      file,
      key,
      real,
      pwdLen: passwordLengthClass(key, val),
      hash40D01C23: hashes.h40,
      hash800DB356: hashes.h80,
      onOrigin: origin,
    });
  }
}

const patterns = [
  ['eyJhbGci', '-S'],
  ['rzp_live_', '-S'],
  ['AKIA', '-S'],
  ['postgres(ql)?://[^:/@]+:[^@\\[<]{6,}@', '-G'],
];
const remoteHits = [];
for (const [pat, flag] of patterns) {
  for (const h of scanPickaxe(`"${pat}"`, flag)) {
    remoteHits.push({
      ...h,
      classification: classifyHit(h.hash, h.file),
    });
  }
}

console.log(JSON.stringify({ rows, remoteHits }, null, 2));
