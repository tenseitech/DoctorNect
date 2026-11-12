'use strict';

/**
 * Proves service_role paths used by gateway + Cloud Functions against fresh local DB.
 * Does not connect to staging/production.
 */

const { Client } = require('pg');
const { buildPostgrestPayload } = require('../../services/api-gateway/src/jwt_minter');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { seedFixtures } = require('./gateway_rls_authorization_suite');

const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

function dbUrl() {
  const base = getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

function serviceClaims() {
  return JSON.stringify(buildPostgrestPayload({ role: 'service_role' }));
}

function patientClaims(uid) {
  return JSON.stringify(buildPostgrestPayload({ role: 'authenticated', sub: uid, appRole: 'patient', verified: true }));
}

const results = [];

function record(name, pass, detail = '') {
  results.push({ name, verdict: pass ? 'PASS' : 'FAIL', detail });
}

async function asRole(client, role, claims, sql, params = []) {
  await client.query('SAVEPOINT sp_svc');
  await client.query(`SET LOCAL ROLE ${role}`);
  await client.query(`SELECT set_config('request.jwt.claims', $1, true)`, [claims]);
  try {
    const res = await client.query(sql, params);
    await client.query('ROLLBACK TO SAVEPOINT sp_svc');
    await client.query('RESET ROLE');
    return { ok: true, res };
  } catch (err) {
    await client.query('ROLLBACK TO SAVEPOINT sp_svc');
    await client.query('RESET ROLE');
    return { ok: false, err };
  }
}

async function main() {
  console.log('Service-role path tests (fresh local)');
  console.log(`DB: ${maskConnectionString(dbUrl())}\n`);

  const client = new Client({ connectionString: dbUrl() });
  await client.connect();
  const before = (await client.query(`SELECT count(*)::int n FROM users`)).rows[0].n;
  await client.query('BEGIN');
  const ids = await seedFixtures(client);

  // notification_outbox (worker)
  let r = await asRole(client, 'service_role', serviceClaims(), `SELECT 1 FROM public.notification_outbox LIMIT 1`);
  record('service_role SELECT notification_outbox', r.ok);

  r = await asRole(
    client,
    'service_role',
    serviceClaims(),
    `INSERT INTO public.notification_outbox (dedupe_key, table_name, event_type, payload)
     VALUES ('svc_test_key', 'users', 'TEST', '{}'::jsonb) RETURNING id`,
  );
  record('service_role INSERT notification_outbox', r.ok && r.res.rowCount === 1);

  r = await asRole(client, 'authenticated', patientClaims(ids.pA), `SELECT 1 FROM public.notification_outbox LIMIT 1`);
  record('authenticated denied notification_outbox', !r.ok || r.res.rowCount === 0);

  // sync_dead_letter_queue (service-role-only table)
  r = await asRole(client, 'service_role', serviceClaims(), `SELECT 1 FROM public.sync_dead_letter_queue LIMIT 1`);
  record('service_role SELECT sync_dead_letter_queue', r.ok);

  r = await asRole(client, 'authenticated', patientClaims(ids.pA), `SELECT 1 FROM public.sync_dead_letter_queue LIMIT 1`);
  record('authenticated denied sync_dead_letter_queue', !r.ok || r.res.rowCount === 0);

  // admin_audit_logs: service_role DML; authenticated insert denied (migration 05)
  r = await asRole(
    client,
    'service_role',
    serviceClaims(),
    `INSERT INTO public.admin_audit_logs (log_id, admin_uid, admin_email, action, target_type, target_id, details)
     VALUES ('svc_audit_1', $1::varchar, 'svc@test', 'TEST', 'user', $2::varchar, '{}')`,
    [ids.pA, ids.pA],
  );
  record('service_role INSERT admin_audit_logs', r.ok, r.ok ? '' : r.err?.message || '');

  r = await asRole(
    client,
    'authenticated',
    patientClaims(ids.pA),
    `INSERT INTO public.admin_audit_logs (log_id, admin_uid, admin_email, action, target_type, target_id, details)
     VALUES ('svc_audit_2', $1::varchar, 'x@test', 'TEST', 'user', $2::varchar, '{}')`,
    [ids.pA, ids.pA],
  );
  record('authenticated denied admin_audit_logs INSERT', !r.ok);

  // otp_challenges service-only table
  r = await asRole(client, 'service_role', serviceClaims(), `SELECT 1 FROM public.otp_challenges LIMIT 1`);
  record('service_role SELECT otp_challenges', r.ok);

  r = await asRole(client, 'authenticated', patientClaims(ids.pA), `SELECT 1 FROM public.otp_challenges LIMIT 1`);
  record('authenticated denied otp_challenges', !r.ok || (r.res && r.res.rowCount === 0));

  // book_appointment_atomic (patient RPC; gateway allowlist / PostgREST)
  r = await asRole(
    client,
    'authenticated',
    patientClaims(ids.pA),
    `SELECT public.book_appointment_atomic(
      'svc_appt_1', $1::varchar, 'Doc A', 'Gen', 'Pat A', 30, 'Male',
      (CURRENT_TIMESTAMP + interval '3 days'), '10:00', 'newVisit',
      NULL::int, NULL::varchar, NULL::varchar, 'patient_supabase', $2::varchar
    )`,
    [ids.docA, ids.pA],
  );
  record('authenticated book_appointment_atomic', r.ok, r.ok ? '' : r.err?.message || '');

  await client.query('ROLLBACK');
  await client.end();

  const afterClient = new Client({ connectionString: dbUrl() });
  await afterClient.connect();
  const after = (await afterClient.query(`SELECT count(*)::int n FROM users`)).rows[0].n;
  await afterClient.end();
  if (after !== before) {
    console.error('Zero-residue failed');
    process.exit(1);
  }

  console.table(results);
  const fails = results.filter((x) => x.verdict === 'FAIL').length;
  console.log(`\n${results.length - fails} PASS / ${fails} FAIL`);
  process.exit(fails ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
