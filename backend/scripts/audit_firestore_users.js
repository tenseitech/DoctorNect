/**
 * DoctorNect: Firestore Users Security & Parity Auditor (READ-ONLY)
 * File: scripts/audit_firestore_users.js
 * 
 * Purpose:
 * Audits the Firestore 'users' collection and related role profile collections
 * using Firebase Admin SDK in strict READ-ONLY mode.
 * 
 * Flags:
 * 1. Duplicate profileId across multiple users.
 * 2. Roles not in the allowed schema role list.
 * 3. Patient documents with verified == true.
 * 4. Users whose profileId does not match the ownerUid of the corresponding profile doc.
 * 5. Users with no matching profile document in their role collection.
 * 
 * Output:
 * Generates a local JSON audit report (scripts/firestore_users_audit_results.json).
 * NEVER logs or exposes credentials, API keys, or private service account secrets.
 * 
 * Usage:
 *   node scripts/audit_firestore_users.js
 */

const fs = require('fs');
const path = require('path');

// Safe environment loading if available
const loadEnvPath = path.join(__dirname, 'load_env.js');
if (fs.existsSync(loadEnvPath)) {
  try {
    require('./load_env').loadEnv();
  } catch (_) {
    // Continue if load_env is not present
  }
}

const admin = require('firebase-admin');

// Allowed roles in the DoctorNect platform schema
const ALLOWED_ROLES = new Set([
  'doctor',
  'patient',
  'medicalStore',
  'lab',
  'ambulance',
  'super_admin',
  'superAdmin',
  'admin',
  'nurse',
  'receptionist',
  'billing_staff',
  'hospital_admin'
]);

// Mapping of role string to Firestore collection name
const ROLE_TO_COLLECTION = {
  doctor: 'doctors',
  patient: 'patients',
  medicalStore: 'medical_stores',
  lab: 'labs',
  ambulance: 'ambulances'
};

// Initialize Firebase Admin SDK safely (READ-ONLY operations only)
function initFirebaseAdmin() {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  const saCandidates = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(process.cwd(), 'service-account.json'),
  ];
  const saPath = saCandidates.find(p => p && fs.existsSync(p));

  if (saPath) {
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId: sa.project_id || 'medibond-45fad',
    });
  }

  return admin.initializeApp({ projectId: 'medibond-45fad' });
}

