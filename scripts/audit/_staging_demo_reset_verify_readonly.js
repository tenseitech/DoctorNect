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

const ADMIN_ID = 'wfT7vh7pakYR64scZkXrFcOefDZ2';

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
  assertDatabaseGuard({ targetKind: 'staging', operationName: 'staging_demo_reset_verify' });
  const dbUrl = getEnv('STAGING_SUPABASE_DB_URL');
  const pool = new Pool({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  const client = await pool.connect();
  try {
    const report = { connection: maskConnectionString(dbUrl), ok: true, errors: [] };
    const uc = await client.query(`SELECT count(*)::int AS c FROM public.users`);
    report.public_users_count = uc.rows[0].c;
    if (uc.rows[0].c !== 6) {
      report.ok = false;
      report.errors.push(`users count expected 6 got ${uc.rows[0].c}`);
    }

    const admin = await client.query(
      `SELECT id, email, is_system_admin, role, mobile, profile_completed, status FROM public.users WHERE id = $1`,
      [ADMIN_ID],
    );
    report.super_admin = admin.rows[0];
    if (!admin.rows[0] || admin.rows[0].email !== 'admin@doctornect.com' || admin.rows[0].is_system_admin !== true) {
      report.ok = false;
      report.errors.push('super_admin row mismatch');
    }

    const orphanD = await client.query(
      `SELECT count(*)::int AS c FROM public.doctors d
       WHERE d.owner_uid IS NULL OR d.owner_uid NOT IN (SELECT id FROM public.users)`,
    );
    const orphanS = await client.query(
      `SELECT count(*)::int AS c FROM public.medical_stores s
       WHERE s.owner_uid IS NULL OR s.owner_uid NOT IN (SELECT id FROM public.users)`,
    );
    const orphanL = await client.query(
      `SELECT count(*)::int AS c FROM public.labs l
       WHERE l.owner_uid IS NULL OR l.owner_uid NOT IN (SELECT id FROM public.users)`,
    );
    report.orphans = { doctors: orphanD.rows[0].c, medical_stores: orphanS.rows[0].c, labs: orphanL.rows[0].c };
    if (orphanD.rows[0].c || orphanS.rows[0].c || orphanL.rows[0].c) {
      report.ok = false;
      report.errors.push('orphan profile rows remain');
    }

    const outbox = await client.query(`SELECT count(*)::int AS c FROM public.notification_outbox`);
    report.notification_outbox = outbox.rows[0].c;
    if (outbox.rows[0].c !== 6) {
      report.ok = false;
      report.errors.push(`notification_outbox expected 6 got ${outbox.rows[0].c}`);
    }

    const sc = await client.query(`SELECT count(*)::int AS c FROM public.system_config`);
    report.system_config_rows = sc.rows[0].c;

    report.demo_users = [];
    report.login_lookup = [];
    for (const d of DEMOS) {
      const u = await client.query(
        `SELECT id, role, mobile, profile_id, profile_completed, verified FROM public.users WHERE id = $1`,
        [d.uid],
      );
      const row = u.rows[0];
      report.demo_users.push(row);
      if (!row || row.role !== d.role) {
        report.ok = false;
        report.errors.push(`demo user ${d.uid} role mismatch`);
      }
      const lk = await loginLookup(client, d.digits);
      report.login_lookup.push({ digits: d.digits, expected: d, ...lk });
      if (!lk.found || lk.uid !== d.uid || lk.role !== d.role) {
        report.ok = false;
        report.errors.push(`login lookup failed ${d.digits}`);
      }
      if (d.role === 'doctor') {
        const doc = await client.query(
          `SELECT doctor_id, owner_uid, verified FROM public.doctors WHERE owner_uid = $1`,
          [d.uid],
        );
        report.doctor_verified = doc.rows[0]?.verified;
        if (doc.rows[0]?.verified !== true) {
          report.ok = false;
          report.errors.push('doctor not verified');
        }
        if (doc.rows[0]?.doctor_id !== row.profile_id) {
          report.ok = false;
          report.errors.push('doctor profile_id mismatch');
        }
      }
      if (d.role === 'patient') {
        const p = await client.query(`SELECT patient_id, owner_uid FROM public.patients WHERE owner_uid = $1`, [d.uid]);
        if (p.rows[0]?.patient_id !== row.profile_id) {
          report.ok = false;
          report.errors.push('patient profile_id mismatch');
        }
      }
      if (d.role === 'medicalStore') {
        const s = await client.query(`SELECT store_id, owner_uid FROM public.medical_stores WHERE owner_uid = $1`, [d.uid]);
        if (s.rows[0]?.store_id !== row.profile_id) {
          report.ok = false;
          report.errors.push('store profile_id mismatch');
        }
      }
      if (d.role === 'lab') {
        const l = await client.query(`SELECT lab_id, owner_uid FROM public.labs WHERE owner_uid = $1`, [d.uid]);
        if (l.rows[0]?.lab_id !== row.profile_id) {
          report.ok = false;
          report.errors.push('lab profile_id mismatch');
        }
      }
      if (d.role === 'ambulance') {
        const a = await client.query(`SELECT ambulance_id, auth_uid FROM public.ambulances WHERE auth_uid = $1`, [d.uid]);
        if (a.rows[0]?.ambulance_id !== row.profile_id) {
          report.ok = false;
          report.errors.push('ambulance profile_id mismatch');
        }
      }
    }

    const fk = await client.query(`
      SELECT conname, conrelid::regclass::text AS tbl
      FROM pg_constraint
      WHERE contype = 'f' AND NOT convalidated
      LIMIT 5
    `);
    report.invalid_fks = fk.rows.length;
    if (fk.rows.length > 0) {
      report.ok = false;
      report.errors.push('invalid FK constraints');
    }

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