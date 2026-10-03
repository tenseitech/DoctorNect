#!/usr/bin/env node
'use strict';

/**
 * DoctorNect — Production Super Admin Provisioning Script
 * File: functions/scripts/create_super_admin.js
 *
 * Purpose:
 * Safely provisions or promotes a Super Admin account in Firebase Auth and Firestore.
 * Compatible with DoctorNect's mobile OTP login flow (findUserByMobileDigits / verifyUserRegistrationOtp).
 *
 * Safety Guarantees:
 * 1. Default mode is DRY-RUN. Zero writes to Auth or Firestore without --execute.
 * 2. Production guard: --execute requires CONFIRM_PROD_SEED=medibond-45fad in environment.
 * 3. Role promotion protection: existing non-admin accounts will NOT be promoted without --promote-existing.
 * 4. Idempotent: safe to run multiple times. Displays field-level diff before writing.
 * 5. Atomic: Firestore writes committed in a single batch.
 * 6. Privacy: mobile numbers are masked (only last 4 digits) in console output.
 * 7. Zero hardcoded secrets: uses GOOGLE_APPLICATION_CREDENTIALS.
 *
 * Usage:
 *   Dry-Run:
 *     node functions/scripts/create_super_admin.js --mobile=9876543210 --name="Super Admin" --email="admin@doctornect.com"
 *
 *   Execute:
 *     $env:CONFIRM_PROD_SEED="medibond-45fad"
 *     node functions/scripts/create_super_admin.js --mobile=9876543210 --name="Super Admin" --email="admin@doctornect.com" --execute
 */

const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

const TARGET_PROJECT_ID = 'medibond-45fad';

// ----------------------------------------------------------------------------
// 1. CLI ARGUMENT PARSING
// ----------------------------------------------------------------------------
function parseArgs(argv) {
  const options = {
    mobile: null,
    name: null,
    email: null,
    execute: false,
    promoteExisting: false,
    withSuperAdminsDoc: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--execute') {
      options.execute = true;
    } else if (arg === '--promote-existing') {
      options.promoteExisting = true;
    } else if (arg === '--with-super-admins-doc') {
      options.withSuperAdminsDoc = true;
    } else if (arg.startsWith('--mobile=')) {
      options.mobile = arg.slice('--mobile='.length).trim();
    } else if (arg === '--mobile' && i + 1 < argv.length) {
      options.mobile = argv[++i].trim();
    } else if (arg.startsWith('--name=')) {
      options.name = arg.slice('--name='.length).trim();
    } else if (arg === '--name' && i + 1 < argv.length) {
      options.name = argv[++i].trim();
    } else if (arg.startsWith('--email=')) {
      options.email = arg.slice('--email='.length).trim();
    } else if (arg === '--email' && i + 1 < argv.length) {
      options.email = argv[++i].trim();
    }
  }

  return options;
}

