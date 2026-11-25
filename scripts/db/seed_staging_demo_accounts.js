#!/usr/bin/env node
'use strict';

/**
 * Seed the Play Store reviewer / demo accounts into the STAGING Supabase database ONLY.
 *
 * Demo phones must be pre-registered users so reviewers take the normal LOGIN path (OTP ->
 * existing user), never signup. This script creates, if missing, one public.users row per demo
 * role (id = firebase_uid = the demo Firebase UID, mobile = +91<digits>) plus the matching profile
 * row. It is create-only: existing rows are never updated or deleted.
 *
 *   node scripts/db/seed_staging_demo_accounts.js            # dry run: prints the plan
 *   DEMO_SEED_TARGET=staging node scripts/db/seed_staging_demo_accounts.js --execute
 *
 * Connection: STAGING_SUPABASE_DB_URL (or --db-url=...). Phones: REVIEW_<ROLE>_PHONES (first number)
 * or the defaults below. Firebase Auth users are created separately by
 * scripts/audit/staging_demo_firebase_create.js (same UIDs). Every demo UID must also be listed in
 * DEMO_FIREBASE_UID_ALLOWLIST on Functions and gateway so production routes them to staging.
 *
 * Hard refusals (no flag overrides them): APP_ENV=production, any *.rds.amazonaws.com host, the
 * PROD_RDS_HOST / PROD_RDS_CONNECT_HOST / PROD_GATEWAY_URL hosts, any URL equal to DATABASE_URL /
 * PROD_RDS_DATABASE_URL, and any host that is not a Supabase host (loopback is allowed only with
 * --allow-local for scratch testing).
 */

const { URL } = require('url');

const DEMOS = [
  { role: 'patient', uid: 'rev_fb_pat_001', digits: '9999900001', phonesEnv: 'REVIEW_PATIENT_PHONES', name: 'Demo Patient' },
  { role: 'doctor', uid: 'rev_fb_doc_001', digits: '9999900002', phonesEnv: 'REVIEW_DOCTOR_PHONES', name: 'Demo Doctor' },
  { role: 'medicalStore', uid: 'rev_fb_store_001', digits: '9999900003', phonesEnv: 'REVIEW_MEDICAL_STORE_PHONES', name: 'Demo Pharmacy' },
  { role: 'lab', uid: 'rev_fb_lab_001', digits: '9999900004', phonesEnv: 'REVIEW_LAB_PHONES', name: 'Demo Lab' },
  { role: 'ambulance', uid: 'rev_fb_amb_001', digits: '9999900005', phonesEnv: 'REVIEW_AMBULANCE_PHONES', name: 'Demo Ambulance' },
];

