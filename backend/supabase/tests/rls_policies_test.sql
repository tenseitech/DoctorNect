-- ============================================================================
-- DOCTORNECT PLATFORM — ROW-LEVEL SECURITY (RLS) TEST SUITE
-- ============================================================================
-- File: backend/supabase/tests/rls_policies_test.sql
--
-- Simulates Firebase JWT claims using PostgreSQL request.jwt.claims:
--   - Patient: Sees own data, records, appointments, prescriptions
--   - Doctor: Sees assigned patients, appointments, prescriptions, cannot see unassigned
--   - Pharmacy: Sees deliveries sent to its store_id
--   - Lab: Sees bookings & orders assigned to its lab_id
--   - Ambulance: Sees pending broadcasts and accepted emergencies
--   - Anon: Blocked from protected tables
--
-- Execution: psql -f rls_policies_test.sql (Transactions rollback automatically)
-- ============================================================================

BEGIN;

CREATE TEMP TABLE test_results (
    test_num INT,
    test_name TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);
GRANT ALL ON test_results TO authenticated, anon;

-- Setup test fixtures with synthetic Firebase UIDs
DO $$
DECLARE
    v_doc1_uid TEXT := 'fb_uid_doc_001';
    v_doc_unver_uid TEXT := 'fb_uid_doc_unver';
    v_pat1_uid TEXT := 'fb_uid_pat_001';
    v_pat2_uid TEXT := 'fb_uid_pat_002';
    v_pharma_uid TEXT := 'fb_uid_pharma_001';
    v_lab_uid TEXT := 'fb_uid_lab_001';
    v_amb_uid TEXT := 'fb_uid_amb_001';

    v_doc1_id TEXT := 'd_001';
    v_doc_unver_id TEXT := 'd_unver';
    v_pat1_id TEXT := 'p_001';
    v_pat2_id TEXT := 'p_002';
    v_store_id TEXT := 'ms_001';
    v_lab_id TEXT := 'lab_001';
    v_amb_id TEXT := 'amb_001';
