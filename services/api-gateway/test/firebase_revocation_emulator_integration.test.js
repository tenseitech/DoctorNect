'use strict';

/**
 * Live Firebase Auth Emulator + Admin SDK revocation (not mocked).
 * Run: firebase emulators:exec --only auth --project demo-doctornect-kyc -- npm test -- test/firebase_revocation_emulator_integration.test.js
 * Or set FIREBASE_AUTH_EMULATOR_HOST (e.g. 127.0.0.1:9099) and RUN_FIREBASE_AUTH_EMULATOR_INTEGRATION=1
 */
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFirebaseTokenNotRevoked,
  resetFirebaseAdminForTesting,
} = require('../src/firebase_revocation');

const emulatorHost = String(process.env.FIREBASE_AUTH_EMULATOR_HOST || '').trim();
const runIntegration = String(process.env.RUN_FIREBASE_AUTH_EMULATOR_INTEGRATION || '').trim() === '1';
const describeIntegration = runIntegration && emulatorHost ? describe : describe.skip;

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'demo-doctornect-kyc';

async function signInWithPassword(email, password) {
  const url =
    `http://${emulatorHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: true,
    }),
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(body.error?.message || 'Emulator sign-in failed');
  }
  return body.idToken;
}

describeIntegration('Firebase Auth Emulator revocation (SEC-04 integration)', () => {
  before(() => {
    delete process.env.DISABLE_FIREBASE_ADMIN_INIT;
    resetFirebaseAdminForTesting();
    process.env.FIREBASE_AUTH_EMULATOR_HOST = emulatorHost;
    process.env.FIREBASE_PROJECT_ID = PROJECT_ID;
    process.env.GCLOUD_PROJECT = PROJECT_ID;
  });

  after(() => {
    process.env.DISABLE_FIREBASE_ADMIN_INIT = '1';
    resetFirebaseAdminForTesting();
  });

  it('Admin verifyIdToken(checkRevoked) accepts valid emulator token before revocation', async () => {
    const { initializeApp, getApps, deleteApp } = require('firebase-admin/app');
    const { getAuth } = require('firebase-admin/auth');

    for (const app of getApps()) {
      await deleteApp(app);
    }
    resetFirebaseAdminForTesting();

    initializeApp({ projectId: PROJECT_ID });
    const auth = getAuth();

    const email = `audit1_pre_${Date.now()}@doctornect-audit1.test`;
    const password = 'Audit1TestPassword!19';
    const user = await auth.createUser({ email, password });

    try {
      const idToken = await signInWithPassword(email, password);
      await auth.verifyIdToken(idToken, true);
      await assert.doesNotReject(() => assertFirebaseTokenNotRevoked(idToken, { required: true }));
    } finally {
      await auth.deleteUser(user.uid).catch(() => {});
      for (const app of getApps()) {
        await deleteApp(app);
      }
      resetFirebaseAdminForTesting();
    }
  });

  it('Admin verifyIdToken(checkRevoked) rejects token after revokeRefreshTokens', async (t) => {
    const { initializeApp, getApps, deleteApp } = require('firebase-admin/app');
    const { getAuth } = require('firebase-admin/auth');

    for (const app of getApps()) {
      await deleteApp(app);
    }
    resetFirebaseAdminForTesting();

    initializeApp({ projectId: PROJECT_ID });
    const auth = getAuth();

    const email = `audit1_revoke_${Date.now()}@doctornect-audit1.test`;
    const password = 'Audit1TestPassword!19';
    const user = await auth.createUser({ email, password });

    try {
      const idToken = await signInWithPassword(email, password);
      await assert.doesNotReject(() => assertFirebaseTokenNotRevoked(idToken, { required: true }));

      await auth.revokeRefreshTokens(user.uid);
      await new Promise((r) => setTimeout(r, 1000));

      let emulatorHonorsRevocation = false;
      try {
        await auth.verifyIdToken(idToken, true);
      } catch (err) {
        emulatorHonorsRevocation = true;
        if (err.code !== 'auth/id-token-revoked') {
          throw err;
        }
      }

      if (!emulatorHonorsRevocation) {
        t.skip(
          'Firebase Auth Emulator does not enforce verifyIdToken(checkRevoked) after revokeRefreshTokens '
          + '(observed 2026-11-25). Complete SEC-04 staging ADC step in docs/audit/SECURITY_AUDIT_1_STAGING_CHECKLIST.md.',
        );
        return;
      }

      await assert.rejects(
        () => assertFirebaseTokenNotRevoked(idToken, { required: true }),
        /revoked/i,
      );
    } finally {
      await auth.deleteUser(user.uid).catch(() => {});
      for (const app of getApps()) {
        await deleteApp(app);
      }
      resetFirebaseAdminForTesting();
    }
  });
});