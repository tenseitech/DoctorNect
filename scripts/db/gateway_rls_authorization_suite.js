'use strict';

/**
 * Production-path authorization matrix: PostgREST role + gateway-minted JWT claims (auth.uid shim)
 * against local Postgres with full migration replay (doctornect_fresh_zero).
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const { Pool } = require('pg');
const { getEnv, maskConnectionString } = require('../lib/env_loader');
const { buildPostgrestPayload } = require('../../services/api-gateway/src/jwt_minter');
const { createGatewayServer } = require('../../services/api-gateway/src/server');
const { base64UrlEncode } = require('../../services/api-gateway/src/jwt_minter');

const DB_NAME = process.env.FRESH_LOCAL_DB_NAME || 'doctornect_fresh_zero';

function freshDbUrl() {
  const explicit = getEnv('LOCAL_FRESH_DB_URL');
  if (explicit) return explicit;
  const base = getEnv('REPLAY_DB_URL') || 'postgresql://postgres:postgres@localhost:5432/postgres';
  const u = new URL(base.replace(/^postgres:\/\//i, 'postgresql://'));
  u.pathname = `/${DB_NAME}`;
  return u.toString();
}

function claimsJson(appRole, uid, verified = true, phone = null) {
  const normalized =
    appRole === 'medicalStore' || appRole === 'pharmacy' ? 'medicalStore' : appRole;
  const tokenRole = 'authenticated';
  return JSON.stringify(
    buildPostgrestPayload({
      role: tokenRole,
      sub: uid,
      appRole: normalized,
      verified,
      phoneNumber: phone,
    }),
  );
}

const MODULES = [
  {
    id: 'doctor',
    mainTable: 'doctors',
    pk: 'doctor_id',
    ownerCol: 'owner_uid',
    appRole: 'doctor',
    peerModuleTable: 'patients',
    peerPk: 'patient_id',
  },
  {
    id: 'patient',
    mainTable: 'patients',
    pk: 'patient_id',
    ownerCol: 'owner_uid',
    appRole: 'patient',
    peerModuleTable: 'doctors',
    peerPk: 'doctor_id',
  },
  {
    id: 'pharmacy',
    mainTable: 'medical_stores',
    pk: 'store_id',
    ownerCol: 'owner_uid',
    appRole: 'medicalStore',
    opsTable: 'pharmacy_deliveries',
    opsPk: 'delivery_id',
    peerModuleTable: 'lab_bookings',
    peerPk: 'booking_id',
  },
  {
    id: 'lab',
    mainTable: 'labs',
    pk: 'lab_id',
    ownerCol: 'owner_uid',
    appRole: 'lab',
    opsTable: 'lab_bookings',
    opsPk: 'booking_id',
    peerModuleTable: 'pharmacy_deliveries',
    peerPk: 'delivery_id',
  },
  {
    id: 'ambulance',
    mainTable: 'ambulances',
    pk: 'ambulance_id',
    ownerCol: 'auth_uid',
    appRole: 'ambulance',
    opsTable: 'ambulance_requests',
    opsPk: 'request_id',
    peerModuleTable: 'lab_bookings',
    peerPk: 'booking_id',
  },
];

const matrix = [];

function pushRow(module, rule, subject, verdict, note = '') {
  matrix.push({ module, rule, subject, verdict, note });
}

async function asRole(client, role, claims, fn) {
  await client.query('SAVEPOINT sp_authz');
  try {
    await client.query(`SET LOCAL ROLE ${role}`);
    if (claims) {
      await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);
    } else {
      await client.query(`SELECT set_config('request.jwt.claims', '', true);`);
      await client.query(`SELECT set_config('request.jwt.claim.sub', '', true);`);
    }
    return await fn();
  } catch (err) {
    await client.query('ROLLBACK TO SAVEPOINT sp_authz');
    throw err;
  } finally {
    await client.query('RESET ROLE').catch(() => {});
    await client.query('ROLLBACK TO SAVEPOINT sp_authz').catch(() => {});
  }
}

async function expectSuccess(client, role, claims, sql) {
  await client.query('SAVEPOINT sp_expect_ok');
  try {
    await client.query(`SET LOCAL ROLE ${role}`);
    if (claims) {
      await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);
    }
    const res = await client.query(sql);
    const ok = (res.rowCount ?? res.rows?.length ?? 0) > 0;
    await client.query('ROLLBACK TO SAVEPOINT sp_expect_ok');
    await client.query('RESET ROLE');
    return ok;
  } catch (err) {
    await client.query('ROLLBACK TO SAVEPOINT sp_expect_ok').catch(() => {});
    await client.query('RESET ROLE').catch(() => {});
    return false;
  }
}

async function expectDenied(client, role, claims, sql) {
  await client.query('SAVEPOINT sp_expect_denied');
  try {
    await client.query(`SET LOCAL ROLE ${role}`);
    if (claims) {
      await client.query(`SELECT set_config('request.jwt.claims', $1, true);`, [claims]);
    } else {
      await client.query(`SELECT set_config('request.jwt.claims', '', true);`);
    }
    try {
      const res = await client.query(sql);
      const n = res.rowCount ?? res.rows?.length ?? 0;
      await client.query('ROLLBACK TO SAVEPOINT sp_expect_denied');
      await client.query('RESET ROLE');
      return n === 0;
    } catch (err) {
      await client.query('ROLLBACK TO SAVEPOINT sp_expect_denied');
      await client.query('RESET ROLE');
      return err.code === '42501' || err.code === 'P0001';
    }
  } catch (err) {
    await client.query('ROLLBACK TO SAVEPOINT sp_expect_denied').catch(() => {});
    await client.query('RESET ROLE').catch(() => {});
    return err.code === '42501';
  }
}

async function seedFixtures(client) {
  const ids = {
    pA: 'authz_pat_a',
    pB: 'authz_pat_b',
    docA: 'authz_doc_a',
    docB: 'authz_doc_b',
    storeA: 'authz_store_a',
    storeB: 'authz_store_b',
    labA: 'authz_lab_a',
    labB: 'authz_lab_b',
    ambA: 'authz_amb_a',
    ambB: 'authz_amb_b',
  };
  await client.query(`
    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, verified) VALUES
      ('${ids.pA}', '${ids.pA}', 'patient', '${ids.pA}', 'Pat A', 'pa@authz.test', '+910000000001', true),
      ('${ids.pB}', '${ids.pB}', 'patient', '${ids.pB}', 'Pat B', 'pb@authz.test', '+910000000002', true),
      ('${ids.docA}', '${ids.docA}', 'doctor', '${ids.docA}', 'Doc A', 'da@authz.test', '+910000000003', true),
      ('${ids.docB}', '${ids.docB}', 'doctor', '${ids.docB}', 'Doc B', 'db@authz.test', '+910000000004', true),
      ('${ids.storeA}', '${ids.storeA}', 'medicalStore', '${ids.storeA}', 'Store A', 'sa@authz.test', '+910000000005', true),
      ('${ids.storeB}', '${ids.storeB}', 'medicalStore', '${ids.storeB}', 'Store B', 'sb@authz.test', '+910000000006', true),
      ('${ids.labA}', '${ids.labA}', 'lab', '${ids.labA}', 'Lab A', 'la@authz.test', '+910000000007', true),
      ('${ids.labB}', '${ids.labB}', 'lab', '${ids.labB}', 'Lab B', 'lb@authz.test', '+910000000008', true),
      ('${ids.ambA}', '${ids.ambA}', 'ambulance', '${ids.ambA}', 'Amb A', 'aa@authz.test', '+910000000009', true),
      ('${ids.ambB}', '${ids.ambB}', 'ambulance', '${ids.ambB}', 'Amb B', 'ab@authz.test', '+910000000010', true)
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.patients (patient_id, owner_uid, name, mobile) VALUES
      ('${ids.pA}', '${ids.pA}', 'Pat A', '+910000000001'),
      ('${ids.pB}', '${ids.pB}', 'Pat B', '+910000000002')
    ON CONFLICT (patient_id) DO NOTHING;
    INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated) VALUES
      ('${ids.docA}', '${ids.docA}', 'Doc A', 'da@authz.test', '+910000000003', 'Gen', 'MBBS', true, false),
      ('${ids.docB}', '${ids.docB}', 'Doc B', 'db@authz.test', '+910000000004', 'Cardio', 'MD', true, false)
    ON CONFLICT (doctor_id) DO NOTHING;
    INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified) VALUES
      ('${ids.storeA}', '${ids.storeA}', 'Store A', 'Own A', 'DL-A', '+910000000005', 'sa@authz.test', true),
      ('${ids.storeB}', '${ids.storeB}', 'Store B', 'Own B', 'DL-B', '+910000000006', 'sb@authz.test', true)
    ON CONFLICT (store_id) DO NOTHING;
    INSERT INTO public.labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified) VALUES
      ('${ids.labA}', '${ids.labA}', 'Lab A', 'LIC-A', '+910000000007', 'la@authz.test', true),
      ('${ids.labB}', '${ids.labB}', 'Lab B', 'LIC-B', '+910000000008', 'lb@authz.test', true)
    ON CONFLICT (lab_id) DO NOTHING;
    INSERT INTO public.ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified, is_available) VALUES
      ('${ids.ambA}', '${ids.ambA}', 'Svc A', 'Drv A', '+910000000009', 'VEH-A', 'bls', 'Delhi', true, true),
      ('${ids.ambB}', '${ids.ambB}', 'Svc B', 'Drv B', '+910000000010', 'VEH-B', 'icu', 'Delhi', true, true)
    ON CONFLICT (ambulance_id) DO NOTHING;
    INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status) VALUES
      ('authz_appt_a', '${ids.docA}', '${ids.pA}', 'Doc A', 'Gen', 'Pat A', 30, 'Male', now(), '10:00', 'newVisit', 'confirmed', 'confirmed')
    ON CONFLICT (appointment_id) DO NOTHING;
    INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age) VALUES
      ('authz_rx_a', '${ids.docA}', '${ids.pA}', 'authz_appt_a', 'Pat A', 30)
    ON CONFLICT (prescription_id) DO NOTHING;
    INSERT INTO public.pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status) VALUES
      ('authz_del_a', 'authz_rx_a', '${ids.docA}', '${ids.storeA}', '${ids.pA}', 'Doc A', 'Store A', 'Pat A', 'sent')
    ON CONFLICT (delivery_id) DO NOTHING;
    INSERT INTO public.pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status) VALUES
      ('authz_del_b', 'authz_rx_a', '${ids.docA}', '${ids.storeB}', '${ids.pB}', 'Doc A', 'Store B', 'Pat B', 'sent')
    ON CONFLICT (delivery_id) DO NOTHING;
    INSERT INTO public.lab_bookings (booking_id, lab_id, patient_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status) VALUES
      ('authz_lb_a', '${ids.labA}', '${ids.pA}', 'Pat A', 30, 't1', 'CBC', ARRAY['CBC'], 'labVisit', now(), '09:00', 'confirmed'),
      ('authz_lb_b', '${ids.labB}', '${ids.pB}', 'Pat B', 30, 't2', 'CBC', ARRAY['CBC'], 'labVisit', now(), '10:00', 'confirmed')
    ON CONFLICT (booking_id) DO NOTHING;
    INSERT INTO public.ambulance_broadcasts (broadcast_id, patient_id, patient_name, contact_phone, pickup_location, drop_location, status, accepted_driver_id) VALUES
      ('authz_bc_a', '${ids.pA}', 'Pat A', '+910000000001', 'A Pickup', 'A Drop', 'accepted', '${ids.ambA}'),
      ('authz_bc_b', '${ids.pB}', 'Pat B', '+910000000002', 'B Pickup', 'B Drop', 'accepted', '${ids.ambB}')
    ON CONFLICT (broadcast_id) DO NOTHING;
    INSERT INTO public.ambulance_requests (request_id, broadcast_id, driver_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status) VALUES
      ('authz_ambreq_a', 'authz_bc_a', '${ids.ambA}', '${ids.pA}', 'Pat A', 'A Pickup', 'A Drop', '+910000000001', 'accepted'),
      ('authz_ambreq_b', 'authz_bc_b', '${ids.ambB}', '${ids.pB}', 'Pat B', 'B Pickup', 'B Drop', '+910000000002', 'accepted')
    ON CONFLICT (request_id) DO NOTHING;
  `);
  return ids;
}

async function runSqlMatrix(client, ids) {
  const byModule = Object.fromEntries(MODULES.map((m) => [m.id, m]));

  const pkOf = {
    doctor: { a: ids.docA, b: ids.docB, uA: ids.docA, uB: ids.docB },
    patient: { a: ids.pA, b: ids.pB, uA: ids.pA, uB: ids.pB },
    pharmacy: { a: ids.storeA, b: ids.storeB, uA: ids.storeA, uB: ids.storeB },
    lab: { a: ids.labA, b: ids.labB, uA: ids.labA, uB: ids.labB },
    ambulance: { a: ids.ambA, b: ids.ambB, uA: ids.ambA, uB: ids.ambB },
  };

  const peerPkCol = {
    patients: 'patient_id',
    doctors: 'doctor_id',
    medical_stores: 'store_id',
    labs: 'lab_id',
    ambulances: 'ambulance_id',
    lab_bookings: 'booking_id',
    pharmacy_deliveries: 'delivery_id',
    ambulance_requests: 'request_id',
    ambulance_broadcasts: 'broadcast_id',
  };

  for (const mod of MODULES) {
    const { a: pkA, b: pkB, uA: userA } = pkOf[mod.id];
    const cA = claimsJson(mod.appRole, userA, true, '+910000000099');

    // (1) own read + update
    const readOwn = await expectSuccess(
      client,
      'authenticated',
      cA,
      `SELECT 1 FROM public.${mod.mainTable} WHERE ${mod.pk} = '${pkA}' LIMIT 1;`,
    );
    pushRow(mod.id, '(1) own read/update', mod.mainTable, readOwn ? 'PASS' : 'FAIL', readOwn ? '' : 'SELECT own row');

    const updateOwn = await expectSuccess(
      client,
      'authenticated',
      cA,
      `UPDATE public.${mod.mainTable} SET updated_at = now() WHERE ${mod.pk} = '${pkA}' AND ${mod.ownerCol} = '${userA}';`,
    );
    pushRow(mod.id, '(1) own read/update', `${mod.mainTable} UPDATE`, updateOwn ? 'PASS' : 'FAIL', updateOwn ? '' : 'UPDATE own row');

    // (2) cross-user read / update / delete (operational rows for provider modules; profile rows for doctor/patient)
    const crossSubject = mod.opsTable || mod.mainTable;
    const crossPkCol = mod.opsPk || mod.pk;
    const crossPkB =
      mod.id === 'pharmacy'
        ? 'authz_del_b'
        : mod.id === 'lab'
          ? 'authz_lb_b'
          : mod.id === 'ambulance'
            ? 'authz_ambreq_b'
            : pkB;

    const crossRead = await expectDenied(
      client,
      'authenticated',
      cA,
      `SELECT * FROM public.${crossSubject} WHERE ${crossPkCol} = '${crossPkB}';`,
    );
    pushRow(mod.id, '(2) cross-user deny', `${crossSubject} SELECT B`, crossRead ? 'PASS' : 'FAIL');

    const crossUpdate = await expectDenied(
      client,
      'authenticated',
      cA,
      `UPDATE public.${crossSubject} SET updated_at = now() WHERE ${crossPkCol} = '${crossPkB}';`,
    );
    pushRow(mod.id, '(2) cross-user deny', `${crossSubject} UPDATE B`, crossUpdate ? 'PASS' : 'FAIL');

    const crossDelete = await expectDenied(
      client,
      'authenticated',
      cA,
      `DELETE FROM public.${crossSubject} WHERE ${crossPkCol} = '${crossPkB}';`,
    );
    pushRow(mod.id, '(2) cross-user deny', `${crossSubject} DELETE B`, crossDelete ? 'PASS' : 'FAIL');

    // (3) wrong module: user A of this module accessing peer module owned row
    const peer = mod.peerModuleTable;
    const peerPkVal =
      mod.id === 'doctor'
        ? ids.pB
        : mod.id === 'patient'
          ? ids.docB
          : mod.id === 'pharmacy'
            ? 'authz_lb_b'
            : mod.id === 'lab'
              ? 'authz_del_b'
              : 'authz_lb_b';
    const peerCol = peerPkCol[peer] || mod.opsPk || 'id';
    const peerDenied = await expectDenied(
      client,
      'authenticated',
      cA,
      `SELECT * FROM public.${peer} WHERE ${peerCol} = '${peerPkVal}';`,
    );
    pushRow(mod.id, '(3) cross-module deny', peer, peerDenied ? 'PASS' : 'FAIL');

    // (4) SQL layer: empty JWT / missing sub
    const noClaims = await expectDenied(
      client,
      'authenticated',
      null,
      `SELECT * FROM public.${mod.mainTable} WHERE ${mod.pk} = '${pkA}' LIMIT 1;`,
    );
    pushRow(mod.id, '(4) no JWT claims (SQL)', mod.mainTable, noClaims ? 'PASS' : 'FAIL');
  }

  // (5) service-role-only table + function
  const patientClaims = claimsJson('patient', ids.pA);
  const outboxDenied = await expectDenied(
    client,
    'authenticated',
    patientClaims,
    `SELECT 1 FROM public.notification_outbox LIMIT 1;`,
  );
  pushRow('all', '(5) service-role only', 'notification_outbox SELECT', outboxDenied ? 'PASS' : 'FAIL');

  const outboxFnDenied = await expectDenied(
    client,
    'authenticated',
    patientClaims,
    `SELECT public.enqueue_notification_outbox();`,
  );
  pushRow('all', '(5) service-role only', 'enqueue_notification_outbox()', outboxFnDenied ? 'PASS' : 'FAIL');

  // (6) admin_audit_logs client insert
  const auditDenied = await expectDenied(
    client,
    'authenticated',
    patientClaims,
    `INSERT INTO public.admin_audit_logs (log_id, admin_uid, admin_email, action, target_type, target_id, details)
     VALUES ('authz_test_log', '${ids.pA}', 'x@test', 'TEST', 'user', '${ids.pA}', '{}');`,
  );
  pushRow('all', '(6) admin_audit INSERT deny', 'admin_audit_logs', auditDenied ? 'PASS' : 'FAIL');

  const medicalTables = [
    { table: 'appointments', pk: 'appointment_id', ownId: 'authz_appt_a', otherId: 'authz_appt_b_other', ownerCol: 'patient_id', uid: ids.pA, role: 'patient' },
    { table: 'prescriptions', pk: 'prescription_id', ownId: 'authz_rx_a', otherId: 'authz_rx_b_other', ownerCol: 'patient_id', uid: ids.pA, role: 'patient' },
    { table: 'health_records', pk: 'record_id', ownId: 'authz_hr_a', otherId: 'authz_hr_b_other', ownerCol: 'patient_id', uid: ids.pA, role: 'patient' },
    { table: 'support_tickets', pk: 'ticket_id', ownId: 'authz_st_a', otherId: 'authz_st_b_other', ownerCol: 'patient_id', uid: ids.pA, role: 'patient' },
  ];

  await client.query('SAVEPOINT authz_medical_seed');
  try {
    await client.query(`
      INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status)
      VALUES ('authz_appt_b_other', '${ids.docB}', '${ids.pB}', 'Doc B', 'Gen', 'Pat B', 25, 'F', now(), '09:00', 'newVisit', 'confirmed', 'confirmed')
      ON CONFLICT (appointment_id) DO NOTHING;
      INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age)
      VALUES ('authz_rx_b_other', '${ids.docB}', '${ids.pB}', 'authz_appt_b_other', 'Pat B', 25)
      ON CONFLICT (prescription_id) DO NOTHING;
      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors)
      VALUES ('authz_hr_a', '${ids.pA}', 'Own HR', 'other', CURRENT_DATE, 'selfUploaded', 'a.pdf', true),
             ('authz_hr_b_other', '${ids.pB}', 'Other HR', 'other', CURRENT_DATE, 'selfUploaded', 'b.pdf', true)
      ON CONFLICT (record_id) DO NOTHING;
      INSERT INTO public.support_tickets (ticket_id, patient_id, issue_type, message, status)
      VALUES ('authz_st_a', '${ids.pA}', 'Technical', 'Help A', 'open'),
             ('authz_st_b_other', '${ids.pB}', 'Technical', 'Help B', 'open')
      ON CONFLICT (ticket_id) DO NOTHING;
    `);
  } catch {
    await client.query('ROLLBACK TO SAVEPOINT authz_medical_seed');
  }

  for (const m of medicalTables) {
    const c = claimsJson(m.role, m.uid);
    const own = await expectSuccess(client, 'authenticated', c, `SELECT 1 FROM public.${m.table} WHERE ${m.pk} = '${m.ownId}' LIMIT 1;`);
    pushRow('medical', '(1) own read', m.table, own ? 'PASS' : 'FAIL');
    const cross = await expectDenied(client, 'authenticated', c, `SELECT * FROM public.${m.table} WHERE ${m.pk} = '${m.otherId}';`);
    pushRow('medical', '(2) cross-user deny', m.table, cross ? 'PASS' : 'FAIL');
  }
}

async function runGatewayAuthChecks() {
  const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const testKid = 'authz-suite-kid';
  const projectId = 'authz-test-project';

  function mintFirebaseToken({ expOffsetSec = 3600, tamper = false } = {}) {
    const now = Math.floor(Date.now() / 1000);
    const header = { alg: 'RS256', kid: testKid, typ: 'JWT' };
    const payload = {
      iss: `https://securetoken.google.com/${projectId}`,
      aud: projectId,
      sub: 'authz_firebase_user',
      app_role: 'patient',
      user_role: 'patient',
      verified: true,
      exp: now + expOffsetSec,
      iat: now - 10,
    };
    const h = base64UrlEncode(JSON.stringify(header));
    const p = base64UrlEncode(JSON.stringify(payload));
    const input = `${h}.${p}`;
    let sig = base64UrlEncode(crypto.sign('RSA-SHA256', Buffer.from(input), keyPair.privateKey));
    if (tamper) sig = (sig[0] === 'A' ? 'B' : 'A') + sig.slice(1);
    return `${input}.${sig}`;
  }

  let mockPort;
  const mockSrv = http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('[]');
  });
  await new Promise((r) => mockSrv.listen(0, '127.0.0.1', r));
  mockPort = mockSrv.address().port;

  const mockJwks = {
    async getPublicKey(kid) {
      if (kid !== testKid) throw new Error('unknown kid');
      return keyPair.publicKey;
    },
  };

  const { server: gateway } = createGatewayServer({
    firebaseProjectId: projectId,
    postgrestUrl: `http://127.0.0.1:${mockPort}`,
    jwksClient: mockJwks,
    postgrestJwtSecret: 'authz-suite-postgrest-secret-32charsxx',
    postgrestJwtAud: 'postgrest',
    serviceRoleKey: 'authz-suite-service-role-key-32chars',
    enforceFirebaseRevocationCheck: false,
    clientAllowedTables: ['patients'],
    allowedMethods: ['GET'],
  });

  await new Promise((r) => gateway.listen(0, '127.0.0.1', r));
  const gwPort = gateway.address().port;

  async function req(path, headers = {}) {
    return new Promise((resolve, reject) => {
      const rq = http.request(
        { hostname: '127.0.0.1', port: gwPort, path, method: 'GET', headers },
        (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            let json = null;
            try {
              json = JSON.parse(Buffer.concat(chunks).toString());
            } catch (_) {}
            resolve({ status: res.statusCode, json });
          });
        },
      );
      rq.on('error', reject);
      rq.end();
    });
  }

  const noToken = await req('/rest/v1/patients?select=patient_id&limit=1');
  pushRow('gateway', '(4) no Firebase token', 'GET /rest/v1/patients', noToken.status === 401 ? 'PASS' : 'FAIL', `HTTP ${noToken.status}`);

  const expired = await req('/rest/v1/patients?select=patient_id&limit=1', {
    authorization: `Bearer ${mintFirebaseToken({ expOffsetSec: -3600 })}`,
  });
  pushRow('gateway', '(4) expired Firebase token', 'GET /rest/v1/patients', expired.status === 401 ? 'PASS' : 'FAIL', `HTTP ${expired.status}`);

  const badSig = await req('/rest/v1/patients?select=patient_id&limit=1', {
    authorization: `Bearer ${mintFirebaseToken({ tamper: true })}`,
  });
  pushRow('gateway', '(4) invalid/revoked-like token', 'GET /rest/v1/patients', badSig.status === 401 ? 'PASS' : 'FAIL', `HTTP ${badSig.status}`);

  await new Promise((r) => gateway.close(r));
  await new Promise((r) => mockSrv.close(r));
}

async function main() {
  const dbUrl = freshDbUrl();
  console.log('Gateway + RLS authorization suite');
  console.log(`Target: ${maskConnectionString(dbUrl)}\n`);

  const pool = new Pool({ connectionString: dbUrl });
  const client = await pool.connect();

  try {
    const before = (await client.query(`SELECT count(*)::int AS n FROM public.users`)).rows[0].n;
    await client.query('BEGIN');
    const ids = await seedFixtures(client);
    await runSqlMatrix(client, ids);
    await client.query('ROLLBACK');
    const after = (await client.query(`SELECT count(*)::int AS n FROM public.users`)).rows[0].n;
    if (after !== before) {
      throw new Error(`Zero-residue violated: users ${before} -> ${after}`);
    }
    console.log('SQL tests rolled back (zero residue).\n');
  } finally {
    client.release();
    await pool.end();
  }

  await runGatewayAuthChecks();

  const fails = matrix.filter((r) => r.verdict === 'FAIL');
  console.log('--- PASS/FAIL matrix ---');
  console.table(matrix);

  const reportPath = path.resolve(__dirname, '../../docs/reports/gateway_rls_authorization_suite.json');
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify({ at: new Date().toISOString(), db: DB_NAME, matrix }, null, 2));
  console.log(`\nWrote ${reportPath}`);
  console.log(`SUMMARY: ${matrix.length - fails.length} PASS / ${fails.length} FAIL`);

  process.exit(fails.length ? 1 : 0);
}

if (require.main === module) {
  main().catch((e) => {
    console.error('Fatal:', e);
    process.exit(1);
  });
}

module.exports = { main, MODULES, seedFixtures };