function hostOf(value) {
  const s = String(value || '').trim();
  if (!s) return '';
  try {
    return new URL(/^[a-z]+:\/\//i.test(s) ? s.replace(/^postgres:\/\//i, 'postgresql://') : `x://${s}`).hostname.toLowerCase();
  } catch (_) {
    return s.toLowerCase();
  }
}

/** Throws unless dbUrl is unmistakably the staging Supabase database. Pure; unit tested. */
function assertStagingOnlyTarget(dbUrl, env = process.env, { allowLocal = false } = {}) {
  const refuse = (why) => {
    const err = new Error(`[seed_staging_demo_accounts] REFUSED: ${why}`);
    err.code = 'DEMO_SEED_REFUSED';
    throw err;
  };
  if (!dbUrl) refuse('no database URL (set STAGING_SUPABASE_DB_URL).');
  if (String(env.APP_ENV || '').trim().toLowerCase() === 'production') refuse('APP_ENV=production.');
  const host = hostOf(dbUrl);
  if (!host) refuse('cannot parse database host.');
  if (/\.rds\.amazonaws\.com$/.test(host) || host.includes('.rds.')) refuse('target is an AWS RDS host.');
  for (const key of ['PROD_RDS_HOST', 'PROD_RDS_CONNECT_HOST', 'PROD_GATEWAY_URL']) {
    if (env[key] && hostOf(env[key]) === host) refuse(`target host equals ${key}.`);
  }
  for (const key of ['DATABASE_URL', 'PROD_RDS_DATABASE_URL']) {
    if (env[key] && String(env[key]).trim() === String(dbUrl).trim()) refuse(`target equals ${key} (production database).`);
  }
  const isLoopback = ['127.0.0.1', 'localhost', '::1'].includes(host);
  const isSupabase = /(^|\.)supabase\.(co|com)$/.test(host) || /\.pooler\.supabase\.com$/.test(host);
  if (isLoopback && !allowLocal) refuse('loopback target requires --allow-local (scratch testing only).');
  if (!isLoopback && !isSupabase) refuse(`host ${host} is not a Supabase staging host.`);
  return host;
}

function demoPhone(demo, env = process.env) {
  const first = String(env[demo.phonesEnv] || '').split(',').map((s) => s.replace(/\D/g, '')).find((d) => d.length >= 10);
  return `+91${(first || demo.digits).slice(-10)}`;
}

function profileFor(demo, mobile) {
  const id = `demo_${demo.role.toLowerCase()}_001`;
  switch (demo.role) {
    case 'patient':
      return { table: 'patients', key: 'patient_id', id, row: { patient_id: id, owner_uid: demo.uid, name: demo.name, phone: mobile, mobile } };
    case 'doctor':
      return { table: 'doctors', key: 'doctor_id', id, row: { doctor_id: id, owner_uid: demo.uid, name: demo.name, mobile, phone: mobile, specialization: 'General Physician', verified: true, deactivated: false } };
    case 'medicalStore':
      return { table: 'medical_stores', key: 'store_id', id, row: { store_id: id, owner_uid: demo.uid, store_name: demo.name, owner_name: demo.name, phone: mobile, verified: true, deactivated: false } };
    case 'lab':
      return { table: 'labs', key: 'lab_id', id, row: { lab_id: id, owner_uid: demo.uid, lab_name: demo.name, phone: mobile, verified: true, deactivated: false } };
    case 'ambulance':
      return { table: 'ambulances', key: 'ambulance_id', id, row: { ambulance_id: id, auth_uid: demo.uid, owner_uid: demo.uid, service_name: demo.name, driver_name: demo.name, phone: mobile, ambulance_type: 'bls', verified: true, is_available: false } };
    default:
      throw new Error(`unknown role ${demo.role}`);
  }
}

async function columnsOf(client, table) {
  const { rows } = await client.query(
    `SELECT column_name, is_nullable, column_default, data_type, udt_name
       FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1`,
    [table],
  );
  return rows;
}

function dummyFor(col) {
  const t = col.data_type;
  if (t === 'uuid') return null; // let the DB fail loudly rather than invent identity values
  if (t === 'ARRAY') return '{}';
  if (t === 'boolean') return false;
  if (/int|numeric|double|real/.test(t)) return 0;
  if (/timestamp|date/.test(t)) return new Date().toISOString();
  if (/json/.test(t)) return '{}';
  return 'demo';
}

/** Insert only columns that exist; fill other NOT NULL columns without defaults; never overwrite. */
async function insertIfMissing(client, table, keyCol, row) {
  const cols = await columnsOf(client, table);
  if (!cols.length) throw new Error(`table public.${table} not found`);
  const names = new Set(cols.map((c) => c.column_name));
  const data = {};
  for (const [k, v] of Object.entries(row)) if (names.has(k)) data[k] = v;
  for (const c of cols) {
    if (c.is_nullable === 'NO' && c.column_default == null && !(c.column_name in data)) {
      const v = dummyFor(c);
      if (v !== null) data[c.column_name] = v;
    }
  }
  const keys = Object.keys(data);
  const sql = `INSERT INTO public.${table} (${keys.map((k) => `"${k}"`).join(', ')})
               VALUES (${keys.map((_, i) => `$${i + 1}`).join(', ')})
               ON CONFLICT ("${keyCol}") DO NOTHING`;
  const res = await client.query(sql, keys.map((k) => data[k]));
  return res.rowCount;
}

function buildPlan(env = process.env) {
  return DEMOS.map((d) => {
    const mobile = demoPhone(d, env);
    const profile = profileFor(d, mobile);
    return {
      role: d.role,
      uid: d.uid,
      mobileMasked: `${mobile.slice(0, 5)}*****${mobile.slice(-2)}`,
      mobile,
      profile,
      user: { id: d.uid, firebase_uid: d.uid, role: d.role, profile_id: profile.id, mobile, name: d.name, email: `${d.uid}@demo.doctornect.invalid` },
    };
  });
}

async function main() {
  const args = process.argv.slice(2);
  const execute = args.includes('--execute');
  const allowLocal = args.includes('--allow-local');
  const urlArg = (args.find((a) => a.startsWith('--db-url=')) || '').slice('--db-url='.length);
  try { require('../lib/bootstrap_root_env').loadRootEnv(); } catch (_) {}
  const dbUrl = urlArg || process.env.STAGING_SUPABASE_DB_URL || '';

  const host = assertStagingOnlyTarget(dbUrl, process.env, { allowLocal });
  const plan = buildPlan();
  console.log(`Target host: ${host}`);
  for (const p of plan) console.log(`  ${p.role.padEnd(13)} uid=${p.uid} mobile=${p.mobileMasked} profile=${p.profile.table}/${p.profile.id}`);
  if (!execute) {
    console.log('\nDry run. Re-run with DEMO_SEED_TARGET=staging and --execute to create missing rows.');
    return;
  }
  if (String(process.env.DEMO_SEED_TARGET || '') !== 'staging') {
    throw new Error('[seed_staging_demo_accounts] REFUSED: set DEMO_SEED_TARGET=staging to execute.');
  }

  const { Client } = require('pg');
  const client = new Client({ connectionString: dbUrl, ssl: allowLocal && ['127.0.0.1', 'localhost', '::1'].includes(host) ? false : { rejectUnauthorized: true } });
  await client.connect();
  try {
    await client.query('BEGIN');
    for (const p of plan) {
      const existing = await client.query('SELECT id, role FROM public.users WHERE mobile = ANY($1) OR id = $2', [
        [p.mobile, p.mobile.slice(3), p.mobile.slice(1)], p.uid,
      ]);
      if (existing.rows.some((r) => r.id !== p.uid)) {
        throw new Error(`demo phone for ${p.role} already belongs to another user; refusing to touch it.`);
      }
      const usr = await insertIfMissing(client, 'users', 'id', p.user);
      const prof = await insertIfMissing(client, p.profile.table, p.profile.key, p.profile.row);
      console.log(`  ${p.role.padEnd(13)} profile ${prof ? 'created' : 'exists'}, user ${usr ? 'created' : 'exists'}`);
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}

module.exports = { assertStagingOnlyTarget, buildPlan, DEMOS };
