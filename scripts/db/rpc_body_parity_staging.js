'use strict';

/**
 * Read-only: compare staging pg_get_functiondef vs local migration replay (doctornect_fresh_zero).
 * Normalizes bodies (strip comments, collapse whitespace) to detect logic drift vs formatting.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Client } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');

const FN_NAMES = [
  'accept_ambulance_request',
  'book_appointment_atomic',
  'cancel_ambulance_broadcast',
  'complete_ambulance_trip',
  'get_ambulance_trip_contact',
  'get_ambulance_trip_location',
  'reschedule_appointment_atomic',
  'update_ambulance_location',
  'update_lab_booking_status',
  'update_lab_order_status',
  'update_pharmacy_delivery_status',
];

const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

function localUrl() {
  const base = getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

function normalizeSql(def) {
  if (!def) return '';
  let s = def;
  s = s.replace(/\r\n/g, '\n');
  s = s.replace(/^\s*--[^\n]*\n/gm, '');
  s = s.replace(/\/\*[\s\S]*?\*\//g, '');
  s = s.replace(/\s+/g, ' ').trim().toLowerCase();
  return s;
}

function sha(s) {
  return crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);
}

function firstDiff(a, b) {
  const max = Math.min(a.length, b.length, 8000);
  for (let i = 0; i < max; i++) {
    if (a[i] !== b[i]) {
      return { at: i, stagingSnip: a.slice(Math.max(0, i - 40), i + 80), localSnip: b.slice(Math.max(0, i - 40), i + 80) };
    }
  }
  if (a.length !== b.length) return { at: max, stagingLen: a.length, localLen: b.length };
  return null;
}

async function fetchDefs(client, names) {
  const out = {};
  for (const name of names) {
    const q = await client.query(
      `SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_functiondef(p.oid) AS def
       FROM pg_proc p
       JOIN pg_namespace n ON p.pronamespace = n.oid
       WHERE n.nspname = 'public' AND p.proname = $1
       ORDER BY pg_get_function_identity_arguments(p.oid)`,
      [name],
    );
    out[name] = q.rows;
  }
  return out;
}

function pickPrimary(rows) {
  if (!rows.length) return null;
  if (rows.length === 1) return rows[0];
  return rows.find((r) => !r.args.includes('internal')) || rows[0];
}

async function main() {
  if (!process.argv.includes('--confirm-live-data')) {
    console.error('Refusing live staging without --confirm-live-data');
    process.exit(1);
  }
  const stagingUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!stagingUrl) {
    console.error('STAGING_SUPABASE_DB_URL missing');
    process.exit(1);
  }

  const sClient = new Client({ connectionString: stagingUrl, ssl: { rejectUnauthorized: false } });
  const lClient = new Client({ connectionString: localUrl() });
  await sClient.connect();
  await lClient.connect();

  const staging = await fetchDefs(sClient, FN_NAMES);
  const local = await fetchDefs(lClient, FN_NAMES);
  await sClient.end();
  await lClient.end();

  const results = [];
  for (const name of FN_NAMES) {
    const sRow = pickPrimary(staging[name] || []);
    const lRow = pickPrimary(local[name] || []);
    const sDef = sRow?.def || '';
    const lDef = lRow?.def || '';
    const sNorm = normalizeSql(sDef);
    const lNorm = normalizeSql(lDef);
    const match = sNorm === lNorm;
    const diff = match ? null : firstDiff(sNorm, lNorm);
    results.push({
      function: name,
      stagingArgs: sRow?.args || null,
      localArgs: lRow?.args || null,
      rawHashStaging: sha(sDef),
      rawHashLocal: sha(lDef),
      normHashStaging: sha(sNorm),
      normHashLocal: sha(lNorm),
      normalizedMatch: match,
      firstDiff: diff,
    });
  }

  const outPath = path.resolve(__dirname, '../../docs/reports/rpc_body_staging_vs_repo_local.json');
  fs.writeFileSync(outPath, JSON.stringify({ generatedAt: new Date().toISOString(), results }, null, 2));

  console.log('RPC body parity (staging vs local migration replay)');
  console.log(`Staging: ${maskConnectionString(stagingUrl)}`);
  console.log(`Local: ${maskConnectionString(localUrl())}\n`);
  for (const r of results) {
    console.log(
      `${r.normalizedMatch ? 'MATCH' : 'DRIFT'}  ${r.function}  norm ${r.normHashStaging} vs ${r.normHashLocal}`,
    );
    if (r.firstDiff && !r.normalizedMatch) {
      console.log('  firstDiff:', JSON.stringify(r.firstDiff));
    }
  }
  console.log(`\nWrote ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
