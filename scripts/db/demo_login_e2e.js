#!/usr/bin/env node
'use strict';

/**
 * End-to-end check for the five demo accounts on a throwaway Postgres (Docker):
 *   1. replays all migrations into postgres:17 (scripts/db/run_sql_tests.js --keep)
 *   2. plants the OLD demo mapping (9999900001 = patient) as staging had it
 *   3. seed --execute must refuse (outdated mapping); seed --reset fixes it; a second
 *      --execute creates nothing (idempotent)
 *   4. runs the REAL backend send/verify code (backend/functions/registration_otp.js, unified
 *      'auth' step) against that database for all five numbers with the fixed demo OTP, and
 *      checks role, UID and the profile rows the app reads after sign-in
 *   5. checks that 000000 is refused for a real number
 *
 *   npm run test:demo-login           (Docker must be running)
 *   node scripts/db/demo_login_e2e.js --db-url=postgresql://postgres:sqltest@127.0.0.1:5541/postgres
 */

const path = require('path');
const { spawnSync } = require('child_process');
const assert = require('assert/strict');
const { Client } = require('pg');

const REPO = path.resolve(__dirname, '../..');
const FN = path.join(REPO, 'backend/functions');
const CONTAINER = 'doctornect-sqltest-pg17';
const DEFAULT_URL = 'postgresql://postgres:sqltest@127.0.0.1:5541/postgres';

