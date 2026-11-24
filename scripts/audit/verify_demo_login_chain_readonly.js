#!/usr/bin/env node
'use strict';

/**
 * Read-only demo login chain: Firebase Auth (medibond-45fad via service account),
 * Supabase staging public.users, and absence from AWS RDS production.
 *
 * Replaces the retired Firestore-based checker (ADC without project + Firestore users lookup).
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { buildRdsPoolConfig, maskRdsTarget } = require('../lib/rds_pool_config');

loadRootEnv();

const EXPECTED_FIREBASE_PROJECT = 'medibond-45fad';

const DEMOS = [
  { digits: '9999900001', role: 'patient', uid: 'rev_fb_pat_001' },
  { digits: '9999900002', role: 'doctor', uid: 'rev_fb_doc_001' },
  { digits: '9999900003', role: 'medicalStore', uid: 'rev_fb_store_001' },
  { digits: '9999900004', role: 'lab', uid: 'rev_fb_lab_001' },
  { digits: '9999900005', role: 'ambulance', uid: 'rev_fb_amb_001' },
];

function maskPhone(digits) {
  const d = String(digits || '').replace(/\D/g, '').slice(-10);
  return d ? `${d.slice(0, 2)}****${d.slice(-2)}` : '(invalid)';
}

function phoneE164(digits) {
  return `+91${digits}`;
}

function mobileCandidates(digits) {
  return [digits, `+91${digits}`, `91${digits}`];
}

function initFirebaseAdmin() {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) {
    return { admin, projectId: admin.app().options.projectId };
  }
  const candidates = [
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    getEnv('FIREBASE_SERVICE_ACCOUNT_PATH'),
    path.join(__dirname, '..', 'service-account.json'),
    path.join(__dirname, '..', '..', 'service-account.json'),
  ];
  const saPath = candidates.find((p) => p && fs.existsSync(p));
  if (!saPath) {
    throw new Error(
      '[FIREBASE] Service account file required (same as staging_demo_firebase_create.js). ADC alone is not used.',
    );
  }
  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const projectId = sa.project_id || getEnv('FIREBASE_PROJECT_ID') || EXPECTED_FIREBASE_PROJECT;
  admin.initializeApp({ credential: admin.credential.cert(sa), projectId });
  return { admin, projectId, saPath: path.basename(saPath) };
}

function resolveProjectExpectations() {
  const appEnv = String(getEnv('APP_ENV') || 'staging').toLowerCase();
  const flutterProjectDefault =
    appEnv === 'production' ? 'medibond-45fad' : 'medibond-staging';
  const gatewayUrl = String(getEnv('PROD_GATEWAY_URL') || '').trim();
  let gatewayHost = null;
  try {
    if (gatewayUrl) gatewayHost = new URL(gatewayUrl).hostname;
  } catch (_) {
    gatewayHost = '(unparseable)';
  }
  return {
    appEnv,
    flutterProjectWhenNoDartDefine: flutterProjectDefault,
    flutterProductionProject: 'medibond-45fad',
    flutterStagingProject: 'medibond-staging',
    envFirebaseProjectId: getEnv('FIREBASE_PROJECT_ID') || null,
    envGcloudProject: getEnv('GCLOUD_PROJECT') || getEnv('GOOGLE_CLOUD_PROJECT') || null,
    otpFunctionsProject: EXPECTED_FIREBASE_PROJECT,
    prodGatewayHostMasked: gatewayHost,
    note:
      'Demo Auth users live on medibond-45fad. Flutter default APP_ENV=staging targets medibond-staging unless --dart-define=APP_ENV=production or FIREBASE_PROJECT_ID=medibond-45fad.',
  };
}

async function probeFirebaseAuth(auth, projectId) {
  const rows = [];
  for (const d of DEMOS) {
    const phone = phoneE164(d.digits);
    const entry = {
      mobile: maskPhone(d.digits),
      expectedRole: d.role,
      expectedUid: d.uid,
      firebaseProjectId: projectId,
      authByPhone: { exists: false, uid: null, phoneSuffix: null },
      authByUid: { exists: false, phoneSuffix: null, disabled: null },
      authOk: false,
    };
    try {
      const byPhone = await auth.getUserByPhoneNumber(phone);
      entry.authByPhone.exists = true;
      entry.authByPhone.uid = byPhone.uid;
      entry.authByPhone.phoneSuffix = String(byPhone.phoneNumber || '').slice(-4);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') entry.authByPhone.error = e.code || e.message;
    }
    try {
      const byUid = await auth.getUser(d.uid);
      entry.authByUid.exists = true;
      entry.authByUid.uid = byUid.uid;
      entry.authByUid.phoneSuffix = String(byUid.phoneNumber || '').slice(-4);
      entry.authByUid.disabled = Boolean(byUid.disabled);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') entry.authByUid.error = e.code || e.message;
    }
    entry.authOk =
      entry.authByPhone.exists
      && entry.authByUid.exists
      && entry.authByPhone.uid === d.uid
      && entry.authByUid.uid === d.uid;
    rows.push(entry);
  }
  return rows;
}

async function probeSupabaseStaging() {
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL') || getEnv('PROD_SUPABASE_DB_URL');
  if (!dbUrl) {
    return {
      skipped: true,
      reason: 'STAGING_SUPABASE_DB_URL not set in root .env',
      connection: null,
      rows: DEMOS.map((d) => ({
        mobile: maskPhone(d.digits),
        expectedUid: d.uid,
        expectedRole: d.role,
        supabaseOk: false,
        skipped: true,
      })),
    };
  }
  const guard = assertDatabaseGuard({
    targetKind: 'staging',
    operationName: 'verify_demo_login_chain',
  });
  const pool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  const client = await pool.connect();
  const rows = [];
  try {
    for (const d of DEMOS) {
      const byId = await client.query(
        `SELECT id, role, mobile, profile_id, verified FROM public.users WHERE id = $1`,
        [d.uid],
      );
      const byMobile = await client.query(
        `SELECT id, role, mobile FROM public.users WHERE mobile = ANY($1::text[]) LIMIT 3`,
        [mobileCandidates(d.digits)],
      );
      const row = byId.rows[0] || null;
      const mobileRow = byMobile.rows[0] || null;
      rows.push({
        mobile: maskPhone(d.digits),
        expectedUid: d.uid,
        expectedRole: d.role,
        supabaseStagingHost: guard.host,
        byId: row
          ? {
              id: row.id,
              role: row.role,
              mobileSuffix: String(row.mobile || '').replace(/\D/g, '').slice(-4) || null,
              verified: row.verified,
            }
          : null,
        byMobileLookup: mobileRow
          ? { id: mobileRow.id, role: mobileRow.role }
          : null,
        supabaseOk: Boolean(
          row
          && row.id === d.uid
          && row.role === d.role
          && mobileRow
          && mobileRow.id === d.uid,
        ),
      });
    }
  } finally {
    client.release();
    await pool.end();
  }
  return { skipped: false, connection: maskConnectionString(dbUrl), rows };
}

async function probeRdsProductionAbsence() {
  let cfg;
  try {
    cfg = buildRdsPoolConfig({
      user: getEnv('PROD_RDS_MASTER_USER') || getEnv('PROD_RDS_USER'),
    });
    cfg.password = getEnv('PROD_RDS_MASTER_PASSWORD') || getEnv('PROD_RDS_PASSWORD');
  } catch (e) {
    return { skipped: true, reason: e.message || String(e), rows: [] };
  }

  const client = new Client(cfg);
  const rows = [];
  try {
    await client.connect();
    await client.query('BEGIN READ ONLY');
    for (const d of DEMOS) {
      const byId = await client.query(
        'SELECT id, role, mobile FROM public.users WHERE id = $1 LIMIT 1',
        [d.uid],
      );
      const byMobile = await client.query(
        `SELECT id, role, mobile FROM public.users
         WHERE right(regexp_replace(COALESCE(mobile, ''), '\\D', '', 'g'), 10) = $1 LIMIT 1`,
        [d.digits],
      );
      const hit = byId.rows[0] || byMobile.rows[0] || null;
      rows.push({
        mobile: maskPhone(d.digits),
        expectedUid: d.uid,
        rdsTarget: maskRdsTarget(cfg),
        presentInRds: Boolean(hit),
        row: hit ? { id: hit.id, role: hit.role } : null,
        rdsOk: !hit,
      });
    }
    await client.query('ROLLBACK');
  } catch (e) {
    return {
      skipped: true,
      reason: e.message || String(e),
      rdsTarget: maskRdsTarget(cfg),
      rows,
    };
  } finally {
    await client.end().catch(() => {});
  }
  return { skipped: false, rdsTarget: maskRdsTarget(cfg), rows };
}

async function main() {
  console.log(
    JSON.stringify({
      script: 'verify_demo_login_chain_readonly',
      retiredCheckerReason:
        'Old check_reviewer_login_users_readonly.js used applicationDefault() (often wrong project / invalid_rapt) and required Firestore users/*; login now uses Firebase Auth + Postgres public.users.',
    }),
  );

  const projectExpect = resolveProjectExpectations();
  const { admin, projectId, saPath } = initFirebaseAdmin();
  const auth = admin.auth();

  const report = {
    projectAlignment: {
      ...projectExpect,
      firebaseAuthAdminProjectId: projectId,
      firebaseAuthUsesServiceAccount: saPath,
      matchesExpectedOtpProject: projectId === EXPECTED_FIREBASE_PROJECT,
    },
    firebaseAuth: await probeFirebaseAuth(auth, projectId),
    supabaseStaging: await probeSupabaseStaging(),
    rdsProduction: await probeRdsProductionAbsence(),
  };

  let failures = 0;
  for (let i = 0; i < DEMOS.length; i += 1) {
    const fa = report.firebaseAuth[i];
    const sb = report.supabaseStaging.rows[i];
    const rd = report.rdsProduction.rows[i];
    const supabaseState = report.supabaseStaging.skipped
      ? 'skipped'
      : sb?.supabaseOk;
    const lineOk =
      fa?.authOk
      && (report.supabaseStaging.skipped || sb?.supabaseOk)
      && (report.rdsProduction.skipped || rd?.rdsOk);
    if (!lineOk) failures += 1;
    console.log(
      JSON.stringify({
        summary: i + 1,
        mobile: maskPhone(DEMOS[i].digits),
        role: DEMOS[i].role,
        firebaseAuth: fa?.authOk,
        supabaseStaging: supabaseState,
        absentFromRds: report.rdsProduction.skipped ? 'skipped' : rd?.rdsOk,
        ok: lineOk,
      }),
    );
  }

  console.log(JSON.stringify(report, null, 2));

  if (!report.projectAlignment.matchesExpectedOtpProject) {
    console.error(
      `[FAIL] Firebase Admin project "${projectId}" !== expected OTP project "${EXPECTED_FIREBASE_PROJECT}".`,
    );
    process.exit(1);
  }

  if (report.supabaseStaging.skipped) {
    console.warn(`[WARN] Supabase staging check skipped: ${report.supabaseStaging.reason}`);
  }
  if (report.rdsProduction.skipped) {
    console.warn(`[WARN] RDS absence check skipped: ${report.rdsProduction.reason}`);
  }

  const firebaseAllOk = report.firebaseAuth.every((r) => r.authOk);
  if (!firebaseAllOk || failures > 0) {
    console.error(
      `\n[FAIL] ${failures}/5 demo chain summary failed (Firebase must pass). Auth-only probe: node scripts/audit/staging_demo_firebase_create.js --phase=probe`,
    );
    process.exit(1);
  }

  if (report.supabaseStaging.skipped || report.rdsProduction.skipped) {
    console.warn(
      '\n[PARTIAL] Firebase Auth OK for 5/5. Re-run with STAGING_SUPABASE_DB_URL in .env and PROD RDS tunnel (port 5434) for full chain.',
    );
    process.exit(2);
  }
  console.log('\n[PASS] All 5 demo login chains verified (Firebase + staging Supabase + RDS absence).');
}

main().catch((err) => {
  const msg = err.message || String(err);
  console.error('[FAIL]', msg);
  if (/invalid_grant|invalid_rapt/i.test(msg)) {
    console.error(
      'Hint: use scripts/service-account.json for medibond-45fad (same as staging_demo_firebase_create.js --phase=probe), not only ADC.',
    );
  }
  process.exit(1);
});