BEGIN
    -- Seed synthetic users with TEXT primary keys (Firebase UIDs)
    INSERT INTO users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
    VALUES 
      (v_doc1_uid, v_doc1_uid, 'doctor', v_doc1_id, 'Dr. Alpha', 'doc1@test.com', '9800000001', TRUE, TRUE, 'approved'),
      (v_doc_unver_uid, v_doc_unver_uid, 'doctor', v_doc_unver_id, 'Dr. Pending', 'unver@test.com', '9800000002', TRUE, FALSE, 'approved'),
      (v_pat1_uid, v_pat1_uid, 'patient', v_pat1_id, 'Patient One', 'pat1@test.com', '9800000003', TRUE, TRUE, 'approved'),
      (v_pat2_uid, v_pat2_uid, 'patient', v_pat2_id, 'Patient Two', 'pat2@test.com', '9800000004', TRUE, TRUE, 'approved'),
      (v_pharma_uid, v_pharma_uid, 'medicalStore', v_store_id, 'Apollo Meds', 'pharma@test.com', '9800000005', TRUE, TRUE, 'approved'),
      (v_lab_uid, v_lab_uid, 'lab', v_lab_id, 'Thyro Lab', 'lab@test.com', '9800000006', TRUE, TRUE, 'approved'),
      (v_amb_uid, v_amb_uid, 'ambulance', v_amb_id, 'Rapid 108', 'amb@test.com', '9800000007', TRUE, TRUE, 'approved')
    ON CONFLICT (id) DO NOTHING;

    -- Seed doctors
    INSERT INTO doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
    VALUES 
      (v_doc1_id, v_doc1_uid, 'Dr. Alpha', 'doc1@test.com', '9800000001', 'Cardiology', 'MD', TRUE, FALSE, TRUE),
      (v_doc_unver_id, v_doc_unver_uid, 'Dr. Pending', 'unver@test.com', '9800000002', 'General', 'MBBS', FALSE, FALSE, TRUE)
    ON CONFLICT (doctor_id) DO NOTHING;

    -- Seed patients
    INSERT INTO patients (patient_id, owner_uid, name, mobile, share_records_with_doctors, profile_completed, verified)
    VALUES 
      (v_pat1_id, v_pat1_uid, 'Patient One', '9800000003', TRUE, TRUE, TRUE),
      (v_pat2_id, v_pat2_uid, 'Patient Two', '9800000004', FALSE, TRUE, TRUE)
    ON CONFLICT (patient_id) DO NOTHING;

    -- Seed appointments
    INSERT INTO appointments (appointment_id, doctor_id, patient_id, doctor_name, specialization, patient_name, patient_age, patient_gender, date_time, slot_label, visit_type, patient_status, doctor_status)
    VALUES 
      ('apt_test_01', v_doc1_id, v_pat1_id, 'Dr. Alpha', 'Cardiology', 'Patient One', 35, 'Male', NOW(), '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
      ('apt_test_02', v_doc_unver_id, v_pat2_id, 'Dr. Pending', 'General', 'Patient Two', 42, 'Female', NOW(), '11:00 AM', 'newVisit', 'confirmed', 'confirmed')
    ON CONFLICT (appointment_id) DO NOTHING;

    -- Seed prescriptions
    INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, appointment_id, patient_name, patient_age)
    VALUES 
      ('rx_test_01', v_doc1_id, v_pat1_id, 'apt_test_01', 'Patient One', 35)
    ON CONFLICT (prescription_id) DO NOTHING;

    -- Seed health records
    INSERT INTO health_records (record_id, patient_id, title, type, date, source, file_name, shared_with_doctors, s3_key, s3_bucket)
    VALUES 
      ('rec_test_01', v_pat1_id, 'Blood Test', 'labReport', NOW(), 'selfUploaded', 'test1.pdf', TRUE, 'records/rec_01.pdf', 'private-records'),
      ('rec_test_02', v_pat2_id, 'Private ECG', 'prescription', NOW(), 'selfUploaded', 'ecg.pdf', FALSE, 'records/ecg.pdf', 'private-records')
    ON CONFLICT (record_id) DO NOTHING;

    -- Seed pharmacy
    INSERT INTO medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified)
    VALUES 
      (v_store_id, v_pharma_uid, 'Apollo Meds', 'Pharma Owner', 'DL-12345', '9800000005', 'pharma@test.com', TRUE)
    ON CONFLICT (store_id) DO NOTHING;

    -- Seed pharmacy delivery
    INSERT INTO pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status)
    VALUES 
      ('deliv_test_01', 'rx_test_01', v_doc1_id, v_store_id, v_pat1_id, 'Dr. Alpha', 'Apollo Meds', 'Patient One', 'sent')
    ON CONFLICT (delivery_id) DO NOTHING;

    -- Seed lab
    INSERT INTO labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified)
    VALUES 
      (v_lab_id, v_lab_uid, 'Thyro Lab', 'LAB-123', '9800000006', 'lab@test.com', TRUE)
    ON CONFLICT (lab_id) DO NOTHING;

    -- Seed lab booking & order
    INSERT INTO lab_bookings (booking_id, patient_id, lab_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status)
    VALUES 
      ('lbook_test_01', v_pat1_id, v_lab_id, 'Patient One', 35, 'T01', 'Lipid Profile', ARRAY['Lipid Profile'], 'labVisit', NOW(), '10:00 AM', 'confirmed')
    ON CONFLICT (booking_id) DO NOTHING;

    INSERT INTO lab_orders (order_id, doctor_id, patient_id, lab_id, doctor_name, patient_name, patient_age, test_ids, test_names, status)
    VALUES 
      ('lord_test_01', v_doc1_id, v_pat1_id, v_lab_id, 'Dr. Alpha', 'Patient One', 35, ARRAY['T01'], ARRAY['Lipid Profile'], 'ordered')
    ON CONFLICT (order_id) DO NOTHING;

    -- Seed ambulance
    INSERT INTO ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified, is_available)
    VALUES 
      (v_amb_id, v_amb_uid, 'Rapid 108', 'Ramesh Driver', '9800000007', 'MH-12-AB-1234', 'als', 'Mumbai', TRUE, TRUE)
    ON CONFLICT (ambulance_id) DO NOTHING;

    -- Seed ambulance broadcasts
    INSERT INTO ambulance_broadcasts (broadcast_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status)
    VALUES 
      ('bc_test_01', v_pat1_id, 'Patient One', 'Andheri West', 'Nanavati Hospital', '9800000003', 'pending')
    ON CONFLICT (broadcast_id) DO NOTHING;

    INSERT INTO ambulance_broadcasts (broadcast_id, patient_id, patient_name, pickup_location, drop_location, contact_phone, status, accepted_driver_id)
    VALUES 
      ('bc_test_02', v_pat2_id, 'Patient Two', 'Bandra', 'Lilavati Hospital', '9800000004', 'accepted', v_amb_id)
    ON CONFLICT (broadcast_id) DO NOTHING;

    -- Seed notification
    INSERT INTO in_app_notifications (notification_id, recipient_uid, title, body)
    VALUES 
      ('notif_test_01', v_pat1_uid, 'Appointment Confirmed', 'Your appointment with Dr. Alpha is confirmed.')
    ON CONFLICT (notification_id) DO NOTHING;
