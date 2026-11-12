'use strict';

/**
 * Smoke test: Firebase signInWithPassword + custom claims + staging users row.
 * Reads SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD from .env (never logged).
 */

const https = require('https');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('./lib/env_loader');

const FIREBASE_API_KEY = getEnv('FIREBASE_API_KEY_WEB') || getEnv('FIREBASE_WEB_API_KEY');

function postJson(url, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => {
          raw += c;
        });
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}') });
          } catch (e) {
            reject(e);
          }
        });
      },
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  if (!FIREBASE_API_KEY) {
    console.error('FIREBASE_API_KEY_WEB missing in .env');
    process.exit(1);
  }
  const email = (getEnv('SUPER_ADMIN_EMAIL') || 'admin@doctornect.com').trim();
  const password = getEnv('SUPER_ADMIN_PASSWORD');
  if (!password) {
    console.error('SUPER_ADMIN_PASSWORD missing in .env');
    process.exit(1);
  }

  const wrong = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    { email, password: `${password}x`, returnSecureToken: true },
  );
  const wrongPass = wrong.status !== 200;
  console.log(`NEGATIVE (wrong password): ${wrongPass ? 'PASS' : 'FAIL'}`);

  const ok = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    { email, password, returnSecureToken: true },
  );
  if (ok.status !== 200) {
    console.log(`LOGIN: FAIL (${ok.json.error?.message || ok.status})`);
    process.exit(1);
  }

  const idToken = ok.json.idToken;
  const localId = ok.json.localId;
  console.log(`LOGIN: PASS (uid=${localId})`);

  const claimsRes = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_API_KEY}`,
    { idToken },
  );
  const claims = {};
  if (claimsRes.json?.users?.[0]?.customAttributes) {
    try {
      Object.assign(claims, JSON.parse(claimsRes.json.users[0].customAttributes));
    } catch (_) {}
  }

  const roleOk =
    claims.role === 'authenticated' &&
    (claims.app_role === 'super_admin' || claims.user_role === 'super_admin');
  console.log(`CLAIMS: ${roleOk ? 'PASS' : 'FAIL'} (app_role=${claims.app_role || 'n/a'})`);

  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  if (!dbUrl) {
    console.log('DB ROW: SKIP (no STAGING_SUPABASE_DB_URL)');
    process.exit(roleOk && wrongPass ? 0 : 1);
  }

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();
  try {
    const row = await client.query(
      `SELECT role, email FROM public.users WHERE id = $1 OR firebase_uid = $1 LIMIT 1`,
      [localId],
    );
    const dbOk = row.rows[0]?.role === 'super_admin';
    console.log(`DB users.role: ${dbOk ? 'PASS' : 'FAIL'} (${maskConnectionString(dbUrl)})`);

    const sa = await client.query(`SELECT 1 FROM public.super_admins WHERE user_uid = $1`, [localId]);
    console.log(`DB super_admins: ${sa.rowCount > 0 ? 'PASS' : 'FAIL'}`);

    const supabaseUrl = getEnv('STAGING_SUPABASE_URL') || getEnv('SUPABASE_URL');
    const supabaseAnon = getEnv('STAGING_SUPABASE_ANON_KEY') || getEnv('SUPABASE_ANON_KEY');
    if (supabaseUrl && supabaseAnon) {
      const headers = {
        apikey: supabaseAnon,
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
      };
      const panels = [
        { name: 'Users tab (users SELECT)', path: '/rest/v1/users?select=id&limit=1' },
        { name: 'Verification (doctors SELECT)', path: '/rest/v1/doctors?select=doctor_id&limit=1' },
        { name: 'Banners (system_config SELECT)', path: '/rest/v1/system_config?select=config_key&config_key=eq.promoted_ads' },
        { name: 'Audit logs SELECT', path: '/rest/v1/admin_audit_logs?select=log_id&limit=1' },
        { name: 'Analytics (appointments SELECT)', path: '/rest/v1/appointments?select=appointment_id&limit=1' },
      ];
      console.log('\n--- Admin panel PostgREST smoke (super_admin JWT) ---');
      for (const p of panels) {
        const ok = await new Promise((resolve) => {
          const req = https.request(
            `${supabaseUrl}${p.path}`,
            { method: 'GET', headers },
            (r) => {
              let raw = '';
              r.on('data', (c) => { raw += c; });
              r.on('end', () => {
                if (p.path.includes('admin_audit_logs') && r.statusCode !== 200) {
                  console.log(`  (audit HTTP ${r.statusCode}: ${raw.slice(0, 200)})`);
                }
                resolve(r.statusCode === 200);
              });
            },
          );
          req.on('error', () => resolve(false));
          req.end();
        });
        console.log(`${p.name}: ${ok ? 'PASS' : 'FAIL'}`);
      }
    } else {
      console.log('Supabase REST smoke: SKIP (missing URL/anon key)');
    }

    process.exit(wrongPass && roleOk && dbOk && sa.rowCount > 0 ? 0 : 1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
