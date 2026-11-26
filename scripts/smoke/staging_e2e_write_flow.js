#!/usr/bin/env node
'use strict';

/**
 * Tagged write-flow smoke: OTP challenge → doctor profile → appointment → lab order → pharmacy delivery.
 * Each step followed by SELECT proof. Cleanup deletes only rows tagged with smoke_run_id.
 *
 * Usage:
 *   node scripts/smoke/staging_e2e_write_flow.js --target local
 *   node scripts/smoke/staging_e2e_write_flow.js --target staging
 *
 * Local (default): LOCAL_FRESH_DB_URL or postgresql://postgres:test@127.0.0.1:5440/replay_check
 * Staging: APP_ENV=staging + STAGING_SUPABASE_DB_URL (guarded)
 */

const crypto = require('crypto');
const { Pool } = require('pg');
const path = require('path');
const { loadRootEnv } = require('../lib/bootstrap_root_env');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { assertDatabaseGuard } = require('../lib/env_guard');
const { buildPostgrestPayload } = require('../../services/api-gateway/src/jwt_minter');
const { stagingPgSsl } = require('../lib/staging_pg_ssl');

function parseArgs() {
  const targetIdx = process.argv.indexOf('--target');
  const target = targetIdx >= 0 ? String(process.argv[targetIdx + 1] || 'local').toLowerCase() : 'local';
  if (!['local', 'staging'].includes(target)) {
    console.error('Usage: --target local|staging');
    process.exit(2);
  }
  return { target };
}

function localDbUrl() {
  return (
    getEnv('LOCAL_FRESH_DB_URL') ||
    getEnv('REPLAY_DB_URL') ||
    'postgresql://postgres:test@127.0.0.1:5440/replay_check'
  );
}

function serviceClaims() {
  return JSON.stringify(buildPostgrestPayload({ role: 'service_role' }));
}

function patientClaims(uid) {
  return JSON.stringify(
    buildPostgrestPayload({
      role: 'authenticated',
      sub: uid,
      appRole: 'patient',
      verified: true,
    }),
  );
}

function assertStepProof(res, label) {
  if (!res || res.rowCount < 1) {
    console.error(`\nFAIL: step "${label}" proof rows=${res?.rowCount ?? 0} (expected >= 1)`);
    process.exitCode = 1;
    throw new Error(`smoke step failed: ${label}`);
  }
}

async function proofSelect(client, label, sql, params) {
  const res = await client.query(sql, params);
  console.log(`\n=== PROOF: ${label} (rows=${res.rowCount}) ===`);
  for (const row of res.rows.slice(0, 3)) {
    console.log(JSON.stringify(row));
  }
  assertStepProof(res, label);
  return res;
}

async function ensureSmokeLab(client, tag) {
  const labs = await client.query(`SELECT lab_id FROM public.labs ORDER BY lab_id LIMIT 1`);
  if (labs.rowCount > 0) {
    return labs.rows[0].lab_id;
  }
  const labId = `${tag}_lab`;
  await client.query(
    `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
     VALUES ($1::varchar, $1::varchar, 'lab', $1::varchar, 'Smoke Lab', 'lab@smoke', '+919999999005', true)
     ON CONFLICT (id) DO NOTHING`,
    [labId],
  );
  await client.query(
    `INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified)
     VALUES ($1::varchar, $1::varchar, 'Smoke Lab', 'LIC-SMOKE', '+919999999005', 'lab@smoke', true)
     ON CONFLICT (lab_id) DO NOTHING`,
    [labId],
  );
  return labId;
}

async function asServiceRole(client, fn) {
  await client.query('BEGIN');
  await client.query('SET LOCAL ROLE service_role');
  await client.query(`SELECT set_config('request.jwt.claims', $1, true)`, [serviceClaims()]);
  try {
    const out = await fn();
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    await client.query('RESET ROLE').catch(() => {});
  }
}

async function asPatient(client, uid, fn) {
  await client.query('BEGIN');
  await client.query('SET LOCAL ROLE authenticated');
  await client.query(`SELECT set_config('request.jwt.claims', $1, true)`, [patientClaims(uid)]);
  try {
    const out = await fn();
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    await client.query('RESET ROLE').catch(() => {});
  }
}

async function cleanupTagged(client, tag) {
  const like = `${tag}%`;
  const stmts = [
    ['pharmacy_deliveries', `DELETE FROM public.pharmacy_deliveries WHERE delivery_id LIKE $1 OR prescription_id LIKE $1`],
    ['prescriptions', `DELETE FROM public.prescriptions WHERE prescription_id LIKE $1`],
    ['lab_orders', `DELETE FROM public.lab_orders WHERE order_id LIKE $1`],
    ['appointments', `DELETE FROM public.appointments WHERE appointment_id LIKE $1`],
    ['patients', `DELETE FROM public.patients WHERE patient_id LIKE $1`],
    ['doctors', `DELETE FROM public.doctors WHERE doctor_id LIKE $1`],
    ['users', `DELETE FROM public.users WHERE id LIKE $1 OR firebase_uid LIKE $1`],
    ['otp_challenges', `DELETE FROM public.otp_challenges WHERE challenge_id LIKE $1`],
  ];
  for (const [name, sql] of stmts) {
    const r = await client.query(sql, [like]);
    if (r.rowCount > 0) {
      console.log(`cleanup ${name}: ${r.rowCount} row(s)`);
    }
  }
}