END $$;

-- ============================================================================
-- TEST 1: PATIENT ISOLATION
-- Patient 1 queries public.users and appointments
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    1,
    'Patient Isolation (sees own user record only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.users;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    2,
    'Patient Appointments (sees own appointment only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.appointments;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    3,
    'Patient Health Records (sees own health records)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.health_records;

-- ============================================================================
-- TEST 2: DOCTOR CLINICAL VAULT ACCESS
-- Verified Doctor 1 sees assigned patient appointments & records
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_001", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    4,
    'Doctor Appointments (sees assigned appointment)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.appointments;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    5,
    'Doctor Vault Access (sees shared health records for assigned patient)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.health_records;

-- ============================================================================
-- TEST 3: UNVERIFIED DOCTOR ISOLATION
-- Unverified Doctor CANNOT access patient clinical vault
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_unver", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    6,
    'Unverified Doctor Vault Lockdown (0 records visible)',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.health_records;

-- ============================================================================
-- TEST 4: PHARMACY DELIVERY ACCESS
-- Pharmacy sees prescription deliveries sent to its store
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pharma_001", "role": "authenticated", "user_role": "medicalStore", "app_role": "medicalStore"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    7,
    'Pharmacy Delivery Access (sees deliveries sent to its store)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.pharmacy_deliveries;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    8,
    'Pharmacy Prescription View (sees connected prescription)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.prescriptions;

-- ============================================================================
-- TEST 5: DIAGNOSTIC LAB ORDERS & BOOKINGS
-- Lab sees assigned bookings and orders
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_lab_001", "role": "authenticated", "user_role": "lab", "app_role": "lab"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    9,
    'Lab Bookings Access (sees bookings assigned to its lab)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_bookings;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    10,
    'Lab Orders Access (sees doctor orders assigned to its lab)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_orders;

-- ============================================================================
-- TEST 6: AMBULANCE DISPATCH & EMERGENCY BROADCASTS
-- Ambulance sees pending broadcasts and emergencies accepted by it
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT 
    11,
    'Ambulance Broadcast Access (sees pending and accepted emergencies)',
    '2',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END
FROM public.ambulance_broadcasts;

-- ============================================================================
-- TEST 7: PATIENT PRIVACY & CROSS-PATIENT ISOLATION
-- Patient One cannot query Patient Two's profile
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    12,
    'Patient Isolation (cannot read another patient profile)',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.patients
WHERE patient_id = 'p_002';

-- ============================================================================
-- TEST 8: DOCTOR SCHEDULE ISOLATION
-- Doctor Alpha cannot query Doctor Pending's appointments
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_001", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    13,
    'Doctor Appointments Isolation (cannot see unassigned appointments)',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.appointments
WHERE doctor_id != 'd_001';

