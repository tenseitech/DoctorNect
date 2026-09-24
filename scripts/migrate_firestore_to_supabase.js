/**
 * DoctorNect: Production Firestore → Supabase PostgreSQL Migration Script
 * Usage:
 *   node scripts/migrate_firestore_to_supabase.js --dry-run
 *   node scripts/migrate_firestore_to_supabase.js --live
 *   node scripts/migrate_firestore_to_supabase.js --live --role=doctor
 *   node scripts/migrate_firestore_to_supabase.js --dry-run --verbose
 */

require('./load_env').loadEnv();

const admin = require('firebase-admin');
const { createClient } = require('@supabase/supabase-js');
const { Client } = require('pg');
const { v5: uuidv5 } = require('uuid');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Fixed UUID namespace for DoctorNect deterministic UUID v5 generation
const DOCTORNECT_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

// Demo accounts metadata (Google Play Store review accounts)
const DEMO_PHONES = {
  patient: '7058809803',
  doctor: '7666892394',
  medicalStore: '9359503874',
  lab: '9409858233',
  ambulance: '9307583929',
};

// Parse CLI flags
const args = process.argv.slice(2);
const IS_DRY_RUN = !args.includes('--live');
const VERBOSE = args.includes('--verbose');
const TARGET_ROLE = args.find((a) => a.startsWith('--role='))?.split('=')[1];
const sinceArg = args.find((a) => a.startsWith('--since='));
const SINCE_TIMESTAMP = sinceArg ? new Date(sinceArg.split('=')[1]) : null;

console.log('================================================================');
console.log(`DOCTORNECT DATA MIGRATION: FIRESTORE -> SUPABASE POSTGRESQL`);
console.log(`MODE: ${IS_DRY_RUN ? 'DRY-RUN (Simulation only — zero DB mutations)' : '*** LIVE MIGRATION ***'}`);
if (TARGET_ROLE) console.log(`FILTER: Target Role = ${TARGET_ROLE}`);
if (SINCE_TIMESTAMP) console.log(`FILTER: Delta Since = ${SINCE_TIMESTAMP.toISOString()}`);
console.log('================================================================\n');

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  const candidateSaPaths = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, 'service-account.json'),
    path.join(__dirname, 'serviceAccountKey.json'),
    path.join(process.cwd(), 'service-account.json'),
    path.join(process.cwd(), 'scripts', 'service-account.json'),
  ];
  const saPath = candidateSaPaths.find((p) => p && fs.existsSync(p));
  if (saPath) {
    const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
    });
  } else {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
    });
  }
}
const firestore = admin.firestore();

// Initialize Supabase Admin & Direct Postgres Client
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const postgresUrl = process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;

if (!IS_DRY_RUN && (!supabaseUrl || !supabaseServiceKey || !postgresUrl)) {
  console.error('FATAL: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and SUPABASE_DB_URL must be set for live migration.');
  process.exit(1);
}

const supabaseAdmin = (supabaseUrl && supabaseServiceKey)
  ? createClient(supabaseUrl, supabaseServiceKey, { auth: { autoRefreshToken: false, persistSession: false } })
  : null;

const pgClient = postgresUrl ? new Client({ connectionString: postgresUrl, ssl: { rejectUnauthorized: false } }) : null;

// Helper: Convert Firestore Timestamp to ISO string
function toIso(val) {
  if (!val) return null;
  if (val.toDate && typeof val.toDate === 'function') return val.toDate().toISOString();
  if (val instanceof Date) return val.toISOString();
  if (typeof val === 'string') return new Date(val).toISOString();
  return null;
}

// Helper: Deterministic User UUID from Firebase UID
function toUserUuid(firebaseUid) {
  if (!firebaseUid) return null;
  return uuidv5(String(firebaseUid), DOCTORNECT_NAMESPACE);
}

// In-Memory ID Tracking for Referential Integrity Validation
const knownIds = {
  users: new Set(),
  doctors: new Set(),
  patients: new Set(),
  medicalStores: new Set(),
  labs: new Set(),
  ambulances: new Set(),
  appointments: new Set(),
};

// Detailed stats tracker
const stats = {
  scanned: {},
  valid: {},
  warnings: {},
  skipped: {},
  errors: {},
};
const warningDetails = [];

function recordStat(collection, status, detailMsg = null) {
  stats[status][collection] = (stats[status][collection] || 0) + 1;
  if (detailMsg && (status === 'warnings' || status === 'errors')) {
    warningDetails.push(`[${collection.toUpperCase()}] ${detailMsg}`);
    if (VERBOSE) console.warn(`  ⚠️  [${collection}] ${detailMsg}`);
  }
}

