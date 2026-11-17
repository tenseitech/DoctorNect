#!/usr/bin/env node
'use strict';

/**
 * Staging-only: authenticated super_admin JWT must not INSERT into admin_audit_logs (migration 000005).
 */

const https = require('https');
const { getEnv } = require('./lib/env_loader');

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
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}'), raw });
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

async function signIn() {
  const email = (getEnv('SUPER_ADMIN_EMAIL') || 'admin@doctornect.com').trim();
  const password = getEnv('SUPER_ADMIN_PASSWORD');
  if (!FIREBASE_API_KEY || !password) {
    throw new Error('FIREBASE_API_KEY_WEB / SUPER_ADMIN_PASSWORD missing');
  }
  const ok = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    { email, password, returnSecureToken: true },
  );
  if (ok.status !== 200) {
    throw new Error(`Login failed: ${ok.json.error?.message || ok.status}`);
  }
  return ok.json.idToken;
}

async function tryInsert(idToken) {
  const url = getEnv('STAGING_SUPABASE_URL') || getEnv('SUPABASE_URL') || '';
  const anon = getEnv('STAGING_SUPABASE_ANON_KEY') || getEnv('SUPABASE_ANON_KEY') || '';
  if (!url || !anon) {
    console.log('INSERT DENY TEST: SKIP (no Supabase URL/anon)');
    return false;
  }
  const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/admin_audit_logs`, {
    method: 'POST',
    headers: {
      apikey: anon,
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({
      log_id: `client_forbidden_${Date.now()}`,
      admin_uid: 'test',
      admin_email: 'test@example.com',
      action: 'CLIENT_INSERT_ATTEMPT',
      target_type: 'test',
      target_id: 'test',
      details: 'negative test',
      metadata: {},
    }),
  });
  const body = await res.text();
  const pass = res.status === 403 || res.status === 401 || res.status === 42501;
  console.log(`Client INSERT admin_audit_logs: HTTP ${res.status} → ${pass ? 'PASS (denied)' : 'FAIL'}`);
  if (!pass && body) console.log(body.slice(0, 200));
  return pass;
}

(async () => {
  const idToken = await signIn();
  const ok = await tryInsert(idToken);
  process.exit(ok ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