-- ============================================================================
-- TEST 9: COLUMN IMMUTABILITY LOCK ON users.role
-- Authenticated client cannot update their own role
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.users SET role = 'superAdmin' WHERE id = 'fb_uid_pat_001';
    INSERT INTO test_results VALUES (14, 'users.role immutability (client cannot escalate role)', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (14, 'users.role immutability (client cannot escalate role)', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (14, 'users.role immutability (client cannot escalate role)', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 10: COLUMN IMMUTABILITY LOCK ON doctors.verified
-- Unverified doctor cannot set verified = true on their own doctor record
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_unver", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.doctors SET verified = TRUE WHERE doctor_id = 'd_unver';
    INSERT INTO test_results VALUES (15, 'doctors.verified immutability (client cannot self-verify)', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (15, 'doctors.verified immutability (client cannot self-verify)', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (15, 'doctors.verified immutability (client cannot self-verify)', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 11: COLUMN IMMUTABILITY LOCK ON doctors.rating
-- Direct client update to doctors.rating must be blocked
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_001", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.doctors SET rating = 5.0 WHERE doctor_id = 'd_001';
    INSERT INTO test_results VALUES (16, 'doctors.rating direct update blocked (42501)', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (16, 'doctors.rating direct update blocked (42501)', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (16, 'doctors.rating direct update blocked (42501)', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 12: REVIEW INSERTION UPDATES DOCTORS.RATING UNDER COLUMN LOCK
-- Inserting a review updates rating & review_count via aggregate trigger bypass
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO public.reviews (review_id, patient_id, doctor_id, patient_name, rating, comment)
VALUES ('rev_test_01', 'p_001', 'd_001', 'Patient One', 5, 'Excellent doctor!');

RESET ROLE;
INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    17,
    'reviews trigger updates doctors.rating and review_count under column lock',
    'rating=5.00, count=1',
    'rating=' || rating::text || ', count=' || review_count::text,
    CASE WHEN rating = 5.00 AND review_count = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.doctors
WHERE doctor_id = 'd_001';

-- ============================================================================
-- TEST 13: PRESCRIPTION OWNERSHIP IN create_prescription_atomic
-- Doctor B cannot overwrite Doctor A's prescription or attach Doctor A's appointment
-- ============================================================================
RESET ROLE;
INSERT INTO users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
VALUES ('fb_uid_doc_002', 'fb_uid_doc_002', 'doctor', 'd_002', 'Dr. Beta', 'doc2@test.com', '9800000008', TRUE, TRUE, 'approved')
ON CONFLICT (id) DO NOTHING;

INSERT INTO doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
VALUES ('d_002', 'fb_uid_doc_002', 'Dr. Beta', 'doc2@test.com', '9800000008', 'Dermatology', 'MD', TRUE, FALSE, TRUE)
ON CONFLICT (doctor_id) DO NOTHING;

SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_doc_002", "role": "authenticated", "user_role": "doctor", "app_role": "doctor"}', true);
SET LOCAL ROLE authenticated;

-- Cannot overwrite Doctor A's prescription
DO $$
BEGIN
    PERFORM public.create_prescription_atomic(jsonb_build_object(
        'prescription_id', 'rx_test_01',
        'patient_id', 'p_001',
        'appointment_id', 'apt_test_01',
        'primary_diagnosis', 'Hijacked diagnosis'
    ));
    INSERT INTO test_results VALUES (18, 'create_prescription_atomic: Doctor B cannot overwrite Doctor A prescription', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (18, 'create_prescription_atomic: Doctor B cannot overwrite Doctor A prescription', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (18, 'create_prescription_atomic: Doctor B cannot overwrite Doctor A prescription', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- Cannot attach appointment belonging to another doctor
DO $$
BEGIN
    PERFORM public.create_prescription_atomic(jsonb_build_object(
        'prescription_id', 'rx_test_doc2_new',
        'patient_id', 'p_001',
        'appointment_id', 'apt_test_01',
        'primary_diagnosis', 'Valid diagnosis'
    ));
    INSERT INTO test_results VALUES (19, 'create_prescription_atomic: Doctor cannot attach appointment belonging to another doctor', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (19, 'create_prescription_atomic: Doctor cannot attach appointment belonging to another doctor', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (19, 'create_prescription_atomic: Doctor cannot attach appointment belonging to another doctor', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 14: PATIENT BOOKING IDENTITY VERIFICATION
-- Patient cannot book appointment specifying another patient's ID
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    PERFORM public.book_appointment_atomic(
        p_appointment_id := 'apt_spoof_01',
        p_doctor_id := 'd_001',
        p_doctor_name := 'Dr. Alpha',
        p_specialization := 'Cardiology',
        p_patient_name := 'Spoofed Patient',
        p_patient_age := 30,
        p_patient_gender := 'Male',
        p_date_time := NOW() + interval '1 day',
        p_slot_label := '11:00 AM',
        p_patient_id := 'p_002'
    );
    INSERT INTO test_results VALUES (20, 'book_appointment_atomic: Patient cannot book as another patient', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (20, 'book_appointment_atomic: Patient cannot book as another patient', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (20, 'book_appointment_atomic: Patient cannot book as another patient', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 15: ANON RPC ACCESS LOCKDOWN
-- Anon cannot invoke book_appointment_atomic or create_prescription_atomic
-- ============================================================================
SELECT set_config('request.jwt.claims', '{}', true);
SET LOCAL ROLE anon;

DO $$
BEGIN
    PERFORM public.book_appointment_atomic(
        p_appointment_id := 'apt_anon_01',
        p_doctor_id := 'd_001',
        p_doctor_name := 'Dr. Alpha',
        p_specialization := 'Cardiology',
        p_patient_name := 'Anon Patient',
        p_patient_age := 30,
        p_patient_gender := 'Male',
        p_date_time := NOW() + interval '2 days',
        p_slot_label := '11:00 AM'
    );
    INSERT INTO test_results VALUES (21, 'anon cannot call book_appointment_atomic', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (21, 'anon cannot call book_appointment_atomic', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (21, 'anon cannot call book_appointment_atomic', 'BLOCK', SQLERRM, 'FAIL');
END $$;

DO $$
BEGIN
    PERFORM public.create_prescription_atomic(jsonb_build_object('prescription_id', 'rx_anon_01'));
    INSERT INTO test_results VALUES (22, 'anon cannot call create_prescription_atomic', 'BLOCK', 'ALLOWED', 'FAIL');
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        INSERT INTO test_results VALUES (22, 'anon cannot call create_prescription_atomic', 'BLOCK', 'BLOCKED (42501)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO test_results VALUES (22, 'anon cannot call create_prescription_atomic', 'BLOCK', SQLERRM, 'FAIL');
END $$;

-- ============================================================================
-- TEST 16: PATIENT ISOLATION ACROSS RECORDS & APPOINTMENTS
-- Patient 1 cannot query Patient 2's health records or appointments
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    23,
    'Patient cannot read another patient health records',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.health_records
WHERE patient_id = 'p_002';

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    24,
    'Patient cannot read another patient appointments',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.appointments
WHERE patient_id = 'p_002';

-- ============================================================================
-- TEST 17: REVIEWS TABLE PRIVACY & ANONYMIZATION
-- reviews table hides patient identity from other patients; review_public masks name
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_002", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    25,
    'reviews table hides other patients reviews (0 rows returned to 3rd party)',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.reviews
WHERE patient_id = 'p_001';

INSERT INTO test_results (test_num, test_name, expected, actual, status)
SELECT
    26,
    'review_public table exposes masked name without patient identity',
    'Patient O.',
    masked_name,
    CASE WHEN masked_name = 'Patient O.' THEN 'PASS' ELSE 'FAIL' END
FROM public.review_public
WHERE review_id = 'rev_test_01';

-- Reset role to print results
RESET ROLE;

-- Display all test results
SELECT 
    test_num,
    test_name,
    expected,
    actual,
    status
FROM test_results
ORDER BY test_num ASC;

ROLLBACK;
