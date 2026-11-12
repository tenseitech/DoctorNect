'use strict';

/**
 * seed_reviewer_accounts.js
 *
 * Provisions server-side pre-approved Play Store / App Store reviewer dummy accounts
 * directly into Supabase via service role / PostgreSQL client.
 *
 * Safety Guards:
 *   - Dry-run by default.
 *   - Explicit --apply AND --confirm flags required for execution.
 *   - Fictitious dummy data ONLY (5 dummy roles).
 *
 * Usage:
 *   node backend/scripts/seed_reviewer_accounts.js
 *   node backend/scripts/seed_reviewer_accounts.js --apply --confirm
 */

const { Client } = require(require('path').join(__dirname, '../node_modules/pg'));
const crypto = require('crypto');

const args = process.argv.slice(2);
const isApply = args.includes('--apply');
const isConfirmed = args.includes('--confirm');
const isDryRun = !isApply || !isConfirmed;

const connectionString = process.env.SUPABASE_DB_URL || 'postgres://postgres:postgres@127.0.0.1:54322/postgres';

const DUMMY_REVIEWER_DATA = [
  {
    role: 'patient',
    profileId: 'rev_pat_001',
    firebaseUid: 'rev_fb_pat_001',
    displayName: 'Reviewer Patient',
    mobile: '9999900001',
    email: 'reviewer.patient@doctornect.test',
  },
  {
    role: 'doctor',
    profileId: 'rev_doc_001',
    firebaseUid: 'rev_fb_doc_001',
    displayName: 'Dr. Reviewer',
    mobile: '9999900002',
    email: 'reviewer.doctor@doctornect.test',
    specialization: 'General Medicine',
    qualification: 'MBBS, MD',
    experienceYears: 10,
    consultationFee: 500,
    councilReg: 'REV-MCI-99999',
  },
  {
    role: 'medicalStore',
    profileId: 'rev_store_001',
    firebaseUid: 'rev_fb_store_001',
    displayName: 'Reviewer Pharmacy',
    mobile: '9999900003',
    email: 'reviewer.pharmacy@doctornect.test',
    storeName: 'Reviewer Pharmacy',
    ownerName: 'Reviewer Owner',
    drugLicenseNumber: 'REV-20B-99999',
  },
  {
    role: 'lab',
    profileId: 'rev_lab_001',
    firebaseUid: 'rev_fb_lab_001',
    displayName: 'Reviewer Diagnostics',
    mobile: '9999900004',
    email: 'reviewer.lab@doctornect.test',
    labName: 'Reviewer Diagnostics',
    licenseNumber: 'REV-NABL-99999',
  },
  {
    role: 'ambulance',
    profileId: 'rev_amb_001',
    firebaseUid: 'rev_fb_amb_001',
    displayName: 'Reviewer Ambulance',
    mobile: '9999900005',
    email: 'reviewer.ambulance@doctornect.test',
    serviceName: 'Reviewer Emergency Ambulance',
    driverName: 'Reviewer Driver',
    vehicleNumber: 'DL-01-REV-108',
    ambulanceType: 'als',
    city: 'New Delhi',
    pinHash: crypto.createHash('sha256').update('112233').digest('hex'),
  },
];

