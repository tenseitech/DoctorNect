#!/usr/bin/env node
'use strict';

/**
 * Read-only: counts on staging Supabase indicating non-demo / real user rows.
 */

const path = require('path');
const { Client } = require('pg');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { collectDemoPhonesFromEnv, isDemoFirebaseUid, normalizeDigits } = require('../lib/demo_routing');

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const url = getEnv('STAGING_SUPABASE_DB_URL');
  if (!url) {
    console.error('STAGING_SUPABASE_DB_URL required');
    process.exit(1);
  }
  const demoPhones = collectDemoPhonesFromEnv();
  const client = new Client({ connectionString: url });
  await client.connect();
  try {
    await client.query('BEGIN READ ONLY');
    const users = await client.query(`SELECT count(*)::int AS n FROM public.users`);
    const withFirebase = await client.query(
      `SELECT count(*)::int AS n FROM public.users WHERE firebase_uid IS NOT NULL AND firebase_uid <> ''`,
    );
    const otpDemo = await client.query(
      `SELECT count(*)::int AS n FROM public.otp_challenges WHERE is_demo IS TRUE`,
    );
    const otpNonDemo = await client.query(
      `SELECT count(*)::int AS n FROM public.otp_challenges WHERE is_demo IS FALSE OR is_demo IS NULL`,
    );
    const mobileSample = await client.query(
      `SELECT id, role, left(mobile, 2) AS m2, right(mobile, 2) AS m4
       FROM public.users
       WHERE mobile IS NOT NULL
       ORDER BY created_at DESC NULLS LAST
       LIMIT 50`,
    );
    let nonDemoPhoneUsers = 0;
    let demoPhoneUsers = 0;
    let demoUidUsers = 0;
    for (const row of mobileSample.rows) {
      const digits = normalizeDigits(row.mobile);
      if (demoPhones.has(digits)) demoPhoneUsers += 1;
      else if (digits) nonDemoPhoneUsers += 1;
    }
    const uidRows = await client.query(
      `SELECT firebase_uid FROM public.users WHERE firebase_uid IS NOT NULL LIMIT 200`,
    );
    for (const row of uidRows.rows) {
      if (isDemoFirebaseUid(row.firebase_uid)) demoUidUsers += 1;
    }
    await client.query('COMMIT');

    const report = {
      connection: maskConnectionString(url),
      usersTotal: users.rows[0].n,
      usersWithFirebaseUid: withFirebase.rows[0].n,
      otpChallengesDemoFlag: otpDemo.rows[0].n,
      otpChallengesNonDemoFlag: otpNonDemo.rows[0].n,
      sampleLast50Mobile: {
        demoPhonePattern: demoPhoneUsers,
        nonDemoPhonePattern: nonDemoPhoneUsers,
      },
      firebaseUidDemoPatternInSample: demoUidUsers,
      configuredDemoPhoneAllowlistSize: demoPhones.size,
    };
    console.log(JSON.stringify(report, null, 2));
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error('FAIL:', err.message || err);
  process.exit(1);
});