'use strict';

/**
 * seed_reviewer_accounts.js
 *
 * Provisions server-side pre-approved Play Store / App Store reviewer dummy accounts
 * into Firebase (Auth + Firestore) via Firebase Admin SDK.
 *
 * Safety Guards:
 *   - DRY-RUN by default. Zero writes without explicit --apply flag.
 *   - Only fictitious dummy numbers (9999900001 - 9999900005).
 *   - Sets verified: true, status: 'approved', verificationStatus: 'verified', profileCompleted: true.
 *
 * Usage:
 *   node scripts/seed_reviewer_accounts.js            # DRY RUN (safe preview)
 *   node scripts/seed_reviewer_accounts.js --apply    # Execute writes
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const args = process.argv.slice(2);
const isApply = args.includes('--apply');
const isDryRun = !isApply;

const REVIEWER_ACCOUNTS = [
  {
    role: 'patient',
    profileId: 'rev_pat_001',
    firebaseUid: 'rev_fb_pat_001',
    displayName: 'Reviewer Patient',
    mobile: '9999900001',
    email: 'reviewer.patient@doctornect.test',
    collection: 'patients',
    profileData: {
      patientId: 'rev_pat_001',
      ownerUid: 'rev_fb_pat_001',
      name: 'Reviewer Patient',
      email: 'reviewer.patient@doctornect.test',
      mobile: '9999900001',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      shareRecordsWithDoctors: true,
    },
  },
  {
    role: 'doctor',
    profileId: 'rev_doc_001',
    firebaseUid: 'rev_fb_doc_001',
    displayName: 'Dr. Reviewer',
    mobile: '9999900002',
    email: 'reviewer.doctor@doctornect.test',
    collection: 'doctors',
    profileData: {
      doctorId: 'rev_doc_001',
      ownerUid: 'rev_fb_doc_001',
      displayName: 'Dr. Reviewer',
      email: 'reviewer.doctor@doctornect.test',
      mobile: '9999900002',
      specialization: 'General Medicine',
      qualification: 'MBBS, MD',
      experienceYears: 10,
      consultationFee: 500,
      councilReg: 'REV-MCI-99999',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'medicalStore',
    profileId: 'rev_store_001',
    firebaseUid: 'rev_fb_store_001',
    displayName: 'Reviewer Pharmacy',
    mobile: '9999900003',
    email: 'reviewer.pharmacy@doctornect.test',
    collection: 'medical_stores',
    profileData: {
      storeId: 'rev_store_001',
      ownerUid: 'rev_fb_store_001',
      storeName: 'Reviewer Pharmacy',
      ownerName: 'Reviewer Owner',
      email: 'reviewer.pharmacy@doctornect.test',
      mobile: '9999900003',
      drugLicenseNumber: 'REV-20B-99999',
      address: 'Shop 101, Medical Market, Review City',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'lab',
    profileId: 'rev_lab_001',
    firebaseUid: 'rev_fb_lab_001',
    displayName: 'Reviewer Diagnostics',
    mobile: '9999900004',
    email: 'reviewer.lab@doctornect.test',
    collection: 'labs',
    profileData: {
      labId: 'rev_lab_001',
      ownerUid: 'rev_fb_lab_001',
      labName: 'Reviewer Diagnostics',
      email: 'reviewer.lab@doctornect.test',
      mobile: '9999900004',
      licenseNumber: 'REV-NABL-99999',
      address: 'Diagnostic Complex, Sector 4, Review City',
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
  {
    role: 'ambulance',
    profileId: 'rev_amb_001',
    firebaseUid: 'rev_fb_amb_001',
    displayName: 'Reviewer Ambulance',
    mobile: '9999900005',
    email: 'reviewer.ambulance@doctornect.test',
    collection: 'ambulances',
    profileData: {
      ambulanceId: 'rev_amb_001',
      authUid: 'rev_fb_amb_001',
      driverName: 'Reviewer Driver',
      serviceName: 'Reviewer Emergency Ambulance',
      email: 'reviewer.ambulance@doctornect.test',
      mobile: '9999900005',
      vehicleNumber: 'DL-01-REV-108',
      ambulanceType: 'als',
      isAvailable: true,
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
    },
  },
];

function initializeAdminSdk() {
  const admin = require('firebase-admin');
  if (admin.apps.length > 0) return admin;

  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
    || path.join(__dirname, 'service-account.json');

  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } else {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT || 'doctornect-prod',
    });
  }
  return admin;
}

async function main() {
  console.log('================================================================');
  console.log('  SEED PLAY STORE / APP STORE REVIEWER ACCOUNTS (ADMIN SDK)    ');
  console.log('================================================================');
  console.log(`MODE: ${isDryRun ? 'DRY-RUN (Safe preview — NO WRITES)' : 'APPLY (WRITES ENABLED)'}`);
  console.log(`Accounts to seed: ${REVIEWER_ACCOUNTS.length}`);

  if (isDryRun) {
    console.log('\n[DRY RUN] Previewing operations for each reviewer account:');
    for (const acc of REVIEWER_ACCOUNTS) {
      console.log(`\n--- Role: ${acc.role.toUpperCase()} ---`);
      console.log(`  UID:               ${acc.firebaseUid}`);
      console.log(`  Profile ID:        ${acc.profileId}`);
      console.log(`  Mobile:            ${acc.mobile}`);
      console.log(`  Email:             ${acc.email}`);
      console.log(`  Firestore Paths:`);
      console.log(`    - profile_claims/${acc.profileId} (role: ${acc.role})`);
      console.log(`    - users/${acc.firebaseUid} (verified: true, status: 'approved', profileCompleted: true)`);
      console.log(`    - ${acc.collection}/${acc.profileId} (verified: true, status: 'approved')`);
      console.log(`  Auth Claims:       { role: '${acc.role}', verified: true }`);
    }

    console.log('\n================================================================');
    console.log('DRY RUN COMPLETE: 0 documents written, 0 auth users created.');
    console.log('To apply these changes, rerun with:');
    console.log('  node scripts/seed_reviewer_accounts.js --apply');
    console.log('================================================================');
    return;
  }

  // --- EXECUTION PATH (ONLY REACHED WITH --apply) ---
  console.log('\n[APPLY] Initializing Firebase Admin SDK...');
  const admin = initializeAdminSdk();
  const db = admin.firestore();
  const auth = admin.auth();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const acc of REVIEWER_ACCOUNTS) {
    console.log(`\nSeeding ${acc.role} (${acc.profileId})...`);

    // 1. Ensure Firebase Auth user exists
    let authUser;
    try {
      authUser = await auth.getUser(acc.firebaseUid);
      console.log(`  Found existing Auth user: ${authUser.uid}`);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        authUser = await auth.createUser({
          uid: acc.firebaseUid,
          email: acc.email,
          phoneNumber: `+91${acc.mobile}`,
          displayName: acc.displayName,
          emailVerified: true,
        });
        console.log(`  Created Auth user: ${authUser.uid}`);
      } else {
        throw err;
      }
    }

    // 2. Set Custom Claims
    await auth.setCustomUserClaims(acc.firebaseUid, {
      role: acc.role,
      verified: true,
      profileId: acc.profileId,
    });
    console.log(`  Set Custom Claims: role=${acc.role}, verified=true`);

    // 3. Write Firestore batch
    const batch = db.batch();

    // profile_claims
    const claimRef = db.collection('profile_claims').doc(acc.profileId);
    batch.set(claimRef, {
      uid: acc.firebaseUid,
      role: acc.role,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    // users/{uid}
    const userRef = db.collection('users').doc(acc.firebaseUid);
    batch.set(userRef, {
      role: acc.role,
      profileId: acc.profileId,
      displayName: acc.displayName,
      email: acc.email,
      mobile: acc.mobile,
      verified: true,
      status: 'approved',
      verificationStatus: 'verified',
      profileCompleted: true,
      deactivated: false,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    // domain profile
    const domainRef = db.collection(acc.collection).doc(acc.profileId);
    batch.set(domainRef, {
      ...acc.profileData,
      createdAt: now,
      updatedAt: now,
    }, { merge: true });

    await batch.commit();
    console.log(`  Committed Firestore docs for ${acc.role}`);
  }

  console.log('\n================================================================');
  console.log('APPLY COMPLETE: All 5 reviewer accounts successfully seeded.');
  console.log('================================================================');
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Fatal error seeding reviewer accounts:', err);
    process.exit(1);
  });
}

module.exports = {
  REVIEWER_ACCOUNTS,
  isDryRun,
};