function sh(args, env = {}) {
  const r = spawnSync(process.execPath, args, {
    cwd: REPO,
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return { code: r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
}

/** Minimal PostgREST-style client over pg (only what the login path uses). */
function pgRestClient(pg) {
  return {
    from(table) {
      const filters = [];
      const params = [];
      let cols = '*';
      let limit = null;
      const q = {
        select(c) { cols = c || '*'; return q; },
        eq(col, v) { params.push(v); filters.push(`"${col}" = $${params.length}`); return q; },
        in(col, vals) { params.push(vals); filters.push(`"${col}" = ANY($${params.length})`); return q; },
        limit(n) { limit = n; return q; },
        maybeSingle() { limit = 1; return q.then((r) => ({ data: r.data[0] || null, error: r.error })); },
        then(resolve, reject) {
          const sql = `SELECT ${cols === '*' ? '*' : cols.split(',').map((c) => `"${c.trim()}"`).join(', ')}
                       FROM public.${table}${filters.length ? ` WHERE ${filters.join(' AND ')}` : ''}${limit ? ` LIMIT ${limit}` : ''}`;
          return pg.query(sql, params).then((res) => ({ data: res.rows, error: null }),
            (err) => ({ data: null, error: { message: err.message } })).then(resolve, reject);
        },
      };
      return q;
    },
  };
}

async function main() {
  const urlArg = (process.argv.find((a) => a.startsWith('--db-url=')) || '').slice(9);
  const ownContainer = !urlArg;
  const dbUrl = urlArg || DEFAULT_URL;
  if (ownContainer) {
    console.log('== replaying migrations into postgres:17 ...');
    const r = sh(['scripts/db/run_sql_tests.js', '--only=17', '--keep', '--no-audits']);
    if (r.code !== 0) throw new Error(`migration replay failed:\n${r.out.slice(-2000)}`);
  }
  const seedEnv = { APP_ENV: 'staging', DEMO_SEED_TARGET: 'staging', PROD_RDS_CONNECT_HOST: 'not-used.invalid', PROD_RDS_HOST: 'not-used.invalid' };
  const seed = (...flags) => sh(['scripts/db/seed_staging_demo_accounts.js', `--db-url=${dbUrl}`, '--allow-local', ...flags], seedEnv);

  const pg = new Client({ connectionString: dbUrl });
  await pg.connect();
  try {
    console.log('== planting the old staging mapping (9999900001 = patient)');
    await pg.query('SET session_replication_role = replica');
    await pg.query(`INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
      VALUES ('rev_fb_pat_001','rev_fb_pat_001','patient','old_pat_profile','Old','old1@demo.doctornect.invalid','+919999900001'),
             ('rev_fb_doc_001','rev_fb_doc_001','doctor','old_doc_profile','Old','old2@demo.doctornect.invalid','+919999900002')
      ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id, mobile = EXCLUDED.mobile`);
    await pg.query(`INSERT INTO public.patients (patient_id, owner_uid, name, mobile) VALUES ('old_pat_profile','rev_fb_pat_001','Old','+919999900001') ON CONFLICT DO NOTHING`);
    await pg.query('SET session_replication_role = origin');

    let r = seed('--execute');
    assert.notEqual(r.code, 0, 'create-only seed must refuse an outdated mapping');
    assert.match(r.out, /outdated number\/role mapping|run --reset/);
    console.log('   create-only seed refused the outdated mapping: OK');

    r = seed('--reset');
    assert.equal(r.code, 0, r.out);
    console.log('   ', r.out.split('\n').filter((l) => /^(Deleted|Created)/.test(l)).join('\n    '));
    r = seed('--execute');
    assert.equal(r.code, 0, r.out);
    const created = JSON.parse(r.out.split('\n').find((l) => l.startsWith('Created:')).slice(8));
    assert.equal(Object.values(created).reduce((a, b) => a + b, 0), 0, 'second run creates nothing');
    console.log('   reset + idempotent re-run: OK');

    const { rows: oldRows } = await pg.query("SELECT count(*)::int AS n FROM public.patients WHERE patient_id = 'old_pat_profile'");
    assert.equal(oldRows[0].n, 0, 'old demo profile removed by reset');

    console.log('== real backend login path (unified auth step) against the seeded database');
    // Never reach MSG91 (or anything else) from this test: answer every HTTPS call locally.
    const https = require('https');
    const { EventEmitter } = require('events');
    const smsCalls = [];
    https.request = (options, callback) => {
      const req = new EventEmitter();
      req.setTimeout = () => {};
      req.destroy = () => {};
      req.write = () => {};
      req.end = () => {
        smsCalls.push(String(options.hostname || options.host || ''));
        process.nextTick(() => {
          const res = new EventEmitter();
          res.statusCode = 200;
          callback(res);
          res.emit('data', JSON.stringify({ type: 'success' }));
          res.emit('end');
        });
      };
      return req;
    };
    Object.assign(process.env, {
      APP_ENV: 'staging', MSG91_AUTH_KEY: 'e2e-hmac-key', MSG91_TEMPLATE_ID: 'e2e',
      REVIEWER_OTP_ENABLED: 'true', REVIEW_FIXED_OTP: '000000', REVIEW_ACCESS_UNTIL: '2099-01-01T00:00:00Z',
    });
    const { initializeApp, getApps } = require(path.join(FN, 'node_modules/firebase-admin/lib/app'));
    if (!getApps().length) initializeApp({ projectId: 'demo-login-e2e' });
    const { getAuth } = require(path.join(FN, 'node_modules/firebase-admin/lib/auth'));
    const auth = getAuth();
    auth.createCustomToken = async (uid) => `token:${uid}`;
    auth.setCustomUserClaims = async () => {};
    const { setRedisClientForTesting } = require(path.join(FN, 'redis'));
    const { createMemoryRedis } = require(path.join(FN, 'test/helpers/memory_redis'));
    setRedisClientForTesting(createMemoryRedis());
    const { setDatabaseClientForTesting } = require(path.join(FN, 'src/db/client'));
    setDatabaseClientForTesting(pgRestClient(pg));
    const otp = require(path.join(FN, 'registration_otp'));
    otp.setReviewerRedisClientForTesting(createMemoryRedis());
    const { DEMO_ACCOUNTS } = require('../lib/demo_accounts');
    const profileTable = { doctor: ['doctors', 'doctor_id'], patient: ['patients', 'patient_id'],
      medicalStore: ['medical_stores', 'store_id'], lab: ['labs', 'lab_id'], ambulance: ['ambulances', 'ambulance_id'] };

    for (const a of DEMO_ACCOUNTS) {
      const sent = await otp.sendUserRegistrationOtp(null, { mobile: a.digits, otpType: 'auth', role: 'patient' }, { clientIp: '10.1.1.1' });
      assert.equal(sent.ok, true);
      const v = await otp.verifyUserRegistrationOtp(null, { mobile: a.digits, otp: '000000', otpType: 'auth', role: 'patient' }, null, { clientIp: '10.1.1.1' });
      assert.equal(v.exists, true, a.digits);
      assert.equal(v.role, a.role, a.digits);
      assert.equal(v.uid, a.uid, a.digits);
      assert.equal(v.customToken, `token:${a.uid}`);
      // What the app reads right after sign-in (users row by uid, then the role profile).
      const { rows: u } = await pg.query('SELECT * FROM public.users WHERE id = $1 OR firebase_uid = $1', [a.uid]);
      assert.equal(u.length, 1);
      const [table, key] = profileTable[a.role];
      const { rows: prof } = await pg.query(`SELECT * FROM public.${table} WHERE ${key} = $1`, [u[0].profile_id]);
      assert.equal(prof.length, 1, `${a.role} profile`);
      if ('verified' in prof[0]) assert.equal(prof[0].verified, true, `${a.role} verified`);
      console.log(`   ${a.digits} -> ${a.role.padEnd(12)} signed in as ${a.uid}, profile ${u[0].profile_id}: OK`);
    }
    assert.equal(smsCalls.length, 0, 'no SMS request for any demo number');
    const { rows: avail } = await pg.query("SELECT count(*)::int AS n FROM public.doctor_availability WHERE doctor_id = 'demo_doctor_001'");
    assert.equal(avail[0].n, 1, 'doctor availability seeded');

    // A real number never accepts the demo OTP.
    await otp.sendUserRegistrationOtp(null, { mobile: '9876500009', otpType: 'auth' }, { clientIp: '10.1.1.2' }).catch(() => {});
    await assert.rejects(
      otp.verifyUserRegistrationOtp(null, { mobile: '9876500009', otp: '000000', otpType: 'auth' }, null, { clientIp: '10.1.1.2' }),
      (e) => ['permission-denied', 'failed-precondition'].includes(e.code),
    );
    assert.equal(smsCalls.length, 1, 'exactly one (stubbed) SMS request: the real number');
    console.log('   000000 refused for a real number: OK (its SMS request was answered locally)');
    console.log('\nDEMO LOGIN E2E PASSED');
  } finally {
    await pg.end().catch(() => {});
    if (ownContainer) spawnSync('docker', ['rm', '-f', CONTAINER], { stdio: 'ignore' });
  }
}

main().catch((e) => {
  console.error(e.stack || e.message);
  if (!process.argv.some((a) => a.startsWith('--db-url='))) spawnSync('docker', ['rm', '-f', CONTAINER], { stdio: 'ignore' });
  process.exit(1);
});
