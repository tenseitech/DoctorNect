#!/usr/bin/env node
'use strict';
/** Dry-run materialize vs deployed sendUserRegistrationOtp env (masked). */
const fs = require('fs');
const path = require('path');
const { findRepoRoot } = require('../lib/repo_root');
const { parseEnvFile } = require('../lib/parse_env_file');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { filterBaselineRuntimeEnv } = require('../lib/firebase_tools_reserved_env');

const root = findRepoRoot(path.join(__dirname, '../..'));
const matSrc = fs.readFileSync(path.join(root, 'scripts/env/materialize_functions_env.js'), 'utf8');
const FUNCTIONS_KEYS = [...new Set([...matSrc.matchAll(/'([A-Z][A-Z0-9_]*)'/g)].map((m) => m[1]).filter((k) => k.length > 2))];

loadRootEnv({ startDir: root, force: true });
const parsed = parseEnvFile(path.join(root, '.env'));

const REVIEWER_OVERLAY_KEYS = new Set([
  'REVIEWER_OTP_ENABLED',
  'REVIEW_ACCESS_UNTIL',
  'REVIEW_FIXED_OTP',
  'REVIEW_PATIENT_PHONES',
  'REVIEW_DOCTOR_PHONES',
  'REVIEW_LAB_PHONES',
  'REVIEW_MEDICAL_STORE_PHONES',
  'REVIEW_MEDICALSTORE_PHONES',
  'REVIEW_AMBULANCE_PHONES',
]);

function wouldMaterialize() {
  const narrow = String(process.env.NARROW_OTP_DEPLOY || '').trim() === '1';
  if (narrow) {
    const baselinePath =
      process.env.DEPLOYED_ENV_BASELINE ||
      path.join(root, '.artifacts', 'baselines', 'sendUserRegistrationOtp.deployed.json');
    const raw = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
    const out = filterBaselineRuntimeEnv(raw.serviceConfig?.environmentVariables || raw);
    for (const key of REVIEWER_OVERLAY_KEYS) {
      const val = process.env[key] ?? parsed[key] ?? '';
      if (val !== '') out[key] = String(val);
    }
    return out;
  }
  const out = {};
  for (const key of FUNCTIONS_KEYS) {
    const val = process.env[key] ?? parsed[key] ?? '';
    if (val === '') continue;
    out[key] = String(val);
  }
  return out;
}

function disp(k, v) {
  if (v === undefined) return '[unset]';
  if (/SECRET|PASSWORD|AUTH_KEY|PROXY_SECRET|WEBHOOK_SECRET|SERVICE_ROLE|MSG91_AUTH/.test(k)) {
    return v ? `[set,len=${v.length}]` : '[unset]';
  }
  if (k === 'REVIEW_FIXED_OTP') return `[set,len=${v.length}]`;
  if (k === 'DATABASE_URL' || k === 'SUPABASE_DB_URL') {
    return v.replace(/:[^@/]+@/, ':****@');
  }
  if (k === 'REDIS_HOST') {
    return v.replace(/.(?=.{4})/g, '*');
  }
  return v;
}

function normRedisHost(h, port) {
  if (!h) return '';
  const s = String(h);
  if (s.includes(':') && !s.startsWith('[')) return s;
  return port ? `${s}:${port}` : s;
}

const deployedPath =
  process.env.DEPLOYED_FN_JSON ||
  process.env.DEPLOYED_ENV_BASELINE ||
  'C:/Users/khije/AppData/Local/Temp/fn-sendUserRegistrationOtp.json';
const deployedRaw =
  JSON.parse(fs.readFileSync(deployedPath, 'utf8')).serviceConfig?.environmentVariables || {};
const deployed = filterBaselineRuntimeEnv(deployedRaw);
const would = wouldMaterialize();

const allowedReviewer = new Set([
  'REVIEWER_OTP_ENABLED',
  'REVIEW_ACCESS_UNTIL',
  'REVIEW_FIXED_OTP',
  'REVIEW_PATIENT_PHONES',
  'REVIEW_DOCTOR_PHONES',
  'REVIEW_MEDICAL_STORE_PHONES',
  'REVIEW_MEDICALSTORE_PHONES',
  'REVIEW_LAB_PHONES',
  'REVIEW_AMBULANCE_PHONES',
]);

const diffs = [];
const nonReviewerDiffs = [];

const allKeys = new Set([...Object.keys(deployed), ...Object.keys(would)]);
for (const k of [...allKeys].sort()) {
  let d = deployed[k];
  let w = would[k];
  if (k === 'REDIS_HOST') {
    d = normRedisHost(d, deployed.REDIS_PORT);
    w = normRedisHost(w, would.REDIS_PORT);
  }
  const ds = d === undefined ? '' : String(d);
  const ws = w === undefined ? '' : String(w);
  if (ds === ws) continue;
  const row = { key: k, deployed: disp(k, d), would: disp(k, w) };
  diffs.push(row);
  if (!allowedReviewer.has(k)) nonReviewerDiffs.push(row);
}

console.log('variable|deployed|would_materialize|reviewer_only');
for (const r of diffs) {
  const ro = allowedReviewer.has(r.key) ? 'yes' : 'NO';
  console.log(`${r.key}|${r.deployed}|${r.would}|${ro}`);
}
console.log('---');
console.log('TOTAL_DIFFS', diffs.length);
console.log('NON_REVIEWER_DIFFS', nonReviewerDiffs.length);
if (nonReviewerDiffs.length) {
  console.log('STOP: non-reviewer differences present');
  process.exit(2);
}
process.exit(0);