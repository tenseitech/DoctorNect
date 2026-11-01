#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT_DIR = path.resolve(__dirname, '..');
module.paths.push(path.resolve(ROOT_DIR, 'backend/functions/node_modules'));
const { bootstrapMutatingScript } = require('./lib/mutating_script_bootstrap');

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx !== -1) {
      const key = trimmed.slice(0, eqIdx).trim();
      let val = trimmed.slice(eqIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      env[key] = val;
    }
  }
  return env;
}

const rootEnv = parseEnvFile(path.resolve(ROOT_DIR, '.env'));
const backendEnv = parseEnvFile(path.resolve(ROOT_DIR, 'backend/functions/.env'));
const mergedEnv = { ...rootEnv, ...backendEnv, ...process.env };

async function checkPostgrestFirebaseToken() {
  bootstrapMutatingScript('scripts/test_firebase_postgrest.js');
  const saPath = path.resolve(ROOT_DIR, 'scripts/service-account.json');
  if (!fs.existsSync(saPath)) {
    console.error('ERROR: scripts/service-account.json missing');
    process.exit(1);
  }

  const { initializeApp, cert, getApps } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');

  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const app = getApps().length === 0 ? initializeApp({ credential: cert(sa) }) : getApps()[0];
  const auth = getAuth(app);

  const webApiKey = mergedEnv.FIREBASE_API_KEY_WEB;
  const testUid = `check_jwt_${Date.now()}`;

  // 1. Mint custom token with standard Firebase -> Supabase claims
  const customToken = await auth.createCustomToken(testUid, {
    role: 'authenticated',
    app_role: 'patient',
    user_role: 'patient',
  });

  // 2. Exchange for Firebase ID Token
  const postData = JSON.stringify({ token: customToken, returnSecureToken: true });
  const idToken = await new Promise((resolve, reject) => {
    const req = https.request(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
      },
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.idToken) resolve(parsed.idToken);
          else reject(new Error(parsed.error?.message || 'Token exchange failed'));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });

  // 3. Probe PostgREST endpoint with Firebase ID token
  const url = new URL(`${mergedEnv.SUPABASE_URL}/rest/v1/users?select=id&limit=1`);
  const postgrestResponse = await new Promise((resolve) => {
    const req = https.request(url, {
      method: 'GET',
      headers: {
        'apikey': mergedEnv.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${idToken}`,
        'Content-Type': 'application/json',
      },
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body,
        });
      });
    });
    req.on('error', (e) => resolve({ error: e.message }));
    req.end();
  });

  console.log('PostgREST HTTP Status:', postgrestResponse.statusCode);
  console.log('PostgREST Response Body:', postgrestResponse.body);

  // Clean up the temporary test user in Firebase Auth
  try {
    await auth.deleteUser(testUid);
  } catch (_) {}

  if (postgrestResponse.statusCode === 200) {
    console.log('SUCCESS: PostgREST accepted the Firebase ID token (HTTP 200 OK)!');
    process.exit(0);
  } else {
    console.error('FAIL: PostgREST rejected token:', postgrestResponse.body);
    process.exit(2);
  }
}

checkPostgrestFirebaseToken().catch((err) => {
  console.error('Execution failure:', err);
  process.exit(1);
});