async function main() {
  loadRootEnv({ startDir: path.join(__dirname, '..') });
  const { target } = parseArgs();
  const smokeRunId = `smoke_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
  const tag = smokeRunId;

  const ids = {
    doctorUid: `${tag}_doc`,
    patientUid: `${tag}_pat`,
    doctorId: `${tag}_doctor`,
    patientId: `${tag}_patient`,
    otpId: `${tag}_otp`,
    apptId: `${tag}_appt`,
    rxId: `${tag}_rx`,
    labOrderId: `${tag}_labord`,
    deliveryId: `${tag}_del`,
    storeId: 'authz_store_a',
  };

  let dbUrl;
  let ssl;
  if (target === 'staging') {
    const appEnv = String(getEnv('APP_ENV') || 'staging').toLowerCase();
    if (appEnv === 'production') {
      console.error('Refusing: APP_ENV=production');
      process.exit(2);
    }
    dbUrl =
      getEnv('STAGING_SUPABASE_DB_URL') ||
      getEnv('SUPABASE_DB_URL') ||
      getEnv('DATABASE_URL');
    if (!dbUrl) {
      console.error('Missing STAGING_SUPABASE_DB_URL');
      process.exit(2);
    }
    assertDatabaseGuard({ targetKind: 'staging', operationName: 'staging_e2e_write_flow' });
    ssl = stagingPgSsl();
  } else {
    dbUrl = localDbUrl();
    ssl = false;
  }

  console.log(`Write-flow smoke target=${target} smoke_run_id=${smokeRunId}`);
  console.log(`DB: ${maskConnectionString(dbUrl)}`);

  const pool = new Pool({
    connectionString: dbUrl,
    ssl,
    max: 3,
    connectionTimeoutMillis: 20000,
  });
  const client = await pool.connect();

  try {
    if (target === 'local') {
      const store = await client.query(`SELECT 1 FROM public.medical_stores WHERE store_id = $1`, [ids.storeId]);
      if (store.rowCount === 0) {
        await client.query(
          `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
           VALUES ($1::varchar, $1::varchar, 'medicalStore', $1::varchar, 'Smoke Store', 'store@smoke', '+919999999004', true)
           ON CONFLICT (id) DO NOTHING`,
          [ids.storeId],
        );
        await client.query(
          `INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified)
           VALUES ($1::varchar, $1::varchar, 'Smoke Store', 'Owner', 'DL-SMOKE', '+919999999004', 'store@smoke', true)
           ON CONFLICT (store_id) DO NOTHING`,
          [ids.storeId],
        );
      }
      await ensureSmokeLab(client, tag);
    }

    // 1) OTP challenge (service_role-only RLS; postgres maintainer bypass for smoke)
    await client.query(
      `INSERT INTO public.otp_challenges (
         challenge_id, otp_hash, mobile, role, expires_at, is_demo
       ) VALUES ($1::varchar, 'hash_smoke', '+919999999001', 'doctor', NOW() + interval '10 minutes', true)`,
      [ids.otpId],
    );
    await proofSelect(
      client,
      'otp_challenges',
      `SELECT challenge_id, mobile, role, is_demo FROM public.otp_challenges WHERE challenge_id = $1`,
      [ids.otpId],
    );

    // 2) Doctor + patient profiles (postgres superuser inserts)
    await client.query(
      `INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified)
       VALUES ($1::varchar, $1::varchar, 'doctor', $1::varchar, 'Smoke Doc', $2::varchar, '+919999999002', true),
              ($3::varchar, $3::varchar, 'patient', $3::varchar, 'Smoke Pat', $4::varchar, '+919999999003', true)
       ON CONFLICT (id) DO NOTHING`,
      [ids.doctorUid, `${tag}@doc.smoke`, ids.patientUid, `${tag}@pat.smoke`],
    );
    await client.query(
      `INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated)
       VALUES ($1::varchar, $2::varchar, 'Smoke Doc', $3::varchar, '+919999999002', 'General', 'MBBS', true, false)
       ON CONFLICT (doctor_id) DO NOTHING`,
      [ids.doctorId, ids.doctorUid, `${tag}@doc.smoke`],
    );
    await client.query(
      `INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
       VALUES ($1::varchar, $2::varchar, 'Smoke Pat', '+919999999003')
       ON CONFLICT (patient_id) DO NOTHING`,
      [ids.patientId, ids.patientUid],
    );
    await proofSelect(
      client,
      'doctor profile',
      `SELECT doctor_id, owner_uid, verified FROM public.doctors WHERE doctor_id = $1`,
      [ids.doctorId],
    );

    // 3) Appointment (prefer RPC; fallback INSERT when replay DB lacks sync_origin column)
    try {
      await asPatient(client, ids.patientUid, async () => {
        await client.query(
          `SELECT public.book_appointment_atomic(
            $1::varchar, $2::varchar, 'Smoke Doc', 'General', 'Smoke Pat', 30, 'Male',
            (CURRENT_TIMESTAMP + interval '4 days'), '11:00 AM', 'newVisit',
            NULL::int, 'Clinic', 'Addr', 'patient_supabase', $3::varchar
          )`,
          [ids.apptId, ids.doctorId, ids.patientId],
        );
      });
    } catch (err) {
      const msg = err.message || String(err);
      if (!/sync_origin|function digest/i.test(msg)) throw err;
      console.warn('book_appointment_atomic unavailable on this DB shape; using maintainer INSERT fallback.');
      await client.query(
        `INSERT INTO public.appointments (
           appointment_id, doctor_id, patient_id, doctor_name, specialization,
           patient_name, patient_age, patient_gender, date_time, slot_label,
           visit_type, patient_status, doctor_status
         ) VALUES (
           $1::varchar, $2::varchar, $3::varchar, 'Smoke Doc', 'General',
           'Smoke Pat', 30, 'Male', (CURRENT_TIMESTAMP + interval '4 days'), '11:00 AM',
           'newVisit', 'confirmed', 'confirmed'
         ) ON CONFLICT (appointment_id) DO NOTHING`,
        [ids.apptId, ids.doctorId, ids.patientId],
      );
    }
    await proofSelect(
      client,
      'appointment',
      `SELECT appointment_id, doctor_id, patient_id, patient_status, doctor_status
       FROM public.appointments WHERE appointment_id = $1`,
      [ids.apptId],
    );

    // 4) Lab order (requires at least one lab row — seed on staging when empty)
    const smokeLabId = await ensureSmokeLab(client, tag);
    const labIns = await client.query(
      `INSERT INTO public.lab_orders (
         order_id, lab_id, doctor_id, patient_id, doctor_name, patient_name, patient_age, test_ids, test_names, status
       ) VALUES ($1::varchar, $2::varchar, $3::varchar, $4::varchar, 'Smoke Doc', 'Smoke Pat', 30, ARRAY['t1'], ARRAY['CBC'], 'ordered')
       ON CONFLICT (order_id) DO NOTHING
       RETURNING order_id`,
      [ids.labOrderId, smokeLabId, ids.doctorId, ids.patientId],
    );
    if (labIns.rowCount < 1) {
      console.error(`\nFAIL: lab_orders INSERT affected ${labIns.rowCount} rows (lab_id=${smokeLabId})`);
      process.exitCode = 1;
      throw new Error('lab_orders insert failed');
    }
    await proofSelect(
      client,
      'lab_order',
      `SELECT order_id, doctor_id, patient_id, status FROM public.lab_orders WHERE order_id = $1`,
      [ids.labOrderId],
    );

    // 5) Pharmacy delivery (requires prescription)
    await client.query(
      `INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age)
       VALUES ($1, $2, $3, $4, 'Smoke Pat', 30)
       ON CONFLICT (prescription_id) DO NOTHING`,
      [ids.rxId, ids.doctorId, ids.patientId, ids.apptId],
    );

    if (target === 'local') {
      await client.query(
        `INSERT INTO public.pharmacy_deliveries (
           delivery_id, prescription_id, doctor_id, store_id, patient_id,
           doctor_name, store_name, patient_name, status
         ) VALUES ($1, $2, $3, $4, $5, 'Smoke Doc', 'Store A', 'Smoke Pat', 'sent')
         ON CONFLICT (delivery_id) DO NOTHING`,
        [ids.deliveryId, ids.rxId, ids.doctorId, ids.storeId, ids.patientId],
      );
    } else {
      await client.query(
        `INSERT INTO public.pharmacy_deliveries (
           delivery_id, prescription_id, doctor_id, store_id, patient_id,
           doctor_name, store_name, patient_name, status
         )
         SELECT $1, $2, $3, ms.store_id, $4, 'Smoke Doc', ms.store_name, 'Smoke Pat', 'sent'
         FROM public.medical_stores ms
         ORDER BY ms.updated_at DESC NULLS LAST
         LIMIT 1`,
        [ids.deliveryId, ids.rxId, ids.doctorId, ids.patientId],
      );
    }
    await proofSelect(
      client,
      'pharmacy_delivery',
      `SELECT delivery_id, prescription_id, doctor_id, patient_id, status
       FROM public.pharmacy_deliveries WHERE delivery_id = $1`,
      [ids.deliveryId],
    );

    if (process.exitCode && process.exitCode !== 0) {
      console.error(`\nABORT: write-flow incomplete smoke_run_id=${smokeRunId}`);
    } else {
      console.log(`\nOK: write-flow complete smoke_run_id=${smokeRunId}`);
    }
  } finally {
    try {
      await cleanupTagged(client, tag);
      console.log('OK: tagged cleanup finished');
    } catch (e) {
      console.error('Cleanup error:', e.message || e);
    }
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(process.exitCode && process.exitCode !== 0 ? process.exitCode : 1);
});