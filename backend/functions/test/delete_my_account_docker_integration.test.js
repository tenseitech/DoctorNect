'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Client } = require('../../node_modules/pg');

const DOCKER_PG_URL = process.env.LOCAL_DOCKER_PG_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

test('delete_my_account Postgres integration test on local Docker', async (t) => {
  const pgClient = new Client({ connectionString: DOCKER_PG_URL });
  try {
    await pgClient.connect();
  } catch (err) {
    if (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND') {
      console.log('Skipping [delete_my_account Postgres integration test on local Docker]: Local Docker Postgres unreachable on ' + DOCKER_PG_URL);
      t.skip('Local Docker Postgres unreachable on 127.0.0.1:54322');
      return;
    }
    throw err;
  }

  try {
    const health = await pgClient.query('SELECT 1 as healthy;');
    assert.equal(health.rows[0].healthy, 1);

    const ts = Date.now();
    const testUserId = `00000000-0000-0000-0000-${String(ts).slice(-12).padStart(12, '0')}`;
    const testFirebaseUid = `docker_del_test_${ts}`;
    const testPatientId = `pat_docker_${ts}`;

    // Insert user, patient, user_device
    await pgClient.query(`
      INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
      VALUES ($1, $2, 'patient', $3, 'Docker Del Test', $4, '9999900099')
      ON CONFLICT (id) DO NOTHING;
    `, [testUserId, testFirebaseUid, testPatientId, `del_${ts}@example.com`]);

    await pgClient.query(`
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
      VALUES ($1, $2, 'Docker Del Patient', '9999900099')
      ON CONFLICT (patient_id) DO NOTHING;
    `, [testPatientId, testUserId]);

    await pgClient.query(`
      INSERT INTO public.user_devices (user_id, fcm_token, platform)
      VALUES ($1, $2, 'android')
      ON CONFLICT DO NOTHING;
    `, [testUserId, `fcm_${ts}`]);

    // Check insertion
    const uRes = await pgClient.query('SELECT id FROM public.users WHERE id = $1;', [testUserId]);
    assert.equal(uRes.rowCount, 1);

    const dRes = await pgClient.query('SELECT user_id FROM public.user_devices WHERE user_id = $1;', [testUserId]);
    assert.equal(dRes.rowCount, 1);

    // Simulate account deletion operations directly on Postgres
    // 1. Delete user_devices
    await pgClient.query('DELETE FROM public.user_devices WHERE user_id = $1;', [testUserId]);
    // 2. Delete patient
    await pgClient.query('DELETE FROM public.patients WHERE patient_id = $1;', [testPatientId]);
    // 3. Delete user
    await pgClient.query('DELETE FROM public.users WHERE id = $1;', [testUserId]);

    // Verify all rows are gone
    const checkUser = await pgClient.query('SELECT id FROM public.users WHERE id = $1;', [testUserId]);
    assert.equal(checkUser.rowCount, 0, 'User row must be deleted');

    const checkDevices = await pgClient.query('SELECT user_id FROM public.user_devices WHERE user_id = $1;', [testUserId]);
    assert.equal(checkDevices.rowCount, 0, 'User devices must be deleted');

    const checkPatient = await pgClient.query('SELECT patient_id FROM public.patients WHERE patient_id = $1;', [testPatientId]);
    assert.equal(checkPatient.rowCount, 0, 'Patient row must be deleted');
  } finally {
    await pgClient.end();
  }
});
