#!/usr/bin/env node
'use strict';

const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { loadRootEnv } = require('../lib/bootstrap_root_env');

loadRootEnv();

const DEMOS = [
  { digits: '9999900001', role: 'patient', uid: 'rev_fb_pat_001' },
  { digits: '9999900002', role: 'doctor', uid: 'rev_fb_doc_001' },
  { digits: '9999900003', role: 'medicalStore', uid: 'rev_fb_store_001' },
  { digits: '9999900004', role: 'lab', uid: 'rev_fb_lab_001' },
  { digits: '9999900005', role: 'ambulance', uid: 'rev_fb_amb_001' },
];

const ADMIN = {
  id: 'wfT7vh7pakYR64scZkXrFcOefDZ2',
  email: 'admin@doctornect.com',
  mobileDigits: '9359503874',
};

function mobileCandidates(digits) {
  return [digits, `+91${digits}`, `+91 ${digits}`, `+91-${digits}`, `91${digits}`, `0${digits}`];
}

async function loginLookup(client, digits) {
  const candidates = mobileCandidates(digits);
  const r = await client.query(
    `SELECT id, role, mobile, profile_id FROM public.users WHERE mobile = ANY($1::text[]) LIMIT 1`,
    [candidates],
  );
  if (!r.rows[0]) return { found: false };
  return { found: true, uid: r.rows[0].id, role: r.rows[0].role, mobile: r.rows[0].mobile, profile_id: r.rows[0].profile_id };
}

async function main() {
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'staging_demo_no_admin_verify' });
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  const client = await pool.connect();
  try {
    const report = { connection: maskConnectionString(dbUrl), ok: true, errors: [] };

    report.public_users = (await client.query(`SELECT count(*)::int AS c FROM public.users`)).rows[0].c;
    report.private_admin_users = (await client.query(`SELECT count(*)::int AS c FROM private.admin_users`)).rows[0].c;
    report.public_super_admins = (await client.query(`SELECT count(*)::int AS c FROM public.super_admins`)).rows[0].c;
    report.auth_users = (await client.query(`SELECT count(*)::int AS c FROM auth.users`)).rows[0].c;
    report.notification_outbox = (await client.query(`SELECT count(*)::int AS c FROM public.notification_outbox`)).rows[0].c;
    report.system_config = (await client.query(`SELECT count(*)::int AS c FROM public.system_config`)).rows[0].c;

    if (report.public_users !== 5) report.errors.push('users count');
    if (report.private_admin_users !== 0) report.errors.push('private.admin_users');
    if (report.public_super_admins !== 0) report.errors.push('super_admins');
    if (report.auth_users !== 0) report.errors.push('auth.users');
    if (report.notification_outbox !== 6) report.errors.push('notification_outbox');
    if (report.system_config !== 2) report.errors.push('system_config');

    const adminHits = await client.query(
      `SELECT count(*)::int AS c FROM public.users
       WHERE id = $1 OR lower(email) = $2 OR right(regexp_replace(mobile, '\\D', '', 'g'), 10) = $3`,
      [ADMIN.id, ADMIN.email, ADMIN.mobileDigits],
    );
    report.admin_residue_users = adminHits.rows[0].c;
    if (adminHits.rows[0].c > 0) report.errors.push('admin residue in users');

    report.triggers = (
      await client.query(`
        SELECT tgname, tgenabled FROM pg_trigger
        WHERE tgrelid = 'public.users'::regclass
          AND tgname IN ('users_protect_system_admin', 'users_protect_system_admin_delete')
        ORDER BY tgname
      `)
    ).rows;
    if (report.triggers.some((t) => t.tgenabled !== 'O')) report.errors.push('triggers not O');

    report.login_lookup = [];
    report.demo_users = [];
    for (const d of DEMOS) {
      const u = await client.query(
        `SELECT id, role, mobile, profile_id, verified, is_system_admin, email FROM public.users WHERE id = $1`,
        [d.uid],
      );
      report.demo_users.push(u.rows[0]);
      if (!u.rows[0] || u.rows[0].role !== d.role) report.errors.push(`role ${d.uid}`);
      if (u.rows[0]?.is_system_admin) report.errors.push(`admin flag ${d.uid}`);
      if (u.rows[0]?.email === ADMIN.email) report.errors.push(`admin email on demo ${d.uid}`);
      const lk = await loginLookup(client, d.digits);
      report.login_lookup.push({ digits: d.digits, expected: d, ...lk });
      if (!lk.found || lk.uid !== d.uid || lk.role !== d.role) report.errors.push(`lookup ${d.digits}`);
      if (d.role === 'doctor') {
        const doc = await client.query(`SELECT verified, doctor_id, owner_uid FROM public.doctors WHERE owner_uid = $1`, [d.uid]);
        if (doc.rows[0]?.verified !== true) report.errors.push('doctor verified');
        if (doc.rows[0]?.doctor_id !== u.rows[0].profile_id) report.errors.push('doctor profile_id');
      }
      if (d.role === 'patient') {
        const p = await client.query(`SELECT patient_id FROM public.patients WHERE owner_uid = $1`, [d.uid]);
        if (p.rows[0]?.patient_id !== u.rows[0].profile_id) report.errors.push('patient profile_id');
      }
      if (d.role === 'medicalStore') {
        const s = await client.query(`SELECT store_id FROM public.medical_stores WHERE owner_uid = $1`, [d.uid]);
        if (s.rows[0]?.store_id !== u.rows[0].profile_id) report.errors.push('store profile_id');
      }
      if (d.role === 'lab') {
        const l = await client.query(`SELECT lab_id FROM public.labs WHERE owner_uid = $1`, [d.uid]);
        if (l.rows[0]?.lab_id !== u.rows[0].profile_id) report.errors.push('lab profile_id');
      }
      if (d.role === 'ambulance') {
        const a = await client.query(`SELECT ambulance_id FROM public.ambulances WHERE auth_uid = $1`, [d.uid]);
        if (a.rows[0]?.ambulance_id !== u.rows[0].profile_id) report.errors.push('ambulance profile_id');
      }
    }

    const fk = await client.query(`SELECT conname FROM pg_constraint WHERE contype = 'f' AND NOT convalidated LIMIT 5`);
    report.invalid_fks = fk.rows.length;
    if (fk.rows.length > 0) report.errors.push('invalid fks');

    report.ok = report.errors.length === 0;
    console.log(JSON.stringify(report, null, 2));
    if (!report.ok) process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});