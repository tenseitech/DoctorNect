/**
 * Seed Full Test Dataset across all public tables for purge & orphan verification.
 */
require('./load_env').loadEnv();
const { Client } = require('pg');

const connectionString =
  process.env.SUPABASE_DB_URL ||
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  'postgres://postgres:postgres@127.0.0.1:54322/postgres';

async function seed() {
  const client = new Client({
    connectionString,
    ssl: connectionString.includes('localhost') || connectionString.includes('127.0.0.1') ? false : { rejectUnauthorized: false },
  });

  await client.connect();
  console.log('Seeding full test dataset across all tables...');

  try {
    await client.query('BEGIN');

    // 1. Users
    await client.query(`
      INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
      VALUES 
        ('fb_uid_purge_pat', 'fb_uid_purge_pat', 'patient', 'pat_purge_001', 'Purge Patient', 'pat.purge@test.com', '9800000091', true, true, 'approved'),
        ('fb_uid_purge_doc', 'fb_uid_purge_doc', 'doctor', 'doc_purge_001', 'Purge Doctor', 'doc.purge@test.com', '9800000092', true, true, 'approved'),
        ('fb_uid_purge_store', 'fb_uid_purge_store', 'medicalStore', 'store_purge_001', 'Purge Store', 'store.purge@test.com', '9800000093', true, true, 'approved'),
        ('fb_uid_purge_lab', 'fb_uid_purge_lab', 'lab', 'lab_purge_001', 'Purge Lab', 'lab.purge@test.com', '9800000094', true, true, 'approved'),
        ('fb_uid_purge_amb', 'fb_uid_purge_amb', 'ambulance', 'amb_purge_001', 'Purge Ambulance', 'amb.purge@test.com', '9800000095', true, true, 'approved')
      ON CONFLICT (id) DO NOTHING;
    `);

    // 2. Profiles
    await client.query(`
      INSERT INTO public.patients (patient_id, owner_uid, name, mobile, email, verified, profile_completed)
      VALUES ('pat_purge_001', 'fb_uid_purge_pat', 'Purge Patient', '9800000091', 'pat.purge@test.com', true, true)
      ON CONFLICT (patient_id) DO NOTHING;

      INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, clinic_name, city, verified, profile_completed)
      VALUES ('doc_purge_001', 'fb_uid_purge_doc', 'Purge Doctor', 'doc.purge@test.com', '9800000092', 'General', 'MBBS', 'Purge Clinic', 'Mumbai', true, true)
      ON CONFLICT (doctor_id) DO NOTHING;

      INSERT INTO public.doctor_private (doctor_id, phone, email, council_number, state_council)
      VALUES ('doc_purge_001', '9800000092', 'doc.purge@test.com', 'MCI-PURGE-001', 'Maharashtra')
      ON CONFLICT (doctor_id) DO NOTHING;

      INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, phone, email, drug_license_number, verified, profile_completed)
      VALUES ('store_purge_001', 'fb_uid_purge_store', 'Purge Pharmacy', 'Owner Pharmacy', '9800000093', 'store.purge@test.com', 'DL-PURGE-001', true, true)
      ON CONFLICT (store_id) DO NOTHING;

      INSERT INTO public.labs (lab_id, owner_uid, lab_name, phone, email, license_number, verified, profile_completed)
      VALUES ('lab_purge_001', 'fb_uid_purge_lab', 'Purge Diagnostics', '9800000094', 'lab.purge@test.com', 'LIC-PURGE-001', true, true)
      ON CONFLICT (lab_id) DO NOTHING;

      INSERT INTO public.ambulances (ambulance_id, auth_uid, vehicle_number, service_name, driver_name, phone, ambulance_type, city, verified, is_available)
      VALUES ('amb_purge_001', 'fb_uid_purge_amb', 'MH-01-PURGE', 'Purge EMS', 'Driver Purge', '9800000095', 'bls', 'Mumbai', true, true)
      ON CONFLICT (ambulance_id) DO NOTHING;
    `);

    // 3. Clinical & Secondary Entities
    await client.query(`
      INSERT INTO public.doctor_availability (doctor_id, working_days, morning_start, morning_end, slot_duration_mins)
      VALUES ('doc_purge_001', ARRAY['Mon', 'Tue'], '09:00 AM', '01:00 PM', 30)
      ON CONFLICT DO NOTHING;

      INSERT INTO public.doctor_blocked_dates (doctor_id, blocked_date)
      VALUES ('doc_purge_001', '2026-12-25')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.family_members (member_id, patient_id, name, relation, age, gender)
      VALUES ('fam_purge_001', 'pat_purge_001', 'Purge Child', 'child', 8, 'Male')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.health_records (record_id, patient_id, title, type, date, source, file_name, file_storage, notes, s3_key)
      VALUES ('hr_purge_001', 'pat_purge_001', 'Old Rx', 'prescription', now(), 'selfUploaded', 'rec1.pdf', 'none', 'Notes', 'health_records/pat_purge_001/rec1.pdf')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, token_number, visit_type, patient_status, doctor_status)
      VALUES ('apt_purge_001', 'doc_purge_001', 'pat_purge_001', 'Purge Doctor', 'General', 'Purge Patient', 30, 'Male', now(), '10:00 AM', 1, 'newVisit', 'confirmed', 'confirmed')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age, primary_diagnosis)
      VALUES ('rx_purge_001', 'doc_purge_001', 'pat_purge_001', 'apt_purge_001', 'Purge Patient', 30, 'Fever')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.prescription_medicines (prescription_id, medicine_entry_id, name, dosage, form, frequency, quantity, duration)
      VALUES ('rx_purge_001', 'entry_001', 'Paracetamol', '500mg', 'Tablet', 'TDS', '10', '3 days')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.prescription_investigations (prescription_id, name, type)
      VALUES ('rx_purge_001', 'CBC', 'lab')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.prescription_referrals (prescription_id, to_doctor_id, doctor_name, specialization, reason)
      VALUES ('rx_purge_001', 'doc_purge_001', 'Purge Doctor', 'General', 'Second opinion')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.patient_doctor_links (patient_id, doctor_id, source)
      VALUES ('pat_purge_001', 'doc_purge_001', 'appointment')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.patient_care_team (patient_id, doctor_id)
      VALUES ('pat_purge_001', 'doc_purge_001')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.reviews (review_id, doctor_id, patient_id, patient_name, rating, comment)
      VALUES ('rev_purge_001', 'doc_purge_001', 'pat_purge_001', 'Purge Patient', 5, 'Great doctor!')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.review_votes (review_id, patient_id)
      VALUES ('rev_purge_001', 'pat_purge_001')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.review_public (review_id, doctor_id, rating, comment, masked_name)
      VALUES ('rev_purge_001', 'doc_purge_001', 5, 'Great doctor!', 'P**** P****')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.referrals (referral_id, from_doctor_id, to_doctor_id, patient_id, from_doctor_name, to_doctor_name, to_specialization, patient_name, patient_age, reason)
      VALUES ('ref_purge_001', 'doc_purge_001', 'doc_purge_001', 'pat_purge_001', 'Doctor Purge One', 'Doctor Purge Two', 'Cardiology', 'Purge Patient', 30, 'Cardiology consult')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.pharmacy_deliveries (delivery_id, store_id, patient_id, prescription_id, doctor_id, doctor_name, store_name, patient_name, status)
      VALUES ('deliv_purge_001', 'store_purge_001', 'pat_purge_001', 'rx_purge_001', 'doc_purge_001', 'Purge Doctor', 'Purge Pharmacy', 'Purge Patient', 'sent')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability)
      VALUES ('deliv_purge_001', 'entry_001', 'available')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.pharmacy_connections (connection_id, doctor_id, medical_store_id, doctor_name, store_name, status, requested_by)
      VALUES ('pconn_purge_001', 'doc_purge_001', 'store_purge_001', 'Purge Doctor', 'Purge Pharmacy', 'active', 'doctor')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.lab_orders (order_id, lab_id, doctor_id, patient_id, doctor_name, patient_name, patient_age, test_ids, test_names, status)
      VALUES ('lord_purge_001', 'lab_purge_001', 'doc_purge_001', 'pat_purge_001', 'Purge Doctor', 'Purge Patient', 30, ARRAY['t1'], ARRAY['Complete Blood Count'], 'ordered')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.lab_bookings (booking_id, lab_id, patient_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status)
      VALUES ('lbkg_purge_001', 'lab_purge_001', 'pat_purge_001', 'Purge Patient', 30, 't1', 'Lipid Profile', ARRAY['Lipid Profile'], 'labVisit', now(), '11:00 AM', 'confirmed')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.lab_connections (connection_id, doctor_id, lab_id, doctor_name, lab_name, status, requested_by)
      VALUES ('lconn_purge_001', 'doc_purge_001', 'lab_purge_001', 'Purge Doctor', 'Purge Diagnostics', 'active', 'doctor')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_broadcasts (broadcast_id, patient_id, patient_name, pickup_location, drop_location, status)
      VALUES ('ambb_purge_001', 'pat_purge_001', 'Purge Patient', '123 Test St', 'City Hospital', 'pending')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_requests (request_id, broadcast_id, driver_id, patient_id, patient_name, pickup_location, drop_location, status)
      VALUES ('ambr_purge_001', 'ambb_purge_001', 'amb_purge_001', 'pat_purge_001', 'Purge Patient', '123 Test St', 'City Hospital', 'pending')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_locations (broadcast_id, driver_id, latitude, longitude)
      VALUES ('ambb_purge_001', 'amb_purge_001', 19.0760, 72.8777)
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_location_updates (broadcast_id)
      VALUES ('ambb_purge_001')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone)
      VALUES ('ambb_purge_001', '9800000091', '9800000095')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_private_settings (ambulance_id, pin_hash)
      VALUES ('amb_purge_001', 'hash_test_pin_1234')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.ambulance_invites (invite_id, token, doctor_id, ambulance_id, service_name, driver_name, phone, status)
      VALUES ('ambinv_purge_001', 'token_purge_123', 'doc_purge_001', 'amb_purge_001', 'Purge EMS', 'Driver Purge', '9800000095', 'pending')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.support_tickets (ticket_id, user_id, patient_id, doctor_id, issue_type, message, status)
      VALUES ('TICK-PURGE-001', 'fb_uid_purge_pat', 'pat_purge_001', 'doc_purge_001', 'Appointment', 'Test issue', 'open')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.support_ticket_messages (message_id, ticket_id, sender_id, sender_name, sender_role, text)
      VALUES ('msg_purge_001', 'TICK-PURGE-001', 'fb_uid_purge_pat', 'Purge Patient', 'patient', 'Hello support')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.in_app_notifications (notification_id, recipient_uid, title, body, type)
      VALUES ('notif_purge_001', 'fb_uid_purge_pat', 'Test Title', 'Test Body', 'system')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.user_devices (user_id, fcm_token, platform)
      VALUES ('fb_uid_purge_pat', 'fcm_purge_token_123', 'android')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.storage_audit_logs (who, role, what, action)
      VALUES ('fb_uid_purge_pat', 'patient', 'health_records/pat_purge_001/rec1.pdf', 'upload')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.promoted_ads (ad_id, provider_type, provider_id, title, description, image_url, cta_label, duration_hours, amount_paid, status)
      VALUES ('AD-PURGE-001', 'doctor', 'fb_uid_purge_doc', 'Purge Ad', 'Purge Ad Desc', 'https://s3.example.com/ad.jpg', 'Learn', 24, 300, 'draft')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.razorpay_orders (order_id, user_uid, ad_id, amount_paise, receipt, status)
      VALUES ('order_purge_001', 'fb_uid_purge_doc', 'AD-PURGE-001', 30000, 'rcpt_purge_001', 'created')
      ON CONFLICT DO NOTHING;

      INSERT INTO public.razorpay_payments (payment_id, order_id, signature, amount_paise, status)
      VALUES ('pay_purge_001', 'order_purge_001', 'sig_purge_001', 30000, 'captured')
      ON CONFLICT DO NOTHING;
    `);

    await client.query('COMMIT');
    console.log('Successfully seeded full test dataset across all tables!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Seeding failed:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

seed();