// ----------------------------------------------------------------------------
// MIGRATION WORKERS PER DOMAIN
// ----------------------------------------------------------------------------

async function migrateSystemConfig() {
  process.stdout.write('-> Migrating System Configuration... ');
  let snap;
  try {
    snap = await firestore.collection('system_config').get();
  } catch (err) {
    console.log(`[Collection not found or empty: ${err.message}]`);
    snap = { docs: [], size: 0 };
  }
  stats.scanned['system_config'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO system_config (config_key, config_value, updated_at)
         VALUES ($1, $2, $3)
         ON CONFLICT (config_key) DO UPDATE SET config_value = $2, updated_at = $3`,
        [doc.id, JSON.stringify(data), toIso(data.updatedAt) || new Date().toISOString()]
      );
    }
    recordStat('system_config', 'valid');
  }

  // Ensure Demo Accounts config is guaranteed
  if (!IS_DRY_RUN) {
    await pgClient.query(
      `INSERT INTO system_config (config_key, config_value)
       VALUES ('demo_accounts', $1)
       ON CONFLICT (config_key) DO UPDATE SET config_value = $1`,
      [JSON.stringify({
        demoOtp: '000000',
        demoPhones: {
          patient: [DEMO_PHONES.patient],
          doctor: [DEMO_PHONES.doctor],
          medicalStore: [DEMO_PHONES.medicalStore],
          lab: [DEMO_PHONES.lab],
          ambulance: [DEMO_PHONES.ambulance],
        }
      })]
    );
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['system_config'] || 0}`);
}