async function run() {
  console.log('======================================================');
  console.log('  SEED PLAY STORE / APP STORE REVIEWER DUMMY ACCOUNTS ');
  console.log('======================================================');
  console.log(`Mode: ${isDryRun ? 'DRY-RUN (Safe, zero writes)' : 'APPLY (Writing dummy accounts)'}`);

  if (isDryRun) {
    console.log('\n[DRY RUN] The following pre-approved accounts would be seeded:');
    for (const item of DUMMY_REVIEWER_DATA) {
      console.log(`  Role: ${item.role.padEnd(14)} | Profile ID: ${item.profileId.padEnd(14)} | Name: ${item.displayName.padEnd(25)} | Mobile: ${item.mobile}`);
    }
    console.log('\nTo apply changes to database, run with: node backend/scripts/seed_reviewer_accounts.js --apply --confirm\n');
    return;
  }

  const client = new Client({ connectionString });
  await client.connect();

  try {
    await client.query('BEGIN');

    for (const item of DUMMY_REVIEWER_DATA) {
      console.log(`[SEED] Upserting user & profile for ${item.role} (${item.profileId})...`);

      // 1. Upsert public.users
      const userRes = await client.query(`
        INSERT INTO public.users (
          id, firebase_uid, role, profile_id, display_name, email, mobile,
          profile_completed, verified, status
        ) VALUES (
          gen_random_uuid(), $1, $2, $3, $4, $5, $6,
          true, true, 'approved'
        )
        ON CONFLICT (firebase_uid) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          email = EXCLUDED.email,
          mobile = EXCLUDED.mobile,
          profile_completed = true,
          verified = true,
          status = 'approved',
          updated_at = now()
        RETURNING id;
      `, [item.firebaseUid, item.role, item.profileId, item.displayName, item.email, item.mobile]);

      const userId = userRes.rows[0].id;

      // 2. Upsert specific role table
      if (item.role === 'patient') {
        await client.query(`
          INSERT INTO public.patients (patient_id, owner_uid, name, mobile, email, verified, profile_completed)
          VALUES ($1, $2, $3, $4, $5, true, true)
          ON CONFLICT (patient_id) DO UPDATE SET
            name = EXCLUDED.name,
            mobile = EXCLUDED.mobile,
            email = EXCLUDED.email,
            verified = true,
            profile_completed = true;
        `, [item.profileId, userId, item.displayName, item.mobile, item.email]);
      } else if (item.role === 'doctor') {
        await client.query(`
          INSERT INTO public.doctors (
            doctor_id, owner_uid, name, email, mobile, specialization, qualification,
            experience_years, consultation_fee, verified, deactivated, profile_completed
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, false, true)
          ON CONFLICT (doctor_id) DO UPDATE SET
            name = EXCLUDED.name,
            email = EXCLUDED.email,
            mobile = EXCLUDED.mobile,
            specialization = EXCLUDED.specialization,
            qualification = EXCLUDED.qualification,
            experience_years = EXCLUDED.experience_years,
            consultation_fee = EXCLUDED.consultation_fee,
            verified = true,
            deactivated = false,
            profile_completed = true;
        `, [item.profileId, userId, item.displayName, item.email, item.mobile, item.specialization, item.qualification, item.experienceYears, item.consultationFee]);

        await client.query(`
          INSERT INTO public.doctor_private (doctor_id, phone, email, council_number)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (doctor_id) DO UPDATE SET
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            council_number = EXCLUDED.council_number;
        `, [item.profileId, item.mobile, item.email, item.councilReg]);
      } else if (item.role === 'medicalStore') {
        await client.query(`
          INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, phone, email, drug_license_number, verified, deactivated, profile_completed)
          VALUES ($1, $2, $3, $4, $5, $6, $7, true, false, true)
          ON CONFLICT (store_id) DO UPDATE SET
            store_name = EXCLUDED.store_name,
            owner_name = EXCLUDED.owner_name,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            drug_license_number = EXCLUDED.drug_license_number,
            verified = true,
            deactivated = false,
            profile_completed = true;
        `, [item.profileId, userId, item.storeName, item.ownerName, item.mobile, item.email, item.drugLicenseNumber]);
      } else if (item.role === 'lab') {
        await client.query(`
          INSERT INTO public.labs (lab_id, owner_uid, lab_name, phone, email, license_number, verified, deactivated, profile_completed)
          VALUES ($1, $2, $3, $4, $5, $6, true, false, true)
          ON CONFLICT (lab_id) DO UPDATE SET
            lab_name = EXCLUDED.lab_name,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            license_number = EXCLUDED.license_number,
            verified = true,
            deactivated = false,
            profile_completed = true;
        `, [item.profileId, userId, item.labName, item.mobile, item.email, item.licenseNumber]);
      } else if (item.role === 'ambulance') {
        await client.query(`
          INSERT INTO public.ambulances (
            ambulance_id, auth_uid, service_name, driver_name, phone,
            vehicle_number, ambulance_type, city, is_available, verified, profile_completed
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, true, true)
          ON CONFLICT (ambulance_id) DO UPDATE SET
            service_name = EXCLUDED.service_name,
            driver_name = EXCLUDED.driver_name,
            phone = EXCLUDED.phone,
            vehicle_number = EXCLUDED.vehicle_number,
            ambulance_type = EXCLUDED.ambulance_type,
            city = EXCLUDED.city,
            is_available = true,
            verified = true,
            profile_completed = true;
        `, [item.profileId, userId, item.serviceName, item.driverName, item.mobile, item.vehicleNumber, item.ambulanceType, item.city]);

        await client.query(`
          INSERT INTO public.ambulance_private_settings (ambulance_id, pin_hash)
          VALUES ($1, $2)
          ON CONFLICT (ambulance_id) DO UPDATE SET
            pin_hash = EXCLUDED.pin_hash;
        `, [item.profileId, item.pinHash]);
      }
    }

    await client.query('COMMIT');
    console.log('\n[SUCCESS] Successfully seeded 5 reviewer dummy accounts in Supabase database.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[ERROR] Failed to seed reviewer dummy accounts:', err);
    process.exit(1);
  } finally {
    await client.end();
  }
}

run().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
