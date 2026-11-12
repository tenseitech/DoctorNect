#!/usr/bin/env node
/**
 * scripts/check_reviewer_users.js
 *
 * READ-ONLY verification script for Google Play / App Store reviewer accounts.
 * Uses Firebase Admin SDK with existing service account credentials to look up
 * each of the 5 reviewer phones in Firebase Auth and Firestore.
 *
 * MODES:
 *   node scripts/check_reviewer_users.js          # Standard status audit
 *   node scripts/check_reviewer_users.js --verify # Strict login flow role resolution verification
 *
 * STRICT RULES:
 * - Read-only: ZERO writes.
 * - Zero secret values, credentials, or tokens are ever printed or logged.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const isVerifyMode = args.includes('--verify') || args.includes('-v');

const REVIEWER_SPECS = [
  { phone: '9999900001', role: 'patient', expectedProfileId: 'rev_pat_001', expectedUid: 'rev_fb_pat_001' },
  { phone: '9999900002', role: 'doctor', expectedProfileId: 'rev_doc_001', expectedUid: 'rev_fb_doc_001' },
  { phone: '9999900003', role: 'medicalStore', expectedProfileId: 'rev_store_001', expectedUid: 'rev_fb_store_001' },
  { phone: '9999900004', role: 'lab', expectedProfileId: 'rev_lab_001', expectedUid: 'rev_fb_lab_001' },
  { phone: '9999900005', role: 'ambulance', expectedProfileId: 'rev_amb_001', expectedUid: 'rev_fb_amb_001' },
];

function initializeAdmin() {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    path.resolve(__dirname, 'service-account.json');

  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || 'medibond-45fad',
    });
  }

  return admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || 'medibond-45fad',
  });
}

/**
 * Simulates findUserByMobileDigits exactly as implemented in backend/functions/registration_otp.js:1429-1528
 */
async function simulateFindUserByMobileDigits(db, digits) {
  const candidates = [digits, `+91${digits}`, `+91 ${digits}`, `+91-${digits}`, `91${digits}`, `0${digits}`];
  const fields = ['mobile', 'phone', 'phoneNumber', 'mobileNumber'];
  const collectionMap = {
    patient: 'patients',
    doctor: 'doctors',
    medicalStore: 'medical_stores',
    lab: 'labs',
    ambulance: 'ambulances',
  };

  // 1. Search users collection
  const userQueries = [];
  for (const candidate of candidates) {
    for (const field of fields) {
      userQueries.push(
        db.collection('users').where(field, '==', candidate).limit(1).get().then((snap) => {
          if (!snap.empty) {
            return { doc: snap.docs[0], field, source: 'users' };
          }
          return null;
        })
      );
    }
  }
  const userSnapshots = await Promise.all(userQueries);
  const userMatch = userSnapshots.find(Boolean);
  if (userMatch) {
    const doc = userMatch.doc;
    return {
      found: true,
      source: 'users',
      matchedField: userMatch.field,
      role: doc.data()?.role,
      uid: doc.id,
      data: doc.data(),
    };
  }

  // 2. Search role collections
  const roleQueries = [];
  for (const [r, coll] of Object.entries(collectionMap)) {
    for (const candidate of candidates) {
      for (const field of fields) {
        roleQueries.push(
          db.collection(coll).where(field, '==', candidate).limit(1).get().then((snap) => {
            if (!snap.empty) {
              return { role: r, doc: snap.docs[0], field, collection: coll };
            }
            return null;
          })
        );
      }
    }
  }
  const roleSnapshots = await Promise.all(roleQueries);
  const roleMatches = roleSnapshots.filter(Boolean);
  for (const match of roleMatches) {
    const profileId = String(match.doc.id || '').trim();
    if (profileId) {
      const userSnap = await db.collection('users').where('profileId', '==', profileId).limit(1).get();
      if (!userSnap.empty) {
        const uDoc = userSnap.docs[0];
        return {
          found: true,
          source: match.collection,
          matchedField: match.field,
          role: match.role,
          uid: uDoc.id,
          data: uDoc.data(),
        };
      }
    }
  }

  return { found: false, source: null, matchedField: null, role: null, uid: null, data: null };
}

/**
 * Simulates findAmbulanceByPhone + isRegisteredAmbulanceData from registration_otp.js:2646-2667
 */
async function simulateFindAmbulanceByPhone(db, digits) {
  const candidates = [digits, `+91${digits}`];
  for (const candidate of candidates) {
    const snapshot = await db.collection('ambulances').where('phone', '==', candidate).limit(1).get();
    if (!snapshot.empty) {
      const doc = snapshot.docs[0];
      const data = doc.data() || {};
      const username = String(data?.username || '').trim();
      const serviceName = String(data?.serviceName || '').trim();
      const isRegistered = username.length >= 3 && serviceName.length > 0;
      return { found: true, id: doc.id, username, serviceName, isRegistered, data };
    }
  }
  return { found: false, id: null, username: '', serviceName: '', isRegistered: false, data: null };
}