async function auditFirestoreUsers() {
  console.log('[Audit] Initializing Firebase Admin SDK (READ-ONLY mode)...');
  initFirebaseAdmin();
  const db = admin.firestore();

  console.log('[Audit] Fetching all documents from "users" collection...');
  const usersSnapshot = await db.collection('users').get();
  console.log(`[Audit] Retrieved ${usersSnapshot.size} user documents.`);

  const profileIdMap = new Map(); // profileId -> Array<{ uid, role, email, mobile }>
  const invalidRoles = [];
  const patientVerifiedTrueUsers = [];
  const profileChecks = []; // Promises for checking role documents

  // 1. Scan users collection
  for (const doc of usersSnapshot.docs) {
    const uid = doc.id;
    const data = doc.data() || {};
    const role = data.role;
    const profileId = data.profileId ? String(data.profileId).trim() : null;
    const email = data.email ? String(data.email) : null;
    const mobile = data.mobile ? String(data.mobile) : null;
    const verified = data.verified === true;

    // Check 1: Allowed roles
    if (!role || !ALLOWED_ROLES.has(role)) {
      invalidRoles.push({
        uid,
        role: role ?? null,
        profileId,
        email,
        mobile
      });
    }

    // Check 2: Profile ID uniqueness mapping
    if (profileId) {
      if (!profileIdMap.has(profileId)) {
        profileIdMap.set(profileId, []);
      }
      profileIdMap.get(profileId).push({ uid, role, email, mobile });
    }

    // Check 3: Patient with verified == true in users collection
    if (role === 'patient' && verified) {
      patientVerifiedTrueUsers.push({
        source: 'users',
        uid,
        profileId,
        verified: true,
        verificationStatus: data.verificationStatus || null
      });
    }

    // Prepare profile document checks for mapped roles
    const targetColl = ROLE_TO_COLLECTION[role];
    if (targetColl && profileId) {
      profileChecks.push(
        db.collection(targetColl).doc(profileId).get().then(profileSnap => ({
          uid,
          role,
          profileId,
          targetCollection: targetColl,
          exists: profileSnap.exists,
          profileData: profileSnap.exists ? profileSnap.data() : null
        }))
      );
    }
  }

  // 2. Identify duplicate profileIds
  const duplicateProfileIds = [];
  for (const [profileId, userList] of profileIdMap.entries()) {
    if (userList.length > 1) {
      duplicateProfileIds.push({
        profileId,
        count: userList.length,
        users: userList
      });
    }
  }

  // 3. Scan patients collection directly for verified == true
  console.log('[Audit] Checking "patients" collection for verified == true documents...');
  const verifiedPatientsSnap = await db.collection('patients')
    .where('verified', '==', true)
    .get();

  const patientDocsVerifiedTrue = verifiedPatientsSnap.docs.map(doc => {
    const pData = doc.data() || {};
    return {
      source: 'patients',
      patientId: doc.id,
      ownerUid: pData.ownerUid || null,
      verified: true
    };
  });

  // 4. Resolve profile checks for ownership match and missing profiles
  console.log(`[Audit] Verifying ${profileChecks.length} role-specific profile document relationships...`);
  const profileResults = await Promise.all(profileChecks);

  const missingProfileDocs = [];
  const profileOwnerMismatches = [];

  for (const res of profileResults) {
    if (!res.exists) {
      missingProfileDocs.push({
        uid: res.uid,
        role: res.role,
        profileId: res.profileId,
        expectedCollection: res.targetCollection
      });
    } else {
      const pData = res.profileData || {};
      const ownerUid = pData.ownerUid || pData.authUid || pData.userId || null;
      if (ownerUid && ownerUid !== res.uid) {
        profileOwnerMismatches.push({
          uid: res.uid,
          role: res.role,
          profileId: res.profileId,
          collection: res.targetCollection,
          docOwnerUid: ownerUid
        });
      }
    }
  }

  // 5. Build final structured audit report
  const auditReport = {
    auditedAt: new Date().toISOString(),
    auditScope: 'Firestore users and role profile collections',
    summary: {
      totalUsersScanned: usersSnapshot.size,
      duplicateProfileIdCount: duplicateProfileIds.length,
      invalidRoleCount: invalidRoles.length,
      patientVerifiedTrueInUsersCount: patientVerifiedTrueUsers.length,
      patientVerifiedTrueInPatientsCount: patientDocsVerifiedTrue.length,
      missingProfileDocCount: missingProfileDocs.length,
      profileOwnerMismatchCount: profileOwnerMismatches.length
    },
    findings: {
      duplicateProfileIds,
      invalidRoles,
      patientVerifiedTrue: {
        usersCollection: patientVerifiedTrueUsers,
        patientsCollection: patientDocsVerifiedTrue
      },
      missingProfileDocs,
      profileOwnerMismatches
    }
  };

  const outputPath = path.join(__dirname, 'firestore_users_audit_results.json');
  fs.writeFileSync(outputPath, JSON.stringify(auditReport, null, 2), 'utf8');

  console.log('\n======================================================');
  console.log('             FIRESTORE USERS AUDIT SUMMARY            ');
  console.log('======================================================');
  console.log(`Total users scanned:               ${auditReport.summary.totalUsersScanned}`);
  console.log(`Duplicate profileId groups:        ${auditReport.summary.duplicateProfileIdCount}`);
  console.log(`Invalid roles found:               ${auditReport.summary.invalidRoleCount}`);
  console.log(`Patient verified=true (users):     ${auditReport.summary.patientVerifiedTrueInUsersCount}`);
  console.log(`Patient verified=true (patients):  ${auditReport.summary.patientVerifiedTrueInPatientsCount}`);
  console.log(`Missing role profile documents:    ${auditReport.summary.missingProfileDocCount}`);
  console.log(`Profile owner mismatches:          ${auditReport.summary.profileOwnerMismatchCount}`);
  console.log('======================================================');
  console.log(`Audit report successfully written to: ${outputPath}\n`);

  return auditReport;
}

if (require.main === module) {
  auditFirestoreUsers().catch(err => {
    console.error('[Audit Error]:', err.message);
    process.exit(1);
  });
}

module.exports = { auditFirestoreUsers };
