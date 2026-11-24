#!/usr/bin/env node
'use strict';

/**
 * Read-only post-deploy checks for demo routing + reviewer OTP.
 * No writes, no user reset, no MSG91 sends (reviewer path only).
 */

const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { findRepoRoot } = require('../lib/repo_root');
const { resolveDataPlane } = require('../lib/demo_routing');
const {
  assertDemoUidNotOnRds,
  assertServiceRoleRdsQuerySafe,
} = require('../lib/rds_demo_uid_guard');
const {
  getReviewerConfig,
  isReviewerPhone,
} = require('../../backend/functions/reviewer_otp_config');

const DEMO_UIDS = [
  'rev_fb_pat_001',
  'rev_fb_doc_001',
  'rev_fb_store_001',
  'rev_fb_lab_001',
  'rev_fb_amb_001',
];

function ok(label, detail = '') {
  console.log(`PASS ${label}${detail ? ` — ${detail}` : ''}`);
}

function skip(label, reason) {
  console.log(`SKIP ${label} — ${reason}`);
}

function fail(label, reason) {
  console.error(`FAIL ${label} — ${reason}`);
  return false;
}

async function main() {
  const root = findRepoRoot(__dirname);
  loadRootEnv({ startDir: root, force: true });
  const env = process.env;
  let allPass = true;

  const appEnv = String(env.APP_ENV || 'staging').trim().toLowerCase();
  if (appEnv !== 'production') {
    console.log('Note: APP_ENV is not production; routing checks use current env.');
  }

  if (String(env.DEMO_REAL_ROUTING_ENABLED || '').trim() !== '1') {
    allPass = fail('DEMO_REAL_ROUTING_ENABLED', 'expected 1');
  } else {
    ok('DEMO_REAL_ROUTING_ENABLED');
  }

  for (const uid of DEMO_UIDS) {
    const plane = resolveDataPlane({ appEnv: 'production', firebaseUid: uid, env });
    if (plane !== 'supabase') {
      allPass = fail(`resolveDataPlane(${uid})`, `expected supabase, got ${plane}`);
    } else {
      ok(`resolveDataPlane demo uid`, uid);
    }
  }

  const realUid = 'real_user_not_in_allowlist';
  const realPlane = resolveDataPlane({ appEnv: 'production', firebaseUid: realUid, env });
  if (realPlane !== 'rds') {
    allPass = fail('resolveDataPlane(real uid)', `expected rds, got ${realPlane}`);
  } else {
    ok('resolveDataPlane(real uid)', 'rds');
  }

  try {
    assertDemoUidNotOnRds('rev_fb_pat_001', env);
    allPass = fail('RDS guard demo uid', 'expected throw');
  } catch (e) {
    if (e.code === 'demo_uid_rds_forbidden') {
      ok('RDS guard rejects demo uid on RDS');
    } else {
      allPass = fail('RDS guard demo uid', e.message);
    }
  }

  try {
    assertServiceRoleRdsQuerySafe('/rest/v1/users', 'id=eq.rev_fb_pat_001', env);
    allPass = fail('service_role demo query guard', 'expected throw');
  } catch (e) {
    if (e.code === 'demo_uid_rds_forbidden') {
      ok('service_role demo query guard');
    } else {
      allPass = fail('service_role demo query guard', e.message);
    }
  }

  if (String(env.REVIEWER_OTP_ENABLED || '').toLowerCase() === 'true') {
    const cfg = getReviewerConfig('patient');
    if (!cfg) {
      allPass = fail('reviewer OTP config', 'patient reviewer config null (phones/expiry/secret?)');
    } else if (!isReviewerPhone('9999900001', 'patient')) {
      allPass = fail('reviewer phone', '9999900001 not recognized for patient');
    } else {
      ok('reviewer OTP path', '9999900001 patient (no MSG91 — verify via send/verify callable in staging)');
    }
  } else {
    skip('reviewer OTP', 'REVIEWER_OTP_ENABLED not true');
  }

  if (env.PROD_GATEWAY_URL && env.DEMO_PGRST_URL) {
    ok('gateway URLs configured', 'live upstream probe not run (read-only script)');
  } else {
    skip('gateway upstream probe', 'set PROD_GATEWAY_URL and DEMO_PGRST_URL for manual curl checks');
  }

  process.exit(allPass ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});