async function runAudit() {
  console.log('================================================================');
  console.log(`DOCTORNECT: REVIEWER USER STATUS AUDIT (${isVerifyMode ? 'LOGIN VERIFICATION MODE' : 'READ-ONLY'})`);
  console.log('================================================================');

  const app = initializeAdmin();
  const auth = admin.auth(app);
  const db = admin.firestore(app);

  const results = [];

  for (const spec of REVIEWER_SPECS) {
    const phone = spec.phone;
    let authUser = null;
    let authExists = false;

    // 1. Look up in Firebase Auth by phone (+91 and raw)
    try {
      authUser = await auth.getUserByPhoneNumber(`+91${phone}`);
      authExists = true;
    } catch (err) {
      if (err.code !== 'auth/user-not-found') {
        try {
          authUser = await auth.getUserByPhoneNumber(phone);
          authExists = true;
        } catch (_) {}
      }
    }

    // 2. Look up in Firestore 'users' collection
    let userDoc = null;
    let firestoreUserExists = false;

    if (authUser?.uid) {
      const docSnap = await db.collection('users').doc(authUser.uid).get();
      if (docSnap.exists) {
        userDoc = docSnap.data();
        firestoreUserExists = true;
      }
    }

    if (!userDoc) {
      const snap = await db.collection('users')
        .where('mobile', 'in', [phone, `+91${phone}`])
        .limit(1)
        .get();

      if (!snap.empty) {
        userDoc = snap.docs[0].data();
        firestoreUserExists = true;
      }
    }

    // 3. Extract Role & Profile Completed
    const role = userDoc?.role || authUser?.customClaims?.role || 'unknown';
    const profileCompleted = userDoc?.profileCompleted ?? false;

    // 4. Check Doctor Verification Status (if doctor)
    let doctorVerificationStatus = 'N/A';
    if (spec.role === 'doctor') {
      let docProfile = null;
      const profileId = userDoc?.profileId || `rev_doc_001`;

      const docSnap = await db.collection('doctors').doc(profileId).get();
      if (docSnap.exists) {
        docProfile = docSnap.data();
      } else {
        const snap = await db.collection('doctors')
          .where('mobile', 'in', [phone, `+91${phone}`])
          .limit(1)
          .get();
        if (!snap.empty) {
          docProfile = snap.docs[0].data();
        }
      }

      if (docProfile) {
        const isVerified = docProfile.verified === true;
        const status = docProfile.verificationStatus || docProfile.status || 'unknown';
        doctorVerificationStatus = `verified=${isVerified} (status: ${status})`;
      } else {
        doctorVerificationStatus = userDoc?.verified ? 'verified=true (users doc)' : 'profile not found';
      }
    }

    // 5. If --verify mode: execute full login role resolution simulation
    let verifyDetails = null;
    if (isVerifyMode) {
      const findResult = await simulateFindUserByMobileDigits(db, phone);
      let authUserByUid = null;
      if (findResult.found && findResult.uid) {
        try {
          authUserByUid = await auth.getUser(findResult.uid);
        } catch (_) {}
      }

      let ambCheck = null;
      if (spec.role === 'ambulance') {
        ambCheck = await simulateFindAmbulanceByPhone(db, phone);
      }

      const roleMatch = findResult.role === spec.role;
      const authOk = Boolean(authUserByUid);
      const profileOk = findResult.data?.profileCompleted === true;
      const verifiedOk = findResult.data?.verified === true || findResult.data?.status === 'approved' || findResult.data?.verificationStatus === 'verified';
      const ambOk = spec.role === 'ambulance' ? ambCheck?.isRegistered : true;

      const readyForLogin = findResult.found && roleMatch && authOk && profileOk && verifiedOk && ambOk;

      verifyDetails = {
        findUserFound: findResult.found,
        resolvedUid: findResult.uid || 'N/A',
        resolvedRole: findResult.role || 'N/A',
        authMatchesUid: authOk ? 'YES' : 'NO',
        roleMatchesExpected: roleMatch ? 'YES' : 'NO',
        profileCompleted: profileOk ? 'YES' : 'NO',
        verifiedApproved: verifiedOk ? 'YES' : 'NO',
        ambulanceCheckOk: spec.role === 'ambulance' ? (ambCheck.isRegistered ? 'YES' : `FAIL (username="${ambCheck.username}")`) : 'N/A',
        loginVerdict: readyForLogin ? 'PASS (Ready)' : 'FAIL (Pending seed)',
      };
    }

    results.push({
      phone,
      expectedRole: spec.role,
      authExists: authExists ? 'YES' : 'NO',
      firestoreExists: firestoreUserExists ? 'YES' : 'NO',
      role,
      profileCompleted: profileCompleted ? 'YES' : 'NO',
      doctorVerificationStatus,
      verifyDetails,
    });
  }

  if (isVerifyMode) {
    console.log('\n### LOGIN RESOLUTION VERIFICATION TABLE (completeMobileOtpLogin Simulation):');
    console.log('| Phone | Expected Role | Resolved UID | findUser | Auth getUser(uid) | Role Match | profileCompleted | Verified/Approved | Ambulance Valid | Login Verdict |');
    console.log('|:---|:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---|');
    for (const r of results) {
      const v = r.verifyDetails;
      console.log(`| ${r.phone} | ${r.expectedRole} | ${v.resolvedUid} | ${v.findUserFound ? 'YES' : 'NO'} | ${v.authMatchesUid} | ${v.roleMatchesExpected} | ${v.profileCompleted} | ${v.verifiedApproved} | ${v.ambulanceCheckOk} | **${v.loginVerdict}** |`);
    }
  } else {
    // Print Summary Table
    console.log('\n| Phone | Auth Exists | Firestore User | Role | Profile Completed | Doctor Verification Status |');
    console.log('|:---|:---:|:---:|:---:|:---:|:---|');
    for (const r of results) {
      console.log(`| ${r.phone} | ${r.authExists} | ${r.firestoreExists} | ${r.role} | ${r.profileCompleted} | ${r.doctorVerificationStatus} |`);
    }
  }

  console.log('\n================================================================');
  console.log('AUDIT COMPLETE: 0 writes performed.');
  console.log('================================================================\n');

  return results;
}

if (require.main === module) {
  runAudit()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Audit failed:', err?.message || err);
      process.exit(1);
    });
}

module.exports = {
  checkReviewerUsers: runAudit,
  simulateFindUserByMobileDigits,
  simulateFindAmbulanceByPhone,
};
