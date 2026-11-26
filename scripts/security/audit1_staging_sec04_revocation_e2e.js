'use strict';

/**
 * SEC-04 staging: revoke refresh tokens → same ID token must fail gateway auth (401).
 * Requires audit1_staging_prereq_check.js exit 0. Never logs tokens or passwords.
 */
const path = require('path');
const { spawnSync } = require('child_process');
const fs = require('fs');

const repoRoot = path.join(__dirname, '..', '..');
require(path.join(repoRoot, 'scripts', 'lib', 'bootstrap_root_env')).loadRootEnv();

const prereq = spawnSync(process.execPath, [path.join(__dirname, 'audit1_staging_prereq_check.js')], {
  cwd: repoRoot,
  encoding: 'utf8',
});
if (prereq.status !== 0) {
  process.stderr.write('SEC-04 staging aborted: prerequisites not met (run audit1_staging_prereq_check.js).\n');
  process.exit(2);
}

const gatewayBase = String(process.env.AUDIT1_STAGING_GATEWAY_URL || '').replace(/\/$/, '');
const email = String(process.env.AUDIT1_TEST_FIREBASE_EMAIL || '').trim();
const password = String(process.env.AUDIT1_TEST_FIREBASE_PASSWORD || '');
const apiKey = String(process.env.AUDIT1_FIREBASE_WEB_API_KEY || process.env.FIREBASE_WEB_API_KEY || '').trim();
const projectId = String(process.env.AUDIT1_FIREBASE_PROJECT_ID || process.env.FIREBASE_PROJECT_ID || '').trim();

if (!apiKey || !projectId) {
  process.stderr.write('SEC-04 staging aborted: set AUDIT1_FIREBASE_WEB_API_KEY and AUDIT1_FIREBASE_PROJECT_ID (staging project).\n');
  process.exit(2);
}

async function signIn() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await res.json();
  if (!res.ok) throw new Error('sign-in failed (staging test account)');
  return { idToken: body.idToken, localId: body.localId, refreshToken: body.refreshToken };
}

async function gatewayProbe(idToken) {
  const url = `${gatewayBase}/rest/v1/doctor_directory?select=id&limit=1`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${idToken}`, Accept: 'application/json' },
  });
  return res.status;
}

async function main() {
  const { initializeApp, getApps, deleteApp } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');

  for (const app of getApps()) await deleteApp(app);
  initializeApp({ projectId });
  const auth = getAuth();

  const session = await signIn();
  const before = await gatewayProbe(session.idToken);
  if (before === 401) {
    process.stderr.write('SEC-04 staging aborted: token rejected before revoke (check gateway URL / Firebase project).\n');
    process.exit(1);
  }

  await auth.revokeRefreshTokens(session.localId);
  await new Promise((r) => setTimeout(r, 1500));

  const after = await gatewayProbe(session.idToken);
  const evidence = {
    event: 'audit1_sec04_staging_revocation',
    timestamp: new Date().toISOString(),
    gateway_host: new URL(gatewayBase).host,
    project_id: projectId,
    status_before_revoke: before,
    status_after_revoke: after,
    pass: after === 401,
  };
  process.stdout.write(`${JSON.stringify(evidence)}\n`);
  process.exit(evidence.pass ? 0 : 1);
}

main().catch((err) => {
  process.stderr.write(`SEC-04 staging error: ${err.message}\n`);
  process.exit(1);
});