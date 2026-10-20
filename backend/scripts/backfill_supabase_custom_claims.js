/**
 * DoctorNect: One-Time Firebase Auth Custom Claims Backfill for Supabase Bridge
 * File: backend/scripts/backfill_supabase_custom_claims.js
 * 
 * Purpose:
 * Backfills Firebase Auth custom claims for all existing users so that their
 * Firebase ID tokens carry:
 *   - role: 'authenticated'   (required by Supabase PostgREST)
 *   - app_role: '<role>'       (doctor | patient | pharmacy | lab | ambulance | super_admin)
 *   - user_role: '<role>'      (for Postgres RLS auth.jwt()->>'user_role')
 * 
 * Usage:
 *   Dry-run mode (Read-only, default):
 *     node scripts/backfill_supabase_custom_claims.js
 * 
 *   Apply mode (Writes claims to Firebase Auth):
 *     node scripts/backfill_supabase_custom_claims.js --apply
 * 
 * Environment variables:
 *   GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_PATH
 */

'use strict';

const fs = require('fs');
const path = require('path');

// Safe environment loading
const loadEnvPath = path.join(__dirname, 'load_env.js');
if (fs.existsSync(loadEnvPath)) {
  try {
    require('./load_env').loadEnv();
  } catch (_) {}
}

const admin = require('firebase-admin');

const args = process.argv.slice(2);
const IS_APPLY = args.includes('--apply');

function normalizeRole(role) {
  const r = String(role || '').trim();
  if (r === 'superAdmin' || r === 'super_admin' || r === 'admin') {
    return 'super_admin';
  }
  if (r === 'medicalStore' || r === 'medical' || r === 'pharmacy') {
    return 'pharmacy';
  }
  return r || 'patient';
}

function initFirebaseAdmin() {
  if (admin.apps.length > 0) return admin.app();

  const saCandidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(process.cwd(), 'service-account.json'),
    path.join(__dirname, '..', 'service-account.json'),
  ];
  const saPath = saCandidates.find((p) => p && fs.existsSync(p));

  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad',
    });
  }

  return admin.initializeApp({ projectId: 'medibond-45fad' });
}

async function runBackfill() {
  console.log('================================================================');
  console.log(`DOCTORNECT: SUPABASE AUTH CLAIMS BACKFILL [${IS_APPLY ? 'APPLY MODE' : 'DRY RUN'}]`);
  console.log('================================================================\n');

  initFirebaseAdmin();
  const db = admin.firestore();
  const auth = admin.auth();

  console.log('[Backfill] Querying Firestore users collection...');
  const usersSnapshot = await db.collection('users').get();
  console.log(`[Backfill] Found ${usersSnapshot.size} user records in Firestore.\n`);

  let alreadyCorrect = 0;
  let toUpdate = 0;
  let authUserNotFound = 0;
  let errors = 0;
  const updates = [];

  for (const doc of usersSnapshot.docs) {
    const uid = doc.id;
    const data = doc.data() || {};
    const rawRole = data.role || 'patient';
    const normalized = normalizeRole(rawRole);

    const targetClaims = {
      role: 'authenticated',
      app_role: normalized,
      user_role: normalized,
    };

    try {
      const userRecord = await auth.getUser(uid);
      const existingClaims = userRecord.customClaims || {};

      const isMatch =
        existingClaims.role === 'authenticated' &&
        existingClaims.app_role === normalized &&
        existingClaims.user_role === normalized;

      if (isMatch) {
        alreadyCorrect++;
        continue;
      }

      toUpdate++;
      const mergedClaims = { ...existingClaims, ...targetClaims };

      if (IS_APPLY) {
        await auth.setCustomUserClaims(uid, mergedClaims);
        console.log(`[APPLIED] UID: ${uid} | Role: ${normalized} | Claims updated.`);
      } else {
        console.log(`[DRY-RUN] UID: ${uid} | Role: ${normalized} | Would update claims:`, JSON.stringify(mergedClaims));
      }

      updates.push({
        uid,
        email: userRecord.email || '',
        previousRole: existingClaims.app_role || existingClaims.role || 'none',
        targetRole: normalized,
        status: IS_APPLY ? 'updated' : 'pending',
      });
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        authUserNotFound++;
        console.warn(`[WARN] UID: ${uid} exists in Firestore users, but no Firebase Auth record found.`);
      } else {
        errors++;
        console.error(`[ERROR] UID: ${uid} failed: ${err.message}`);
      }
    }
  }

  const report = {
    timestamp: new Date().toISOString(),
    mode: IS_APPLY ? 'apply' : 'dry-run',
    totalFirestoreUsers: usersSnapshot.size,
    alreadyCorrect,
    updated: IS_APPLY ? toUpdate : 0,
    pendingUpdate: !IS_APPLY ? toUpdate : 0,
    authUserNotFound,
    errors,
  };

  const reportPath = path.join(__dirname, 'backfill_supabase_custom_claims_report.json');
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

  console.log('\n================================================================');
  console.log('BACKFILL SUMMARY');
  console.log('================================================================');
  console.log(`Total Firestore Users:   ${report.totalFirestoreUsers}`);
  console.log(`Already Had Claims:      ${alreadyCorrect}`);
  console.log(`Claims Updated:          ${IS_APPLY ? toUpdate : 0} (${!IS_APPLY ? toUpdate + ' pending --apply' : '0 pending'})`);
  console.log(`Auth Records Not Found:  ${authUserNotFound}`);
  console.log(`Errors:                  ${errors}`);
  console.log(`Report saved to:         ${reportPath}`);
  console.log('================================================================\n');

  if (!IS_APPLY && toUpdate > 0) {
    console.log('Run with --apply to write custom claims to Firebase Auth:');
    console.log('  node scripts/backfill_supabase_custom_claims.js --apply\n');
  }
}

if (require.main === module) {
  runBackfill().catch((err) => {
    console.error('Fatal error during backfill:', err);
    process.exit(1);
  });
}

module.exports = {
  runBackfill,
  normalizeRole,
};
