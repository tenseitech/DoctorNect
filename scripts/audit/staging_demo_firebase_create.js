'use strict';

/**
 * Staging demo Firebase Auth users — probe (read-only) | plan | execute (gated).
 * Create-only: never update/delete existing Firebase users.
 * Project: medibond-45fad
 */

const fs = require('fs');
const path = require('path');
const { getEnv } = require('../lib/env_loader');
const { loadRootEnv } = require('../lib/bootstrap_root_env');

loadRootEnv();

const PROJECT_ID = 'medibond-45fad';
const PHASE = (() => {
  const a = process.argv.find((x) => x.startsWith('--phase='));
  return a ? a.split('=')[1] : 'probe';
})();

const FIREBASE_DEMO_UID_BY_DIGITS = {
  '9999900001': 'rev_fb_pat_001',
  '9999900002': 'rev_fb_doc_001',
  '9999900003': 'rev_fb_store_001',
  '9999900004': 'rev_fb_lab_001',
  '9999900005': 'rev_fb_amb_001',
};

const DEMOS = [
  { digits: '9999900001', role: 'patient', uid: FIREBASE_DEMO_UID_BY_DIGITS['9999900001'], name: 'Demo Patient' },
  { digits: '9999900002', role: 'doctor', uid: FIREBASE_DEMO_UID_BY_DIGITS['9999900002'], name: 'Demo Doctor' },
  { digits: '9999900003', role: 'medicalStore', uid: FIREBASE_DEMO_UID_BY_DIGITS['9999900003'], name: 'Demo Pharmacy' },
  { digits: '9999900004', role: 'lab', uid: FIREBASE_DEMO_UID_BY_DIGITS['9999900004'], name: 'Demo Lab' },
  { digits: '9999900005', role: 'ambulance', uid: FIREBASE_DEMO_UID_BY_DIGITS['9999900005'], name: 'Demo Ambulance' },
];

function phoneE164(digits) {
  return `+91${digits}`;
}

function initAdmin() {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) return admin;
  const candidates = [
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    getEnv('FIREBASE_SERVICE_ACCOUNT_PATH'),
    path.join(__dirname, '..', 'service-account.json'),
    path.join(__dirname, '..', '..', 'service-account.json'),
  ];
  const saPath = candidates.find((p) => p && fs.existsSync(p));
  if (!saPath) {
    throw new Error('[FIREBASE] Service account file not found (set GOOGLE_APPLICATION_CREDENTIALS or add service-account.json).');
  }
  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const projectId = sa.project_id || getEnv('FIREBASE_PROJECT_ID') || PROJECT_ID;
  admin.initializeApp({ credential: admin.credential.cert(sa), projectId });
  return admin;
}

function supabaseClaims(role) {
  return {
    role: 'authenticated',
    app_role: role,
    user_role: role,
  };
}

async function probeAuth(auth) {
  const report = { project: PROJECT_ID, phones: {}, uids: {}, conflicts: [] };
  for (const d of DEMOS) {
    const phone = phoneE164(d.digits);
    report.phones[d.digits] = { exists: false, uid: null, masked: phone.replace(/\d(?=\d{4})/g, '*') };
    try {
      const u = await auth.getUserByPhoneNumber(phone);
      report.phones[d.digits].exists = true;
      report.phones[d.digits].uid = u.uid;
      if (u.uid !== d.uid) {
        report.conflicts.push({ type: 'phone_uid_mismatch', digits: d.digits, existing_uid: u.uid, planned_uid: d.uid });
      }
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
    report.uids[d.uid] = { exists: false };
    try {
      const u = await auth.getUser(d.uid);
      report.uids[d.uid].exists = true;
      report.uids[d.uid].phone_suffix = String(u.phoneNumber || '').slice(-4);
      if (u.phoneNumber && u.phoneNumber !== phone) {
        report.conflicts.push({ type: 'uid_phone_mismatch', uid: d.uid, existing_phone_suffix: u.phoneNumber.slice(-4) });
      }
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
  }
  return report;
}

async function executeCreate(auth) {
  const created = [];
  for (const d of DEMOS) {
    const phone = phoneE164(d.digits);
    try {
      await auth.getUser(d.uid);
      created.push({ uid: d.uid, action: 'skip_exists' });
      continue;
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
    try {
      await auth.getUserByPhoneNumber(phone);
      throw new Error(`[ABORT] Phone ${d.digits} already registered to another UID — create-only policy`);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
    const rec = await auth.createUser({
      uid: d.uid,
      phoneNumber: phone,
      displayName: d.name,
      disabled: false,
    });
    await auth.setCustomUserClaims(d.uid, supabaseClaims(d.role));
    created.push({ uid: rec.uid, role: d.role, action: 'created' });
  }
  return created;
}

async function main() {
  const admin = initAdmin();
  const auth = admin.auth();
  if (PHASE === 'probe' || PHASE === 'plan') {
    const report = await probeAuth(auth);
    console.log(JSON.stringify({ phase: PHASE, uid_scheme: 'public.users.id === Firebase Auth uid (FIRESTORE_FORBIDDEN postgres mobile lookup)', ...report }, null, 2));
    if (PHASE === 'plan') {
      console.log('\n--- PLANNED CREATE (not executed) ---\n');
      for (const d of DEMOS) {
        console.log(JSON.stringify({
          uid: d.uid,
          phone: phoneE164(d.digits),
          displayName: d.name,
          claims: supabaseClaims(d.role),
        }));
      }
    }
    return;
  }
  if (PHASE === 'execute') {
    if (!process.argv.includes('--approved-staging-user-reset')) {
      console.error('[BLOCKED] Pass --approved-staging-user-reset after operator approval.');
      process.exit(1);
    }
    const report = await probeAuth(auth);
    if (report.conflicts.length > 0) {
      console.error('[ABORT] Conflicts:', JSON.stringify(report.conflicts));
      process.exit(1);
    }
  const allReady = DEMOS.every((d) => report.uids[d.uid]?.exists && report.phones[d.digits]?.uid === d.uid);
    if (!allReady) {
      console.error('[ABORT] Expected all reviewer Firebase users present; create/modify disabled in this run.');
      process.exit(1);
    }
    console.log(JSON.stringify({ phase: 'execute', action: 'no_op_probe_only', created: 0, modified: 0, report }, null, 2));
    return;
  }
  console.error('Unknown --phase (probe|plan|execute)');
  process.exit(1);
}

main().catch((e) => {
  console.error('[FAIL]', e.message);
  process.exit(1);
});