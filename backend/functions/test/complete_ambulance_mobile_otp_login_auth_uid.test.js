'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  completeAmbulanceMobileOtpLogin,
} = require('../registration_otp');

function createFakeDb(initialDocs = {}, { customQueryHandler } = {}) {
  const docs = new Map();
  for (const [key, val] of Object.entries(initialDocs)) {
    docs.set(key, { ...val });
  }
  const writeLog = [];

  function getDoc(path) {
    return docs.get(path);
  }

  function setDoc(path, data, options = {}) {
    writeLog.push({ action: 'set', path, data: { ...data }, options });
    if (options.merge && docs.has(path)) {
      docs.set(path, { ...docs.get(path), ...data });
    } else {
      docs.set(path, { ...data });
    }
  }

  function deleteDoc(path) {
    writeLog.push({ action: 'delete', path });
    docs.delete(path);
  }

  return {
    docs,
    writeLog,
    collection(colName) {
      return {
        doc(docId) {
          const path = `${colName}/${docId}`;
          return {
            id: docId,
            path,
            async get() {
              const data = getDoc(path);
              return {
                id: docId,
                exists: data !== undefined && data !== null,
                data: () => (data ? { ...data } : undefined),
              };
            },
            async set(data, options = {}) {
              setDoc(path, data, options);
            },
            async delete() {
              deleteDoc(path);
            },
          };
        },
        where(field, op, val) {
          return {
            limit(n) {
              return {
                async get() {
                  if (customQueryHandler) {
                    const customResult = customQueryHandler(colName, field, op, val, n);
                    if (customResult !== undefined) return customResult;
                  }
                  const matchingDocs = [];
                  for (const [p, d] of docs.entries()) {
                    if (p.startsWith(`${colName}/`)) {
                      if (op === '==' && d && d[field] === val) {
                        const id = p.slice(colName.length + 1);
                        matchingDocs.push({
                          id,
                          data: () => ({ ...d }),
                        });
                        if (matchingDocs.length >= n) break;
                      }
                    }
                  }
                  return {
                    empty: matchingDocs.length === 0,
                    docs: matchingDocs,
                  };
                },
              };
            },
          };
        },
      };
    },
    async runTransaction(txFn) {
      const pendingSets = [];
      const pendingDeletes = [];
      const tx = {
        async get(ref) {
          return await ref.get();
        },
        set(ref, data, options = {}) {
          pendingSets.push({ ref, data, options });
        },
        delete(ref) {
          pendingDeletes.push(ref);
        },
      };
      const result = await txFn(tx);
      for (const d of pendingDeletes) {
        await d.delete();
      }
      for (const s of pendingSets) {
        await s.ref.set(s.data, s.options);
      }
      return result;
    },
  };
}

function futureTimestamp(msFromNow = 300000) {
  const d = new Date(Date.now() + msFromNow);
  return {
    toDate: () => d,
  };
}

function pastTimestamp(msAgo = 60000) {
  const d = new Date(Date.now() - msAgo);
  return {
    toDate: () => d,
  };
}