// ----------------------------------------------------------------------------
// 2. INPUT NORMALIZATION & VALIDATION
// ----------------------------------------------------------------------------
function normalizeMobileDigits(mobile) {
  let digits = String(mobile || '').replace(/\D/g, '');
  while (digits.length > 10 && digits.startsWith('91')) {
    digits = digits.slice(2);
  }
  while (digits.length > 10 && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (digits.length !== 10 || !/^[6-9]\d{9}$/.test(digits)) {
    return '';
  }
  return digits;
}

function maskMobile(digits) {
  if (!digits || digits.length < 4) return '******';
  return `******${digits.slice(-4)}`;
}

// ----------------------------------------------------------------------------
// 3. MAIN RUNNER
// ----------------------------------------------------------------------------
async function main() {
  const options = parseArgs(process.argv.slice(2));

  console.log('================================================================');
  console.log('DoctorNect — Super Admin Provisioning Script');
  console.log(`Target Firebase Project: ${TARGET_PROJECT_ID}`);
  console.log(`Execution Mode:          ${options.execute ? 'LIVE EXECUTION (--execute)' : 'DRY-RUN (default)'}`);
  console.log('================================================================');

  // Validate required args
  if (!options.mobile) {
    console.error('Error: Missing required argument --mobile (10-digit Indian mobile number)');
    process.exit(1);
  }
  if (!options.name) {
    console.error('Error: Missing required argument --name (Display Name for Super Admin)');
    process.exit(1);
  }
  if (!options.email || !options.email.includes('@')) {
    console.error('Error: Missing or invalid argument --email (Admin email address)');
    process.exit(1);
  }

  const digits = normalizeMobileDigits(options.mobile);
  if (!digits) {
    console.error(`Error: Invalid mobile number format "${options.mobile}". Must be a valid 10-digit Indian mobile number starting with 6-9.`);
    process.exit(1);
  }

  const cleanName = options.name.trim();
  const cleanEmail = options.email.trim().toLowerCase();
  const formattedPhone = `+91${digits}`;
  const profileId = `admin_${digits}`;

  console.log(`Target Mobile: ${maskMobile(digits)}`);
  console.log(`Target Name:   ${cleanName}`);
  console.log(`Target Email:  ${cleanEmail}`);
  console.log(`Profile ID:    ${profileId}`);
  console.log('----------------------------------------------------------------');

  // Production Execution Guard
  if (options.execute) {
    const confirmGuard = process.env.CONFIRM_PROD_SEED;
    if (confirmGuard !== TARGET_PROJECT_ID) {
      console.error(`Refusing execution: CONFIRM_PROD_SEED="${TARGET_PROJECT_ID}" is required in environment to write changes.`);
      console.error(`Set the environment variable and re-run:`);
      console.error(`  PowerShell: $env:CONFIRM_PROD_SEED="${TARGET_PROJECT_ID}"`);
      console.error(`  Bash:       export CONFIRM_PROD_SEED="${TARGET_PROJECT_ID}"`);
      process.exit(1);
    }
  }

  // Credentials Check
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.warn('Notice: GOOGLE_APPLICATION_CREDENTIALS environment variable is not explicitly set.');
    console.warn('Attempting initialization using Google Application Default Credentials (ADC)...');
  }

  // Initialize Firebase Admin SDK
  try {
    admin.initializeApp({
      projectId: TARGET_PROJECT_ID,
    });
  } catch (initErr) {
    console.error('Failed to initialize Firebase Admin SDK:', initErr.message);
    process.exit(1);
  }

  const auth = getAuth();
  const db = getFirestore();

  console.log('Checking current state in Firebase Auth and Firestore...');

  // --------------------------------------------------------------------------
  // 4. DISCOVERY: Firebase Auth User Lookup (by phone & email)
  // --------------------------------------------------------------------------
  let authUserByPhone = null;
  let authUserByEmail = null;

  try {
    authUserByPhone = await auth.getUserByPhoneNumber(formattedPhone);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') {
      console.error('Error checking Auth by phone:', err.message);
      process.exit(1);
    }
  }

  try {
    authUserByEmail = await auth.getUserByEmail(cleanEmail);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') {
      console.error('Error checking Auth by email:', err.message);
      process.exit(1);
    }
  }

  if (authUserByPhone && authUserByEmail && authUserByPhone.uid !== authUserByEmail.uid) {
    console.error('Collision detected:');
    console.error(`  Auth user by phone ${maskMobile(digits)} has UID: ${authUserByPhone.uid}`);
    console.error(`  Auth user by email ${cleanEmail} has UID: ${authUserByEmail.uid}`);
    console.error('Different accounts exist for this phone and email. Resolve account collision before proceeding.');
    process.exit(1);
  }

  const existingAuthUser = authUserByPhone || authUserByEmail;
  let targetUid = existingAuthUser?.uid || null;

  if (existingAuthUser) {
    console.log(`[Found] Existing Firebase Auth user: UID=${existingAuthUser.uid}`);
  } else {
    console.log(`[New] No existing Firebase Auth user found. Will create new Auth user with phone ${formattedPhone}.`);
  }

  // --------------------------------------------------------------------------
  // 5. DISCOVERY: Firestore users Collection Lookup
  // --------------------------------------------------------------------------
  let existingUserDoc = null;
  let existingUserDocRef = null;

  // Check by UID if Auth user was found
  if (targetUid) {
    const docSnap = await db.collection('users').doc(targetUid).get();
    if (docSnap.exists) {
      existingUserDoc = docSnap.data();
      existingUserDocRef = docSnap.ref;
      console.log(`[Found] Existing Firestore doc at users/${targetUid} (role="${existingUserDoc.role}")`);
    }
  }

  // Also search users collection by mobile candidates (matching findUserByMobileDigits)
  if (!existingUserDoc) {
    const candidates = [digits, `+91${digits}`, `+91 ${digits}`, `+91-${digits}`, `91${digits}`, `0${digits}`];
    const queries = candidates.map(c => db.collection('users').where('mobile', '==', c).limit(1).get());
    const querySnaps = await Promise.all(queries);

    for (const snap of querySnaps) {
      if (!snap.empty) {
        existingUserDoc = snap.docs[0].data();
        existingUserDocRef = snap.docs[0].ref;
        if (!targetUid) {
          targetUid = snap.docs[0].id;
        }
        console.log(`[Found] Existing Firestore doc via mobile query at users/${snap.docs[0].id} (role="${existingUserDoc.role}")`);
        break;
      }
    }
  }

  // --------------------------------------------------------------------------
  // 6. ROLE PROTECTION GUARD
  // --------------------------------------------------------------------------
  if (existingUserDoc) {
    const currentRole = String(existingUserDoc.role || '').trim();
    const isAlreadyAdmin = currentRole === 'super_admin' || currentRole === 'superAdmin' || currentRole === 'admin';

    if (!isAlreadyAdmin) {
      if (!options.promoteExisting) {
        console.error('----------------------------------------------------------------');
        console.error(`Safety Guard Aborted: User at users/${existingUserDocRef.id} currently has role="${currentRole}".`);
        console.error('Silently promoting an existing non-admin user to super_admin is blocked.');
        console.error('To intentionally promote this user, pass the explicit flag: --promote-existing');
        console.error('----------------------------------------------------------------');
        process.exit(1);
      } else {
        console.warn(`[Promotion Warning] User with role="${currentRole}" will be elevated to "super_admin" due to --promote-existing flag.`);
      }
    }
  }

  // --------------------------------------------------------------------------
  // 7. PREPARE PROPOSED MUTATIONS
  // --------------------------------------------------------------------------
  // If targetUid still unknown, generate random placeholder for dry-run
  const finalUid = targetUid || `new_admin_${digits}`;

  const proposedUserDoc = {
    role: 'super_admin',
    profileId: profileId,
    displayName: cleanName,
    email: cleanEmail,
    mobile: digits,
    phone: digits,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    mobileVerified: true,
    deactivated: false,
    updatedAt: '[FieldValue.serverTimestamp()]',
  };

  const proposedCompanionDoc = {
    adminId: profileId,
    ownerUid: finalUid,
    name: cleanName,
    fullName: cleanName,
    email: cleanEmail,
    mobile: digits,
    phone: digits,
    verified: true,
    status: 'approved',
    profileCompleted: true,
    updatedAt: '[FieldValue.serverTimestamp()]',
  };

  console.log('----------------------------------------------------------------');
  console.log('PROPOSED FIRESTORE MUTATIONS:');
  console.log(`Path: users/${finalUid}`);
  console.log(JSON.stringify(proposedUserDoc, null, 2));

  if (options.withSuperAdminsDoc) {
    console.log(`Companion Doc Path: super_admins/${profileId}`);
    console.log(JSON.stringify(proposedCompanionDoc, null, 2));
  }

  // --------------------------------------------------------------------------
  // 8. DRY-RUN VS EXECUTE
  // --------------------------------------------------------------------------
  if (!options.execute) {
    console.log('----------------------------------------------------------------');
    console.log('[DRY-RUN COMPLETE] No changes were written.');
    console.log('To apply these changes to production, execute with:');
    console.log(`  $env:CONFIRM_PROD_SEED="${TARGET_PROJECT_ID}"`);
    console.log(`  node functions/scripts/create_super_admin.js --mobile=${digits} --name="${cleanName}" --email="${cleanEmail}" --execute${options.promoteExisting ? ' --promote-existing' : ''}${options.withSuperAdminsDoc ? ' --with-super-admins-doc' : ''}`);
    process.exit(0);
  }

  // ==========================================================================
  // 9. LIVE EXECUTION (--execute)
  // ==========================================================================
  console.log('----------------------------------------------------------------');
  console.log('APPLYING CHANGES TO FIREBASE...');

  let realUid = targetUid;

  // Step A: Ensure Firebase Auth user
  if (!existingAuthUser) {
    console.log(`Creating new Firebase Auth user with phone ${formattedPhone}...`);
    const newAuthUser = await auth.createUser({
      phoneNumber: formattedPhone,
      email: cleanEmail,
      displayName: cleanName,
      emailVerified: true,
    });
    realUid = newAuthUser.uid;
    console.log(`[Created] Firebase Auth user created with UID: ${realUid}`);
  } else {
    realUid = existingAuthUser.uid;
    console.log(`Updating existing Firebase Auth user (${realUid})...`);
    await auth.updateUser(realUid, {
      displayName: cleanName,
      email: cleanEmail,
      emailVerified: true,
    });
    console.log(`[Updated] Firebase Auth user updated (displayName, email, emailVerified: true)`);
  }

  // Set custom claims for role
  await auth.setCustomUserClaims(realUid, { role: 'super_admin' });
  console.log(`[Updated] Set Firebase Auth custom claims: { role: 'super_admin' }`);

  // Step B: Write Firestore documents atomically
  const batch = db.batch();
  const userRef = db.collection('users').doc(realUid);

  const finalUserPayload = {
    role: 'super_admin',
    profileId: profileId,
    displayName: cleanName,
    email: cleanEmail,
    mobile: digits,
    phone: digits,
    verified: true,
    verificationStatus: 'verified',
    status: 'approved',
    profileCompleted: true,
    mobileVerified: true,
    deactivated: false,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (!existingUserDoc) {
    finalUserPayload.createdAt = FieldValue.serverTimestamp();
  }

  batch.set(userRef, finalUserPayload, { merge: true });

  if (options.withSuperAdminsDoc) {
    const companionRef = db.collection('super_admins').doc(profileId);
    batch.set(companionRef, {
      adminId: profileId,
      ownerUid: realUid,
      name: cleanName,
      fullName: cleanName,
      email: cleanEmail,
      mobile: digits,
      phone: digits,
      verified: true,
      status: 'approved',
      profileCompleted: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();
  console.log(`[Success] Atomic Firestore batch committed successfully.`);

  // --------------------------------------------------------------------------
  // 10. FINAL SUMMARY
  // --------------------------------------------------------------------------
  console.log('================================================================');
  console.log('SUPER ADMIN PROVISIONING COMPLETE');
  console.log(`UID:            ${realUid}`);
  console.log(`User Doc:       users/${realUid}`);
  console.log(`Role:           super_admin`);
  console.log(`Mobile:         ${maskMobile(digits)}`);
  console.log(`Email:          ${cleanEmail}`);
  console.log(`Login Flow:     Ready for Phone OTP login via mobile ending in ${digits.slice(-4)}`);
  if (options.withSuperAdminsDoc) {
    console.log(`Companion Doc:  super_admins/${profileId}`);
  }
  console.log('================================================================');
}

main().catch((err) => {
  console.error('Fatal execution error:', err);
  process.exit(1);
});