async function migrateUsers() {
  process.stdout.write('-> Migrating Users & Auth Identity... ');
  let query = firestore.collection('users');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['users'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const firebaseUid = doc.id;
    knownIds.users.add(firebaseUid);

    const userUuid = toUserUuid(firebaseUid);
    const email = data.email || `${data.mobile || firebaseUid}@signup.doctornect.app`;
    const role = data.role || 'patient';
    const isDemo = Object.values(DEMO_PHONES).includes(data.mobile);

    if (TARGET_ROLE && role !== TARGET_ROLE) {
      recordStat('users', 'skipped');
      continue;
    }

    if (!data.mobile && !data.email) {
      recordStat('users', 'warnings', `User ${firebaseUid} has neither email nor mobile`);
    }

    if (!IS_DRY_RUN) {
      // 1. Sync Supabase Auth User
      const { error: authErr } = await supabaseAdmin.auth.admin.createUser({
        id: userUuid,
        email: email.toLowerCase(),
        phone: data.mobile ? `+91${data.mobile}` : undefined,
        email_confirm: true,
        phone_confirm: true,
        user_metadata: {
          firebase_uid: firebaseUid,
          role: role,
          profile_id: data.profileId,
        },
      });

      if (authErr && !authErr.message.includes('already exists') && !authErr.message.includes('duplicate')) {
        console.error(`Auth user creation failed for ${firebaseUid}:`, authErr.message);
        recordStat('users', 'errors', `Auth create error for ${firebaseUid}: ${authErr.message}`);
        continue;
      }

      // 2. Insert into public.users
      await pgClient.query(
        `INSERT INTO users (
            id, firebase_uid, role, profile_id, display_name, email, mobile,
            profile_completed, verified, verified_at, deactivated, status, photo_url,
            created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         ON CONFLICT (id) DO UPDATE SET
            display_name = $5, mobile = $7, profile_completed = $8,
            verified = $9, status = $12, updated_at = $15`,
        [
          userUuid,
          firebaseUid,
          role,
          data.profileId || `prof_${firebaseUid}`,
          data.displayName || data.name || 'User',
          email.toLowerCase(),
          data.mobile || null,
          role === 'patient' || isDemo || data.profileCompleted === true,
          isDemo || data.verified === true,
          toIso(data.verifiedAt),
          data.deactivated === true,
          data.status || 'approved',
          data.photoUrl || null,
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('users', 'valid');
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['users'] || 0} | Skipped: ${stats.skipped['users'] || 0}`);
}

async function migrateDoctors() {
  process.stdout.write('-> Migrating Doctors & Schedules... ');
  let query = firestore.collection('doctors');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['doctors'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const doctorId = doc.id;
    knownIds.doctors.add(doctorId);

    if (data.ownerUid && !knownIds.users.has(data.ownerUid)) {
      recordStat('doctors', 'warnings', `Doctor '${doctorId}' references ownerUid '${data.ownerUid}' not found in users collection`);
    }

    const ownerUuid = toUserUuid(data.ownerUid);
    const isDemo = data.mobile === DEMO_PHONES.doctor;

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO doctors (
            doctor_id, owner_uid, name, email, mobile, specialization, super_specialization,
            qualification, experience_years, consultation_fee, clinic_name, area, city, state,
            pincode, address_line1, state_council, council_number, about, languages, photo_url,
            maps_link, landmark, rating, review_count, profile_completed, verified, verified_at,
            created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30)
         ON CONFLICT (doctor_id) DO UPDATE SET
            name = $3, consultation_fee = $10, clinic_name = $11, rating = $24,
            review_count = $25, verified = $27, updated_at = $30`,
        [
          doctorId,
          ownerUuid,
          data.name || data.fullName || 'Doctor',
          (data.email || `${doctorId}@doctornect.com`).toLowerCase(),
          data.mobile || data.phone || '0000000000',
          data.specialization || 'General Physician',
          data.superSpecialization || null,
          data.qualification || 'MBBS',
          parseInt(data.experienceYears || 1, 10),
          parseFloat(data.consultationFee || 0.0),
          data.clinicName || null,
          data.area || null,
          data.city || 'Mumbai',
          data.state || 'Maharashtra',
          data.pincode || null,
          data.addressLine1 || null,
          data.stateCouncil || null,
          data.councilNumber || null,
          data.about || null,
          data.languages || ['English', 'Hindi'],
          data.photoUrl || null,
          data.mapsLink || null,
          data.landmark || null,
          parseFloat(data.rating || 0.0),
          parseInt(data.reviewCount || 0, 10),
          isDemo || data.profileCompleted === true,
          isDemo || data.verified === true,
          toIso(data.verifiedAt),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('doctors', 'valid');
  }

  // Doctor Availability
  let availSnap;
  try {
    availSnap = await firestore.collection('doctor_availability').get();
  } catch (_) {
    availSnap = { docs: [], size: 0 };
  }
  stats.scanned['doctor_availability'] = availSnap.size;
  for (const doc of availSnap.docs) {
    const data = doc.data();
    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO doctor_availability (
            doctor_id, working_days, morning_start, morning_end, evening_enabled,
            evening_start, evening_end, slot_duration_mins, max_patients_per_day,
            break_enabled, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (doctor_id) DO UPDATE SET
            working_days = $2, morning_start = $3, morning_end = $4,
            evening_start = $6, evening_end = $7, updated_at = $11`,
        [
          doc.id,
          data.workingDays || ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          data.morningStart || '09:00 AM',
          data.morningEnd || '01:00 PM',
          data.eveningEnabled !== false,
          data.eveningStart || '04:00 PM',
          data.eveningEnd || '08:00 PM',
          parseInt(data.slotDurationMins || 15, 10),
          parseInt(data.maxPatientsPerDay || 20, 10),
          data.breakEnabled === true,
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('doctor_availability', 'valid');
  }
  // Auto-insert Deactivated Legacy Doctors for historical appointments & prescriptions
  const LEGACY_DOCTORS = [
    { id: 'd1783603413832', name: 'Dr. Vedant Nandanwar (Legacy)', specialization: 'General Physician' },
    { id: 'd1783677686848', name: 'Dr. Khijendra Dighore (Legacy)', specialization: 'Internal Medicine' },
    { id: 'd1783863920949', name: 'Dr. Rohit K Chunarkar (Legacy)', specialization: 'General Physician' },
    { id: 'd1784185736978', name: 'Dr. Rochdoctwo (Legacy)', specialization: 'General Physician' },
  ];
  for (const legDoc of LEGACY_DOCTORS) {
    knownIds.doctors.add(legDoc.id);
    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO doctors (
            doctor_id, owner_uid, name, email, mobile, specialization,
            qualification, experience_years, consultation_fee, clinic_name, city, state,
            about, languages, rating, review_count, profile_completed, verified, deactivated,
            created_at, updated_at
         )
         VALUES ($1, NULL, $2, $3, '0000000000', $4, 'MBBS', 1, 0.0, 'Archived Clinic', 'Nagpur', 'Maharashtra',
                 'Archived legacy doctor profile retained for historical patient records', ARRAY['English', 'Hindi'], 0.0, 0, false, false, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT (doctor_id) DO NOTHING`,
        [legDoc.id, legDoc.name, `${legDoc.id}@legacy.doctornect.app`, legDoc.specialization]
      );
    }
  }


  console.log(`Scanned: ${snap.size} | Valid Doctors: ${stats.valid['doctors'] || 0} | Schedules: ${stats.valid['doctor_availability'] || 0}`);
}

async function migratePatients() {
  process.stdout.write('-> Migrating Patients & Family Health Records... ');
  let query = firestore.collection('patients');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['patients'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const patientId = doc.id;
    knownIds.patients.add(patientId);

    if (data.ownerUid && !knownIds.users.has(data.ownerUid)) {
      // Auto-synthesize missing user for registered patient
      knownIds.users.add(data.ownerUid);
      if (!IS_DRY_RUN) {
        const synthEmail = data.email || `${data.ownerUid}@signup.doctornect.app`;
        const synthMobile = data.mobile;
        await supabaseAdmin.auth.admin.createUser({
          id: ownerUuid,
          email: synthEmail.toLowerCase(),
          phone: synthMobile ? (synthMobile.startsWith('+') ? synthMobile : `+91${synthMobile}`) : undefined,
          email_confirm: true,
          phone_confirm: true,
          user_metadata: {
            firebase_uid: data.ownerUid,
            role: 'patient',
            profile_id: patientId,
          },
        }).catch(() => {});

        await pgClient.query(
          `INSERT INTO users (
              id, firebase_uid, role, profile_id, display_name, email, mobile,
              profile_completed, verified, status, created_at, updated_at
           )
           VALUES ($1, $2, 'patient', $3, $4, $5, $6, TRUE, TRUE, 'approved', $7, $8)
           ON CONFLICT (id) DO UPDATE SET display_name = $4, mobile = $6, updated_at = $8`,
          [
            ownerUuid,
            data.ownerUid,
            patientId,
            data.name || 'Patient',
            synthEmail.toLowerCase(),
            synthMobile || null,
            toIso(data.createdAt) || new Date().toISOString(),
            toIso(data.updatedAt) || new Date().toISOString(),
          ]
        );
      }
    }

    const ownerUuid = toUserUuid(data.ownerUid);

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO patients (
            patient_id, owner_uid, name, email, mobile, age, gender, blood_group,
            height, weight, address, photo_url, share_records_with_doctors,
            primary_doctor_id, care_team_doctor_ids, profile_completed, verified,
            created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
         ON CONFLICT (patient_id) DO UPDATE SET
            name = $3, mobile = $5, share_records_with_doctors = $13,
            care_team_doctor_ids = $15, updated_at = $19`,
        [
          patientId,
          ownerUuid,
          data.name || 'Patient',
          data.email || null,
          data.mobile || '0000000000',
          parseInt(data.age || 0, 10) || null,
          data.gender || 'Other',
          data.bloodGroup || null,
          data.height || null,
          data.weight || null,
          data.address || null,
          data.photoUrl || null,
          data.shareRecordsWithDoctors !== false,
          data.primaryDoctorId || null,
          data.careTeamDoctorIds || [],
          true,
          true,
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );

      // Subcollection: doctor_links
      const linksSnap = await doc.ref.collection('doctor_links').get();
      for (const linkDoc of linksSnap.docs) {
        const linkData = linkDoc.data();
        await pgClient.query(
          `INSERT INTO patient_doctor_links (patient_id, doctor_id, source, from_doctor_id, referral_id, created_at)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (patient_id, doctor_id) DO NOTHING`,
          [
            patientId,
            linkDoc.id,
            linkData.source || 'appointment',
            linkData.fromDoctorId || null,
            linkData.referralId || null,
            toIso(linkData.createdAt) || new Date().toISOString(),
          ]
        );
      }
    }
    recordStat('patients', 'valid');
  }

  // Family Members
  let famSnap;
  try {
    famSnap = await firestore.collectionGroup('family_members').get();
  } catch (_) {
    famSnap = { docs: [], size: 0 };
  }
  stats.scanned['family_members'] = famSnap.size;

  for (const doc of famSnap.docs) {
    const data = doc.data();
    const patientId = doc.ref.parent.parent ? doc.ref.parent.parent.id : data.patientId;
    if (!patientId || !knownIds.patients.has(patientId)) {
      recordStat('family_members', 'warnings', `Family member '${doc.id}' references missing parent patientId '${patientId}'`);
    }

    if (!IS_DRY_RUN && patientId) {
      await pgClient.query(
        `INSERT INTO family_members (
            member_id, patient_id, name, relation, age, gender, blood_group,
            allergies, conditions, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (member_id) DO UPDATE SET name = $3, age = $5, updated_at = $11`,
        [
          doc.id,
          patientId,
          data.name || 'Dependent',
          (data.relation || 'other').toLowerCase(),
          parseInt(data.age || 0, 10),
          data.gender || 'Other',
          data.bloodGroup || null,
          data.allergies || [],
          data.conditions || [],
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('family_members', 'valid');
  }

  // Auto-insert Walk-In Patient Stubs (offline clinic patients with wi... IDs)
  let appSnapForWalkins;
  try {
    appSnapForWalkins = await firestore.collection('appointments').get();
  } catch (_) {
    appSnapForWalkins = { docs: [] };
  }
  for (const appDoc of appSnapForWalkins.docs) {
    const appData = appDoc.data();
    const pId = appData.patientId;
    if (pId && !knownIds.patients.has(pId)) {
      knownIds.patients.add(pId);
      if (!IS_DRY_RUN) {
        await pgClient.query(
          `INSERT INTO patients (
              patient_id, owner_uid, name, mobile, age, gender,
              share_records_with_doctors, profile_completed, verified, created_at, updated_at
           )
           VALUES ($1, NULL, $2, $3, $4, $5, TRUE, FALSE, FALSE, $6, $6)
           ON CONFLICT (patient_id) DO NOTHING`,
          [
            pId,
            appData.patientName || 'Walk-in Patient',
            appData.contactNumber || '0000000000',
            parseInt(appData.patientAge || 0, 10) || null,
            appData.patientGender === 'M' ? 'Male' : (appData.patientGender === 'F' ? 'Female' : (appData.patientGender || 'Other')),
            toIso(appData.dateTime) || new Date().toISOString(),
          ]
        );
      }
    }
  }

  console.log(`Scanned: ${snap.size} | Valid Patients: ${stats.valid['patients'] || 0} | Family Members: ${stats.valid['family_members'] || 0}`);
}

async function migrateMedicalStores() {
  process.stdout.write('-> Migrating Medical Stores / Pharmacies... ');
  let query = firestore.collection('medical_stores');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['medical_stores'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const storeId = doc.id;
    knownIds.medicalStores.add(storeId);

    if (data.ownerUid && !knownIds.users.has(data.ownerUid)) {
      recordStat('medical_stores', 'warnings', `Medical Store '${storeId}' references ownerUid '${data.ownerUid}' not found in users`);
    }

    const ownerUuid = toUserUuid(data.ownerUid);
    const isDemo = data.phone === DEMO_PHONES.medicalStore || data.mobile === DEMO_PHONES.medicalStore;

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO medical_stores (
            store_id, owner_uid, store_name, owner_name, drug_license_number, phone,
            email, gst_number, address_line1, city, state, pincode, profile_completed,
            verified, verified_at, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
         ON CONFLICT (store_id) DO UPDATE SET store_name = $3, verified = $14, updated_at = $17`,
        [
          storeId,
          ownerUuid,
          data.storeName || data.name || 'Medical Store',
          data.ownerName || 'Owner',
          data.drugLicenseNumber || 'DL-PENDING',
          data.phone || data.mobile || '0000000000',
          data.email || `${doc.id}@doctornect.com`,
          data.gstNumber || null,
          data.addressLine1 || data.address || null,
          data.city || 'Mumbai',
          data.state || 'Maharashtra',
          data.pincode || null,
          isDemo || data.profileCompleted === true,
          isDemo || data.verified === true,
          toIso(data.verifiedAt),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('medical_stores', 'valid');
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['medical_stores'] || 0}`);
}

async function migrateLabs() {
  process.stdout.write('-> Migrating Diagnostic Laboratories... ');
  let query = firestore.collection('labs');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['labs'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const labId = doc.id;
    knownIds.labs.add(labId);

    if (data.ownerUid && !knownIds.users.has(data.ownerUid)) {
      recordStat('labs', 'warnings', `Lab '${labId}' references ownerUid '${data.ownerUid}' not found in users`);
    }

    const ownerUuid = toUserUuid(data.ownerUid);
    const isDemo = data.phone === DEMO_PHONES.lab || data.mobile === DEMO_PHONES.lab;

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO labs (
            lab_id, owner_uid, lab_name, license_number, phone, email, gst_number,
            rating, city, state, pincode, profile_completed, verified, verified_at,
            created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
         ON CONFLICT (lab_id) DO UPDATE SET lab_name = $3, verified = $13, updated_at = $16`,
        [
          labId,
          ownerUuid,
          data.labName || data.name || 'Diagnostic Lab',
          data.licenseNumber || 'LAB-PENDING',
          data.phone || data.mobile || '0000000000',
          data.email || `${doc.id}@doctornect.com`,
          data.gstNumber || null,
          parseFloat(data.rating || 0.0),
          data.city || 'Mumbai',
          data.state || 'Maharashtra',
          data.pincode || null,
          isDemo || data.profileCompleted === true,
          isDemo || data.verified === true,
          toIso(data.verifiedAt),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('labs', 'valid');
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['labs'] || 0}`);
}

async function migrateAmbulances() {
  process.stdout.write('-> Migrating Ambulance Fleet... ');
  let query = firestore.collection('ambulances');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['ambulances'] = snap.size;

  const EXCLUDED_AMBULANCE_IDS = new Set([
    'smoke-test-amb-driver',
    'amb-reg-1784185219830', // July 16 test cluster (dummy license kjhkjhjkhjkhkj, phone 8282828282)
    'amb-reg-1784187441893', // July 16 test cluster (dummy license Ma123, phone 8555555555)
    'amb-reg-1784186572181', // July 16 test cluster (rochambone)
    'amb-reg-1784185203509', // July 16 test cluster (kk, dummy license LIC645135)
    'amb-reg-1786516801770', // Aug 12 throwaway test (dummy keyboard-mash license, invalid 7-digit pincode)
  ]);

  for (const doc of snap.docs) {
    const data = doc.data();
    const ambulanceId = doc.id;

    if (EXCLUDED_AMBULANCE_IDS.has(ambulanceId)) {
      recordStat('ambulances', 'skipped');
      continue;
    }

    knownIds.ambulances.add(ambulanceId);

    const authUuid = toUserUuid(data.authUid);
    const isDemo = data.phone === DEMO_PHONES.ambulance || data.mobile === DEMO_PHONES.ambulance;

    if (data.authUid && !knownIds.users.has(data.authUid)) {
      // Auto-synthesize missing user for legitimate ambulance driver
      knownIds.users.add(data.authUid);
      if (!IS_DRY_RUN) {
        const synthEmail = `${data.username || ambulanceId}@ambulance.doctornect.app`;
        const phone = data.phone || data.mobile;
        await supabaseAdmin.auth.admin.createUser({
          id: authUuid,
          email: synthEmail.toLowerCase(),
          phone: phone ? (phone.startsWith('+') ? phone : `+91${phone}`) : undefined,
          email_confirm: true,
          phone_confirm: true,
          user_metadata: {
            firebase_uid: data.authUid,
            role: 'ambulance',
            profile_id: ambulanceId,
          },
        }).catch(() => {});

        await pgClient.query(
          `INSERT INTO users (
              id, firebase_uid, role, profile_id, display_name, email, mobile,
              profile_completed, verified, status, created_at, updated_at
           )
           VALUES ($1, $2, 'ambulance', $3, $4, $5, $6, TRUE, TRUE, 'approved', $7, $8)
           ON CONFLICT (id) DO UPDATE SET display_name = $4, mobile = $6, updated_at = $8`,
          [
            authUuid,
            data.authUid,
            ambulanceId,
            data.driverName || data.serviceName || 'Ambulance Driver',
            synthEmail.toLowerCase(),
            phone || null,
            toIso(data.createdAt) || new Date().toISOString(),
            toIso(data.updatedAt) || new Date().toISOString(),
          ]
        );
      }
    }

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO ambulances (
            ambulance_id, auth_uid, service_name, owner_name, driver_name, phone,
            vehicle_number, ambulance_type, username, city, base_address, has_oxygen,
            has_ventilator, has_stretcher, is_24x7, rate_per_km, total_rating,
            is_available, profile_completed, verified, verified_at, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23)
         ON CONFLICT (ambulance_id) DO UPDATE SET
            service_name = $3, driver_name = $5, is_available = $18, verified = $20, updated_at = $23`,
        [
          ambulanceId,
          authUuid,
          data.serviceName || 'Ambulance Service',
          data.ownerName || null,
          data.driverName || 'Driver',
          data.phone || data.mobile || '0000000000',
          data.vehicleNumber || 'MH-01-AB-0000',
          data.ambulanceType || 'bls',
          data.username || `amb_${ambulanceId}`,
          data.city || 'Mumbai',
          data.baseAddress || null,
          data.hasOxygen === true,
          data.hasVentilator === true,
          data.hasStretcher !== false,
          data.is24x7 === true,
          parseFloat(data.ratePerKm || 0.0),
          parseFloat(data.rating || 0.0),
          data.isAvailable !== false,
          isDemo || data.profileCompleted === true,
          isDemo || data.verified === true,
          toIso(data.verifiedAt),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );

      // Ambulance Private Settings (PIN Hash)
      if (data.pinHash) {
        await pgClient.query(
          `INSERT INTO ambulance_private_settings (ambulance_id, pin_hash, fcm_token, updated_at)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (ambulance_id) DO UPDATE SET pin_hash = $2, fcm_token = $3, updated_at = $4`,
          [
            ambulanceId,
            data.pinHash,
            data.fcmToken || null,
            toIso(data.updatedAt) || new Date().toISOString(),
          ]
        );
      } else if (isDemo) {
        // Pre-seed 0000 PIN hash for review account
        const demoPinHash = crypto.createHash('sha256').update('0000').digest('hex');
        await pgClient.query(
          `INSERT INTO ambulance_private_settings (ambulance_id, pin_hash, updated_at)
           VALUES ($1, $2, CURRENT_TIMESTAMP)
           ON CONFLICT (ambulance_id) DO NOTHING`,
          [ambulanceId, demoPinHash]
        );
      }
    }
    recordStat('ambulances', 'valid');
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['ambulances'] || 0}`);
}

async function migrateAppointments() {
  process.stdout.write('-> Migrating Consultations & Appointments... ');
  let query = firestore.collection('appointments');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['appointments'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const aptId = doc.id;
    knownIds.appointments.add(aptId);
    let hasFkError = false;

    if (data.doctorId && !knownIds.doctors.has(data.doctorId)) {
      recordStat('appointments', 'warnings', `Appointment '${aptId}' references unknown doctorId '${data.doctorId}'`);
      hasFkError = true;
    }
    if (data.patientId && !knownIds.patients.has(data.patientId)) {
      recordStat('appointments', 'warnings', `Appointment '${aptId}' references unknown patientId '${data.patientId}'`);
      hasFkError = true;
    }

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO appointments (
            appointment_id, doctor_id, patient_id, doctor_name, doctor_specialization,
            patient_name, patient_age, patient_gender, appointment_date, time_slot,
            token_number, consultation_type, patient_status, doctor_status, clinic_name,
            cancellation_reason, diagnosis, has_prescription, has_report, has_review,
            review_rating, review_id, contact_number, source, chief_complaints,
            symptoms, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28)
         ON CONFLICT (appointment_id) DO UPDATE SET
            patient_status = $13, doctor_status = $14, diagnosis = $17, updated_at = $28`,
        [
          aptId,
          data.doctorId,
          data.patientId,
          data.doctorName || 'Doctor',
          data.specialization || 'Physician',
          data.patientName || 'Patient',
          parseInt(data.patientAge || 0, 10),
          data.patientGender || 'Other',
          toIso(data.dateTime) || new Date().toISOString(),
          data.slotLabel || '10:00 AM',
          parseInt(data.tokenNumber || 1, 10),
          data.visitType || 'newVisit',
          data.patientStatus || 'confirmed',
          data.doctorStatus || 'confirmed',
          data.clinicName || null,
          data.cancellationReason || null,
          data.diagnosis || null,
          data.hasPrescription === true,
          data.hasReport === true,
          data.hasReview === true,
          data.reviewRating ? parseInt(data.reviewRating, 10) : null,
          data.reviewId || null,
          data.contactNumber || null,
          data.source || 'app',
          data.chiefComplaints || [],
          data.symptoms || [],
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    if (!hasFkError) {
      recordStat('appointments', 'valid');
    }
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['appointments'] || 0} | FK Warnings: ${stats.warnings['appointments'] || 0}`);
}

async function migratePrescriptions() {
  process.stdout.write('-> Migrating Prescriptions & Regimens... ');
  let query = firestore.collection('prescriptions');
  if (SINCE_TIMESTAMP) query = query.where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(SINCE_TIMESTAMP));
  const snap = await query.get();
  stats.scanned['prescriptions'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    const prescId = doc.id;
    let hasFkError = false;

    if (data.doctorId && !knownIds.doctors.has(data.doctorId)) {
      recordStat('prescriptions', 'warnings', `Prescription '${prescId}' references unknown doctorId '${data.doctorId}'`);
      hasFkError = true;
    }
    if (data.patientId && !knownIds.patients.has(data.patientId)) {
      recordStat('prescriptions', 'warnings', `Prescription '${prescId}' references unknown patientId '${data.patientId}'`);
      hasFkError = true;
    }

    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO prescriptions (
            prescription_id, doctor_id, patient_id, appointment_id, doctor_name,
            doctor_specialization, clinic_name, patient_name, patient_age,
            patient_gender, prescription_date, diagnosis_type, primary_diagnosis,
            chief_complaint, symptoms, general_advice, diet_advice, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
         ON CONFLICT (prescription_id) DO UPDATE SET primary_diagnosis = $13, updated_at = $19`,
        [
          prescId,
          data.doctorId,
          data.patientId,
          data.appointmentId && knownIds.appointments.has(data.appointmentId) ? data.appointmentId : null,
          data.doctorName || null,
          data.doctorSpecialization || null,
          data.clinicName || null,
          data.patientName || 'Patient',
          parseInt(data.patientAge || 0, 10),
          data.patientGender || null,
          toIso(data.prescriptionDate) || new Date().toISOString(),
          data.diagnosisType || 'Provisional',
          data.primaryDiagnosis || null,
          data.chiefComplaint || null,
          data.symptoms || null,
          data.generalAdvice || (data.advice ? data.advice.general : null),
          data.dietAdvice || (data.advice ? data.advice.diet : null),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );

      // Line items: Medicines
      if (Array.isArray(data.medicines)) {
        for (const med of data.medicines) {
          await pgClient.query(
            `INSERT INTO prescription_medicines (
                prescription_id, medicine_entry_id, name, dosage, form,
                frequency, quantity, duration, instructions, is_sos
             )
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
            [
              prescId,
              med.id || crypto.randomUUID(),
              med.name || 'Medicine',
              med.dosage || '1 tab',
              med.form || 'Tablet',
              med.frequency || '1-0-1',
              med.quantity || '10',
              med.duration || '5 days',
              med.instructions || 'After meals',
              med.isSos === true,
            ]
          );
        }
      }
    }
    if (!hasFkError) {
      recordStat('prescriptions', 'valid');
    }
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['prescriptions'] || 0} | FK Warnings: ${stats.warnings['prescriptions'] || 0}`);
}

async function migratePromotedAds() {
  process.stdout.write('-> Migrating Promoted Ads & Campaigns... ');
  let snap;
  try {
    snap = await firestore.collection('promotedAds').get();
  } catch (_) {
    snap = { docs: [], size: 0 };
  }
  stats.scanned['promoted_ads'] = snap.size;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!IS_DRY_RUN) {
      await pgClient.query(
        `INSERT INTO promoted_ads (
            ad_id, provider_type, provider_id, title, description, image_url,
            cta_label, duration_hours, amount_paid, target_city, razorpay_order_id,
            razorpay_payment_id, payment_status, status, start_time, end_time,
            created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
         ON CONFLICT (ad_id) DO UPDATE SET status = $14, payment_status = $13, updated_at = $18`,
        [
          doc.id,
          data.providerType || 'doctor',
          data.providerId || 'system',
          data.title || 'Promoted Ad',
          data.description || '',
          data.imageUrl || '',
          data.ctaLabel || 'View Details',
          parseInt(data.durationHours || 24, 10),
          parseFloat(data.amountPaid || 300.0),
          data.targetCity || null,
          data.razorpayOrderId || null,
          data.razorpayPaymentId || null,
          data.paymentStatus || 'pending',
          data.status || 'draft',
          toIso(data.startTime),
          toIso(data.endTime),
          toIso(data.createdAt) || new Date().toISOString(),
          toIso(data.updatedAt) || new Date().toISOString(),
        ]
      );
    }
    recordStat('promoted_ads', 'valid');
  }
  console.log(`Scanned: ${snap.size} | Valid: ${stats.valid['promoted_ads'] || 0}`);
}

// ----------------------------------------------------------------------------
// MAIN CONTROLLER
// ----------------------------------------------------------------------------

async function runMigration() {
  const startTime = Date.now();

  try {
    if (!IS_DRY_RUN) {
      await pgClient.connect();
      console.log('PostgreSQL connected successfully.');
    }

    await migrateSystemConfig();
    await migrateUsers();
    await migrateDoctors();
    await migratePatients();
    await migrateMedicalStores();
    await migrateLabs();
    await migrateAmbulances();
    await migrateAppointments();
    await migratePrescriptions();
    await migratePromotedAds();

    console.log('\n================================================================');
    console.log('MIGRATION SUMMARY AUDIT REPORT');
    console.log('================================================================');
    console.table(
      Object.keys(stats.scanned).map((col) => ({
        Entity: col,
        'Scanned (Firestore)': stats.scanned[col] || 0,
        'Valid (Postgres Ready)': stats.valid[col] || 0,
        'FK Warnings': stats.warnings[col] || 0,
        'Skipped': stats.skipped[col] || 0,
        'Fatal Errors': stats.errors[col] || 0,
      }))
    );

    if (warningDetails.length > 0) {
      console.log(`\n⚠️  WARNING DETAILS & FOREIGN KEY ISSUES (Found ${warningDetails.length} issues):`);
      warningDetails.forEach((w, idx) => console.log(`  ${idx + 1}. ${w}`));
    } else {
      console.log('\n✅ Zero foreign key or schema validation warnings found across all scanned documents!\n');
    }

    const elapsedSeconds = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`Finished in ${elapsedSeconds} seconds.`);
    console.log(IS_DRY_RUN ? 'Dry-run complete. No database mutations occurred.' : 'Live migration succeeded!');
  } catch (err) {
    console.error('\nMigration aborted due to fatal error:', err);
    process.exit(1);
  } finally {
    if (pgClient) await pgClient.end();
  }
}

runMigration();
