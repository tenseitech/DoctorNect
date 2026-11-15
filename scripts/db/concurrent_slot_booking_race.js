#!/usr/bin/env node
'use strict';

/**
 * Concurrent booking race on plain Postgres: N parallel book_appointment_atomic for same slot.
 * Expect exactly 1 success when capacity is 1 (MAX from migration / slot logic).
 *
 *   LOCAL_FRESH_DB_URL=postgresql://postgres:test@127.0.0.1:5440/replay_check node scripts/db/concurrent_slot_booking_race.js
 */

const crypto = require('crypto');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { buildPostgrestPayload } = require('../../services/api-gateway/src/jwt_minter');

const PARALLEL = Number(process.env.SLOT_RACE_PARALLEL || 20);
const DB_URL =
  getEnv('LOCAL_FRESH_DB_URL') ||
  getEnv('REPLAY_DB_URL') ||
  'postgresql://postgres:test@127.0.0.1:5440/replay_check';

function patientClaims(uid) {
  return JSON.stringify(
    buildPostgrestPayload({ role: 'authenticated', sub: uid, appRole: 'patient', verified: true }),
  );
}

async function oneAttempt(pool, { apptId, doctorId, patientUid, patientId, slotDate }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query(`SELECT set_config('request.jwt.claims', $1, true)`, [patientClaims(patientUid)]);
    await client.query(
      `SELECT public.book_appointment_atomic(
        $1::varchar, $2::varchar, 'Race Doc', 'General', $3::varchar, 30, 'Male',
        $4::timestamptz, '10:00 AM', 'newVisit',
        NULL::int, 'Clinic', 'Addr', 'patient_supabase', $5::varchar
      )`,
      [apptId, doctorId, `Pat ${patientUid.slice(-6)}`, slotDate, patientId],
    );
    await client.query('COMMIT');
    return { apptId, ok: true };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    return { apptId, ok: false, code: err.code, msg: err.message?.slice(0, 120) };
  } finally {
    await client.query('RESET ROLE').catch(() => {});
    client.release();
  }
}

async function main() {
  const tag = `race_${Date.now()}`;
  const doctorId = `${tag}_doc`;
  const doctorUid = `${tag}_duid`;
  const slotDate = new Date(Date.now() + 5 * 24 * 3600 * 1000);

  console.log(`Concurrent slot race PARALLEL=${PARALLEL}`);
  console.log(`DB: ${maskConnectionString(DB_URL)}`);

  const pool = new Pool({ connectionString: DB_URL, max: PARALLEL + 2 });
  const client = await pool.connect();

  const patientUids = [];
  try {
    await client.query(
      `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
       VALUES ($1::varchar, $1::varchar, 'doctor', $1::varchar, 'Race Doc', $2, '+919900000001', true)
       ON CONFLICT (id) DO NOTHING`,
      [doctorUid, `${tag}@doc.race`],
    );
    await client.query(
      `INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated)
       VALUES ($1::varchar, $2::varchar, 'Race Doc', $3, '+919900000001', 'Gen', 'MBBS', true, false)
       ON CONFLICT (doctor_id) DO NOTHING`,
      [doctorId, doctorUid, `${tag}@doc.race`],
    );

    for (let i = 0; i < PARALLEL; i++) {
      const uid = `${tag}_p${i}`;
      patientUids.push(uid);
      const mobile = `+91990000${String(1000 + i).slice(-4)}`;
      await client.query(
        `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
         VALUES ($1::varchar, $1::varchar, 'patient', $1::varchar, $2::varchar, $3::varchar, $4::varchar, true)
         ON CONFLICT (id) DO NOTHING`,
        [uid, `Race Pat ${i}`, `${uid}@race`, mobile],
      );
      await client.query(
        `INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
         VALUES ($1::varchar, $2::varchar, $3::varchar, $4::varchar)
         ON CONFLICT (patient_id) DO NOTHING`,
        [uid, uid, `Race Pat ${i}`, mobile],
      );
    }
  } finally {
    client.release();
  }

  const attempts = patientUids.map((uid, i) => ({
    apptId: `${tag}_appt_${i}`,
    doctorId,
    patientUid: uid,
    patientId: uid,
    slotDate,
  }));

  const results = await Promise.all(attempts.map((a) => oneAttempt(pool, a)));
  const wins = results.filter((r) => r.ok);
  const fails = results.filter((r) => !r.ok);

  const verifyClient = await pool.connect();
  let rows = 0;
  try {
    const q = await verifyClient.query(
      `SELECT count(*)::int AS n FROM public.appointments
       WHERE doctor_id = $1 AND date_time = $2`,
      [doctorId, slotDate],
    );
    rows = q.rows[0].n;
  } finally {
    verifyClient.release();
  }

  console.log(`\nResults: success=${wins.length} fail=${fails.length} db_rows_same_slot=${rows}`);
  if (fails.length > 0) {
    const byMsg = {};
    for (const f of fails) {
      const key = f.msg || f.code || 'unknown';
      byMsg[key] = (byMsg[key] || 0) + 1;
    }
    console.log('Failure histogram:', byMsg);
  }

  const cleanup = await pool.connect();
  try {
    await cleanup.query(`DELETE FROM public.appointments WHERE doctor_id = $1`, [doctorId]);
    await cleanup.query(`DELETE FROM public.patients WHERE owner_uid LIKE $1`, [`${tag}%`]);
    await cleanup.query(`DELETE FROM public.doctors WHERE doctor_id = $1`, [doctorId]);
    await cleanup.query(`DELETE FROM public.users WHERE id LIKE $1 OR firebase_uid LIKE $1`, [`${tag}%`]);
  } finally {
    cleanup.release();
    await pool.end();
  }

  const slotMax = Number(process.env.SLOT_RACE_MAX_WINS || 3);
  const pass = wins.length === slotMax && rows === slotMax && wins.length + fails.length === PARALLEL;
  console.log(
    pass
      ? `PASS: ${slotMax} booking(s) won the slot; ${fails.length} rejected (capacity enforced)`
      : `FAIL: expected ${slotMax} success(es) and ${slotMax} row(s), got success=${wins.length} rows=${rows}`,
  );
  process.exit(pass ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});