test.describe('completeAmbulanceMobileOtpLogin server-side authUid binding', () => {
  const validMobile = '9876543210';
  const driverUid = 'driver-auth-uid-456';
  const ambDocId = 'amb-reg-1001';


  function validSetup(overrides = {}) {
    return {
      [`ambulances/${ambDocId}`]: {
        phone: '+919876543210',
        username: 'city_ambulance',
        serviceName: 'City Ambulance Care',
        authUid: '',
        ...(overrides.ambulance || {}),
      },
      'otp_verification_sessions/session-valid-01': {
        role: 'ambulance',
        mobileDigits: validMobile,
        mobileVerified: true,
        consumed: false,
        expiresAt: futureTimestamp(300000),
        ...(overrides.session || {}),
      },
    };
  }

  test('(a) valid session sets authUid on the ambulance document', async () => {
    const db = createFakeDb(validSetup());
    const auth = { uid: driverUid };

    const result = await completeAmbulanceMobileOtpLogin(
      db,
      { mobile: validMobile, sessionId: 'session-valid-01' },
      auth,
    );

    assert.equal(result.ok, true);
    assert.equal(result.driverId, ambDocId);

    const ambDoc = db.docs.get(`ambulances/${ambDocId}`);
    assert.equal(ambDoc.authUid, driverUid);

    const ambulanceWrites = db.writeLog.filter(
      (w) => w.action === 'set' && w.path === `ambulances/${ambDocId}`,
    );
    assert.equal(ambulanceWrites.length, 1);
    assert.deepEqual(ambulanceWrites[0].data, { authUid: driverUid });
    assert.deepEqual(ambulanceWrites[0].options, { merge: true });
  });

  test('(b) same uid is a no-op: does not execute write to ambulance document', async () => {
    const db = createFakeDb(
      validSetup({
        ambulance: { authUid: driverUid },
      }),
    );
    const auth = { uid: driverUid };

    const result = await completeAmbulanceMobileOtpLogin(
      db,
      { mobile: validMobile, sessionId: 'session-valid-01' },
      auth,
    );

    assert.equal(result.ok, true);
    assert.equal(result.driverId, ambDocId);

    const ambulanceWrites = db.writeLog.filter(
      (w) => w.action === 'set' && w.path === `ambulances/${ambDocId}`,
    );
    assert.equal(ambulanceWrites.length, 0, 'No write should occur when authUid already matches');
  });

  test('(c) stale authUid is replaced by the new caller authUid', async () => {
    const db = createFakeDb(
      validSetup({
        ambulance: { authUid: 'old-stale-device-uid' },
      }),
    );
    const auth = { uid: driverUid };

    const result = await completeAmbulanceMobileOtpLogin(
      db,
      { mobile: validMobile, sessionId: 'session-valid-01' },
      auth,
    );

    assert.equal(result.ok, true);
    const ambDoc = db.docs.get(`ambulances/${ambDocId}`);
    assert.equal(ambDoc.authUid, driverUid);

    const ambulanceWrites = db.writeLog.filter(
      (w) => w.action === 'set' && w.path === `ambulances/${ambDocId}`,
    );
    assert.equal(ambulanceWrites.length, 1);
    assert.deepEqual(ambulanceWrites[0].data, { authUid: driverUid });
  });

  test('(d) invalid/mismatched/expired session throws and writes nothing to ambulance', async () => {
    // 1. Missing session doc -> throws failed-precondition
    {
      const db = createFakeDb(validSetup());
      const auth = { uid: driverUid };

      await assert.rejects(
        () => completeAmbulanceMobileOtpLogin(
          db,
          { mobile: validMobile, sessionId: 'nonexistent-session' },
          auth,
        ),
        (err) => {
          assert.ok(err instanceof HttpsError);
          assert.equal(err.code, 'failed-precondition');
          return true;
        },
      );
      assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
      const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
      assert.equal(ambWrites.length, 0);
    }

    // 2. Expired session doc -> throws deadline-exceeded
    {
      const db = createFakeDb(validSetup({
        session: { expiresAt: pastTimestamp(60000) },
      }));
      const auth = { uid: driverUid };

      await assert.rejects(
        () => completeAmbulanceMobileOtpLogin(
          db,
          { mobile: validMobile, sessionId: 'session-valid-01' },
          auth,
        ),
        (err) => {
          assert.ok(err instanceof HttpsError);
          assert.equal(err.code, 'deadline-exceeded');
          return true;
        },
      );
      assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
      const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
      assert.equal(ambWrites.length, 0);
    }

    // 3. Mismatched session role -> throws failed-precondition
    {
      const db = createFakeDb(validSetup({
        session: { role: 'patient' },
      }));
      const auth = { uid: driverUid };

      await assert.rejects(
        () => completeAmbulanceMobileOtpLogin(
          db,
          { mobile: validMobile, sessionId: 'session-valid-01' },
          auth,
        ),
        (err) => {
          assert.ok(err instanceof HttpsError);
          assert.equal(err.code, 'failed-precondition');
          return true;
        },
      );
      assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
      const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
      assert.equal(ambWrites.length, 0);
    }

    // 4. Mismatched mobile in session -> throws permission-denied
    {
      const db = createFakeDb(validSetup({
        session: { mobileDigits: '9111111111' },
      }));
      const auth = { uid: driverUid };

      await assert.rejects(
        () => completeAmbulanceMobileOtpLogin(
          db,
          { mobile: validMobile, sessionId: 'session-valid-01' },
          auth,
        ),
        (err) => {
          assert.ok(err instanceof HttpsError);
          assert.equal(err.code, 'permission-denied');
          return true;
        },
      );
      assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
      const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
      assert.equal(ambWrites.length, 0);
    }
  });

  test('(e) unauthenticated (auth null) throws unauthenticated', async () => {
    const db = createFakeDb(validSetup());

    await assert.rejects(
      () => completeAmbulanceMobileOtpLogin(
        db,
        { mobile: validMobile, sessionId: 'session-valid-01' },
        null,
      ),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'unauthenticated');
        return true;
      },
    );
    assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
    const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
    assert.equal(ambWrites.length, 0);
  });

  test('(f) phone on doc mismatch throws permission-denied and writes nothing', async () => {
    const db = createFakeDb(
      validSetup({
        ambulance: { phone: '+919999999999' },
      }),
      {
        customQueryHandler: (colName, field, op, val) => {
          if (colName === 'ambulances' && field === 'phone') {
            return {
              empty: false,
              docs: [
                {
                  id: ambDocId,
                  data: () => ({
                    phone: '+919999999999',
                    username: 'city_ambulance',
                    serviceName: 'City Ambulance Care',
                    authUid: '',
                  }),
                },
              ],
            };
          }
        },
      },
    );
    const auth = { uid: driverUid };

    await assert.rejects(
      () => completeAmbulanceMobileOtpLogin(
        db,
        { mobile: validMobile, sessionId: 'session-valid-01' },
        auth,
      ),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'permission-denied');
        assert.equal(err.message, 'Registered mobile does not match ambulance profile.');
        return true;
      },
    );

    const ambWrites = db.writeLog.filter((w) => w.path === `ambulances/${ambDocId}`);
    assert.equal(ambWrites.length, 0);
    assert.equal(db.docs.get(`ambulances/${ambDocId}`).authUid, '');
  });

  test('(g) no matching doc -> not-found and no write', async () => {
    const db = createFakeDb({
      'otp_verification_sessions/session-valid-01': {
        role: 'ambulance',
        mobileDigits: validMobile,
        mobileVerified: true,
        consumed: false,
        expiresAt: futureTimestamp(300000),
      },
    });
    const auth = { uid: driverUid };

    await assert.rejects(
      () => completeAmbulanceMobileOtpLogin(
        db,
        { mobile: validMobile, sessionId: 'session-valid-01' },
        auth,
      ),
      (err) => {
        assert.ok(err instanceof HttpsError);
        assert.equal(err.code, 'not-found');
        assert.equal(err.message, 'No ambulance account found for this mobile number.');
        return true;
      },
    );

    const ambWrites = db.writeLog.filter((w) => w.path.startsWith('ambulances/'));
    assert.equal(ambWrites.length, 0);
  });
});
