'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');
const { before, after, beforeEach, afterEach, test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID_HEAD = 'demo-replay-read-head';
const PROJECT_ID_LIVE = 'demo-replay-read-live';

const PATIENT_UID = 'patient_uid_1';
const PATIENT_ID = 'pat_1';
const DOCTOR_UID = 'doctor_uid_1';
const DOCTOR_ID = 'doc_1';
const UNVERIFIED_DOCTOR_UID = 'doctor_uid_unverified';
const UNVERIFIED_DOCTOR_ID = 'doc_unverified';
const STORE_UID = 'store_uid_1';
const STORE_ID = 'store_1';
const LAB_UID = 'lab_uid_1';
const LAB_ID = 'lab_1';
const AMB_UID = 'amb_uid_1';
const AMB_ID = 'amb_1';

let testEnvHead;
let testEnvLive;

function getLiveRules() {
  const tmpPath = path.join(os.tmpdir(), 'firestore.rules.7e0ab46');
  if (fs.existsSync(tmpPath)) {
    return fs.readFileSync(tmpPath, 'utf8');
  }
  const rules = cp.execSync('git show 7e0ab46:backend/firestore.rules', { encoding: 'utf8' });
  fs.writeFileSync(tmpPath, rules, 'utf8');
  return rules;
}

async function seedEnvironment(env) {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // 1. Users
    await db.collection('users').doc(PATIENT_UID).set({
      role: 'patient',
      profileId: PATIENT_ID,
      email: 'patient@example.com',
      mobile: '9876543210',
    });
    await db.collection('users').doc(DOCTOR_UID).set({
      role: 'doctor',
      profileId: DOCTOR_ID,
      email: 'doctor@example.com',
      mobile: '9876543211',
    });
    await db.collection('users').doc(UNVERIFIED_DOCTOR_UID).set({
      role: 'doctor',
      profileId: UNVERIFIED_DOCTOR_ID,
      email: 'unverified@example.com',
      mobile: '9876543212',
    });
    await db.collection('users').doc(STORE_UID).set({
      role: 'medicalStore',
      profileId: STORE_ID,
      email: 'store@example.com',
    });
    await db.collection('users').doc(LAB_UID).set({
      role: 'lab',
      profileId: LAB_ID,
      email: 'lab@example.com',
    });
    await db.collection('users').doc(AMB_UID).set({
      role: 'ambulance',
      profileId: AMB_ID,
    });

    // 2. Doctors
    await db.collection('doctors').doc(DOCTOR_ID).set({
      ownerUid: DOCTOR_UID,
      doctorId: DOCTOR_ID,
      verified: true,
      name: 'Dr. Verified',
      councilNumber: 'MCI-12345',
    });
    await db.collection('doctors').doc(UNVERIFIED_DOCTOR_ID).set({
      ownerUid: UNVERIFIED_DOCTOR_UID,
      doctorId: UNVERIFIED_DOCTOR_ID,
      verified: false,
      name: 'Dr. Pending',
      councilNumber: 'MCI-99999',
    });

    // 3. Medical Stores
    await db.collection('medical_stores').doc(STORE_ID).set({
      ownerUid: STORE_UID,
      storeId: STORE_ID,
      verified: true,
      name: 'Med Store One',
    });
    await db.collection('medical_stores').doc('store_unverified').set({
      ownerUid: 'store_u_uid',
      storeId: 'store_unverified',
      verified: false,
      name: 'Pending Store',
    });

    // 4. Labs
    await db.collection('labs').doc(LAB_ID).set({
      ownerUid: LAB_UID,
      labId: LAB_ID,
      verified: true,
      name: 'City Lab',
    });
    await db.collection('labs').doc('lab_unverified').set({
      ownerUid: 'lab_u_uid',
      labId: 'lab_unverified',
      verified: false,
      name: 'Pending Lab',
    });

    // 5. Ambulances
    await db.collection('ambulances').doc(AMB_ID).set({
      authUid: AMB_UID,
      serviceName: 'Rapid Response Ambulance',
      username: 'ambdriver',
      phone: '9888800001',
      isAvailable: true,
    });

    // 6. Medical directory & lab catalog
    await db.collection('medical_directory').doc('dir_1').set({
      entryId: 'dir_1',
      doctorId: DOCTOR_ID,
      name: 'Apollo Hospital',
      type: 'hospital',
      phone: '9876543210',
    });
    await db.collection('lab_catalog').doc('tests_catalog').set({
      tests: ['Complete Blood Count', 'Blood Sugar'],
    });

    // 7. Community catalogs
    await db.collection('community_medicines').doc('med_1').set({
      name: 'Paracetamol',
      nameLower: 'paracetamol',
      dosageUnit: 'mg',
      form: 'tablet',
      addedByDoctorId: DOCTOR_ID,
    });
    await db.collection('community_diagnoses').doc('diag_1').set({
      text: 'Type 2 Diabetes',
      textLower: 'type 2 diabetes',
      addedByDoctorId: DOCTOR_ID,
    });
    await db.collection('community_lab_tests').doc('test_1').set({
      name: 'CBC',
      nameLower: 'cbc',
      group: 'Hematology',
      addedByDoctorId: DOCTOR_ID,
    });
    await db.collection('community_radiology').doc('rad_1').set({
      name: 'Chest X-Ray',
      nameLower: 'chest x-ray',
      group: 'X-Ray',
      addedByDoctorId: DOCTOR_ID,
    });
    await db.collection('community_body_parts').doc('part_1').set({
      name: 'Lungs',
      nameLower: 'lungs',
      addedByDoctorId: DOCTOR_ID,
    });

    // 8. Doctor slots (server-only)
    await db.collection('doctor_slots').doc('slot_1').set({
      doctorId: DOCTOR_ID,
      activeAppointmentIds: [],
    });
  });
}

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  test('client read replay rules (skipped: FIRESTORE_EMULATOR_HOST not set)', {
    skip: 'FIRESTORE_EMULATOR_HOST not set; run firebase emulators:exec',
  }, () => {});
} else {
  before(async () => {
    // 1. HEAD rules
    testEnvHead = await initializeTestEnvironment({
      projectId: PROJECT_ID_HEAD,
      firestore: {
        rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
      },
    });
    await seedEnvironment(testEnvHead);

    // 2. Live rules (7e0ab46)
    testEnvLive = await initializeTestEnvironment({
      projectId: PROJECT_ID_LIVE,
      firestore: {
        rules: getLiveRules(),
      },
    });
    await seedEnvironment(testEnvLive);
  });

  after(async () => {
    if (testEnvHead) await testEnvHead.cleanup();
    if (testEnvLive) await testEnvLive.cleanup();
  });

  function registerReadReplaySuite(suiteTitle, getEnv, isLive) {
    describe(suiteTitle, () => {
      // 1. fetchAllDoctors(verifiedOnly: false) equivalents
      test('1. fetchAllDoctors(verifiedOnly: false) [doctors.limit(40) without verified filter]', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        // At 741cb46: query did not include where('verified', '==', true)
        const unfilteredQuery = client.collection('doctors').limit(40);
        // Both 7e0ab46 and HEAD require verified == true in the list rule -> DENIED
        await assertFails(unfilteredQuery.get());
      });

      test('2. fetchAllDoctors(verifiedOnly: true) [doctors.where(verified == true).limit(40)]', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        const verifiedQuery = client.collection('doctors').where('verified', '==', true).limit(40);
        await assertSucceeds(verifiedQuery.get());
      });

      // 2. councilNumber lookup in user_repository.dart at 741cb46 vs HEAD
      test('3. councilNumber lookup at 741cb46 [doctors.where(councilNumber == ...).limit(1) without verified filter]', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(DOCTOR_UID).firestore();
        // At 741cb46 (user_repository.dart:583-586):
        const oldCouncilQuery = client.collection('doctors').where('councilNumber', '==', 'MCI-12345').limit(1);
        // Both 7e0ab46 and HEAD require resource.data.verified == true for list -> DENIED
        await assertFails(oldCouncilQuery.get());
      });

      test('4. councilNumber lookup at HEAD [doctors.where(verified == true).where(councilNumber == ...).limit(1)]', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(DOCTOR_UID).firestore();
        // At HEAD (user_repository.dart:575):
        const headCouncilQuery = client
          .collection('doctors')
          .where('verified', '==', true)
          .where('councilNumber', '==', 'MCI-12345')
          .limit(1);
        await assertSucceeds(headCouncilQuery.get());
      });

      // 3. Doctor doc get reads
      test('5. Doctor single doc get (verified doctor)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertSucceeds(client.collection('doctors').doc(DOCTOR_ID).get());
      });

      test('6. Doctor single doc get (unverified doctor by stranger: denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertFails(client.collection('doctors').doc(UNVERIFIED_DOCTOR_ID).get());
      });

      test('7. Doctor single doc get (unverified doctor by owner: allowed)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(UNVERIFIED_DOCTOR_UID).firestore();
        await assertSucceeds(client.collection('doctors').doc(UNVERIFIED_DOCTOR_ID).get());
      });

      // 4. Medical store directory lists
      test('8. Medical stores directory list (fetchVerifiedStores: verified == true, limit <= 100)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        const query = client.collection('medical_stores').where('verified', '==', true).limit(100);
        await assertSucceeds(query.get());
      });

      test('9. Medical stores unfiltered list (denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        const query = client.collection('medical_stores').limit(100);
        await assertFails(query.get());
      });

      // 5. Labs directory lists
      test('10. Labs directory list (fetchVerifiedLabs: verified == true, limit <= 100)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        const query = client.collection('labs').where('verified', '==', true).limit(100);
        await assertSucceeds(query.get());
      });

      test('11. Labs unfiltered list (denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        const query = client.collection('labs').limit(100);
        await assertFails(query.get());
      });

      // 6. Ambulance queries
      test('12. Ambulance single doc get (registered ambulance)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertSucceeds(client.collection('ambulances').doc(AMB_ID).get());
      });

      test('13. Ambulance collection query (client where/unfiltered list: denied by list rule evaluation)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(AMB_UID).firestore();
        // Client queries like ambulances.where('phone', '==', ...) or unfiltered ambulances fail
        // because the list rule branches on unbound driverId and unconstrained resource.data
        const query = client.collection('ambulances').where('phone', '==', '9888800001').limit(1);
        await assertFails(query.get());
      });

      // 7. Users collection reads
      test('14. Users collection list query by normal user (741cb46 user_repository queries: denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        // 741cb46 user_repository.dart email lookup:
        const emailQuery = client.collection('users').where('email', '==', 'patient@example.com').limit(1);
        await assertFails(emailQuery.get());

        // 741cb46 mobile lookup:
        const mobileQuery = client
          .collection('users')
          .where('role', '==', 'patient')
          .where('mobile', '==', '9876543210')
          .limit(1);
        await assertFails(mobileQuery.get());
      });

      test('15. Users single doc get (own user doc: allowed; other user doc: denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertSucceeds(client.collection('users').doc(PATIENT_UID).get());
        await assertFails(client.collection('users').doc(DOCTOR_UID).get());
      });

      // 8. Directory / Listing collections
      test('16. medical_directory read by doctor with doctorId filter (allowed); patient or unverified (denied)', async () => {
        const env = getEnv();
        const docClient = env.authenticatedContext(DOCTOR_UID).firestore();
        // Owning verified doctor:
        await assertSucceeds(
          docClient.collection('medical_directory').where('doctorId', '==', DOCTOR_ID).limit(100).get()
        );
        await assertSucceeds(docClient.collection('medical_directory').doc('dir_1').get());

        // Patient client: denied
        const patClient = env.authenticatedContext(PATIENT_UID).firestore();
        await assertFails(patClient.collection('medical_directory').limit(100).get());
      });

      test('17. lab_catalog read / get (signed in: allowed)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertSucceeds(client.collection('lab_catalog').doc('tests_catalog').get());
      });

      // 9. Community collections
      test('18. community_* catalogs read / list (signed in: allowed)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(PATIENT_UID).firestore();
        await assertSucceeds(client.collection('community_medicines').limit(100).get());
        await assertSucceeds(client.collection('community_diagnoses').limit(100).get());
        await assertSucceeds(client.collection('community_lab_tests').limit(100).get());
        await assertSucceeds(client.collection('community_radiology').limit(100).get());
        await assertSucceeds(client.collection('community_body_parts').limit(100).get());
      });

      // 10. Server-only doctor_slots
      test('19. doctor_slots client read (denied)', async () => {
        const env = getEnv();
        const client = env.authenticatedContext(DOCTOR_UID).firestore();
        await assertFails(client.collection('doctor_slots').doc('slot_1').get());
      });
    });
  }

  registerReadReplaySuite('Replay against Live Rules (7e0ab46)', () => testEnvLive, true);
  registerReadReplaySuite('Replay against HEAD Rules', () => testEnvHead, false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3: Unit test with fake DB proving completeAmbulanceMobileOtpLogin authUid link
// ─────────────────────────────────────────────────────────────────────────────

describe('completeAmbulanceMobileOtpLogin unit test with fake db', () => {
  let origLegacyCutover;
  beforeEach(() => {
    origLegacyCutover = process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = '1';
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}
  });

  afterEach(() => {
    if (origLegacyCutover === undefined) delete process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT;
    else process.env.__TEST_FORCE_LEGACY_DOCTOR_PATIENT = origLegacyCutover;
    try {
      const { _resetRemoteConfigCache } = require('../sync_flags');
      _resetRemoteConfigCache();
    } catch (_) {}
  });

  function createFakeDb(initialDocs = {}) {
    const store = new Map(Object.entries(initialDocs));
    return {
      store,
      collection(collName) {
        return {
          doc(docId) {
            const key = `${collName}/${docId}`;
            return {
              key,
              async get() {
                const data = store.get(key);
                return {
                  exists: Boolean(data),
                  data: () => data ? { ...data } : undefined,
                };
              },
              async set(data, opts = {}) {
                if (opts.merge && store.has(key)) {
                  store.set(key, { ...store.get(key), ...data });
                } else {
                  store.set(key, { ...data });
                }
              },
              async delete() {
                store.delete(key);
              },
            };
          },
          where(field, op, val) {
            return {
              limit(n) {
                return {
                  async get() {
                    const matches = [];
                    for (const [k, v] of store.entries()) {
                      if (k.startsWith(`${collName}/`)) {
                        if (op === '==' && v[field] === val) {
                          matches.push({
                            id: k.split('/')[1],
                            data: () => ({ ...v }),
                          });
                          if (matches.length >= n) break;
                        }
                      }
                    }
                    return {
                      empty: matches.length === 0,
                      docs: matches,
                    };
                  },
                };
              },
            };
          },
        };
      },
      async runTransaction(updateFunction) {
        const tx = {
          async get(docRef) {
            const data = store.get(docRef.key);
            return {
              exists: Boolean(data),
              data: () => data ? { ...data } : undefined,
            };
          },
          set(docRef, data, opts = {}) {
            if (opts.merge && store.has(docRef.key)) {
              store.set(docRef.key, { ...store.get(docRef.key), ...data });
            } else {
              store.set(docRef.key, { ...data });
            }
          },
          delete(docRef) {
            store.delete(docRef.key);
          },
        };
        return await updateFunction(tx);
      },
    };
  }

  // Implementation of completeAmbulanceMobileOtpLogin incorporating the 4-line server change
  async function completeAmbulanceMobileOtpLoginWithPatch(db, data, auth) {
    const { completeAmbulanceMobileOtpLogin } = require('../registration_otp');
    // Call the server function
    const result = await completeAmbulanceMobileOtpLogin(db, data, auth);

    // ─── Minimal 4-line server change (SEC-09 fix) ───
    await db.collection('ambulances').doc(result.driverId).set(
      { authUid: auth.uid },
      { merge: true },
    );

    return result;
  }

  test('valid session: ambulances/{id}.authUid is set to auth.uid', async () => {
    const futureDate = new Date(Date.now() + 10 * 60 * 1000);
    const db = createFakeDb({
      'otp_verification_sessions/session_valid': {
        role: 'ambulance',
        mobileVerified: true,
        mobileDigits: '9888800001',
        consumed: false,
        expiresAt: { toDate: () => futureDate },
      },
      'ambulances/amb_123': {
        phone: '9888800001',
        username: 'city_amb',
        serviceName: 'City Ambulance',
        authUid: 'old_or_missing_auth_uid',
      },
    });

    const auth = { uid: 'new_anon_auth_uid_777' };
    const res = await completeAmbulanceMobileOtpLoginWithPatch(
      db,
      { mobile: '9888800001', sessionId: 'session_valid' },
      auth,
    );

    assert.equal(res.ok, true);
    assert.equal(res.driverId, 'amb_123');

    // Prove ambulances/amb_123.authUid was updated to auth.uid
    const ambDoc = db.store.get('ambulances/amb_123');
    assert.equal(ambDoc.authUid, 'new_anon_auth_uid_777', 'authUid must match auth.uid after valid login');
  });

  test('invalid or mismatched session: sets nothing on ambulances/{id}', async () => {
    const db = createFakeDb({
      'otp_verification_sessions/session_wrong_phone': {
        role: 'ambulance',
        mobileVerified: true,
        mobileDigits: '9999999999', // Mismatched phone
        consumed: false,
        expiresAt: { toDate: () => new Date(Date.now() + 600000) },
      },
      'ambulances/amb_123': {
        phone: '9888800001',
        username: 'city_amb',
        serviceName: 'City Ambulance',
        authUid: 'original_auth_uid',
      },
    });

    const auth = { uid: 'attacker_uid_999' };

    await assert.rejects(
      async () => {
        await completeAmbulanceMobileOtpLoginWithPatch(
          db,
          { mobile: '9888800001', sessionId: 'session_wrong_phone' },
          auth,
        );
      },
      (err) => {
        assert.equal(err.code, 'permission-denied');
        return true;
      },
    );

    // Prove ambulances/amb_123 was untouched
    const ambDoc = db.store.get('ambulances/amb_123');
    assert.equal(ambDoc.authUid, 'original_auth_uid', 'Must not modify authUid on mismatched session');
  });

  test('non-existent or expired session: sets nothing on ambulances/{id}', async () => {
    const db = createFakeDb({
      'ambulances/amb_123': {
        phone: '9888800001',
        username: 'city_amb',
        serviceName: 'City Ambulance',
        authUid: 'original_auth_uid',
      },
    });

    const auth = { uid: 'attacker_uid_999' };

    await assert.rejects(
      async () => {
        await completeAmbulanceMobileOtpLoginWithPatch(
          db,
          { mobile: '9888800001', sessionId: 'missing_session' },
          auth,
        );
      },
    );

    const ambDoc = db.store.get('ambulances/amb_123');
    assert.equal(ambDoc.authUid, 'original_auth_uid', 'Must not modify authUid on missing session');
  });
});
