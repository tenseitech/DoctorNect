-- ============================================================================
-- DOCTORNECT PLATFORM — PHASE D: PHARMACY, LAB, AMBULANCE RLS & RPC TEST SUITE
-- ============================================================================
-- File: backend/supabase/tests/phase_d_rls_test.sql
-- Description:
--   1. Cross-store, cross-lab, cross-driver isolation
--   2. Unrelated patient blocked from accessing other parties' data
--   3. Double-accept race (second accept must fail with error 42501)
--   4. Anon blocked from every RPC
--   5. Column locks: verified, rating, status (direct UPDATE throws 42501)
--   6. Validated state machines for Pharmacy and Lab status transitions
--   7. Automated S3 report linking to public.health_records
--   8. Ambulance live tracking & contact privacy (active-trip only)
-- ============================================================================

BEGIN;

CREATE TEMP TABLE phase_d_test_results (
    test_num INT,
    test_name TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);
GRANT ALL ON phase_d_test_results TO authenticated, anon;

-- Setup test fixtures with synthetic Firebase UIDs and records
DO $$
DECLARE
    -- Stores
    v_pharma1_uid TEXT := 'fb_uid_store_001';
    v_pharma2_uid TEXT := 'fb_uid_store_002';
    v_store1_id TEXT := 'ms_001';
    v_store2_id TEXT := 'ms_002';

    -- Labs
    v_lab1_uid TEXT := 'fb_uid_lab_001';
    v_lab2_uid TEXT := 'fb_uid_lab_002';
    v_lab1_id TEXT := 'lab_001';
    v_lab2_id TEXT := 'lab_002';

    -- Ambulances
    v_amb1_uid TEXT := 'fb_uid_amb_001';
    v_amb2_uid TEXT := 'fb_uid_amb_002';
    v_amb1_id TEXT := 'amb_001';
    v_amb2_id TEXT := 'amb_002';

    -- Patients & Doctors
    v_pat1_uid TEXT := 'fb_uid_pat_001';
    v_pat2_uid TEXT := 'fb_uid_pat_002';
    v_pat1_id TEXT := 'p_001';
    v_pat2_id TEXT := 'p_002';
    v_doc1_uid TEXT := 'fb_uid_doc_001';
    v_doc1_id TEXT := 'd_001';
BEGIN
    -- Seed synthetic users
    INSERT INTO users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
    VALUES 
      (v_doc1_uid, v_doc1_uid, 'doctor', v_doc1_id, 'Dr. Alpha', 'doc1@test.com', '9800000001', TRUE, TRUE, 'approved'),
      (v_pat1_uid, v_pat1_uid, 'patient', v_pat1_id, 'Patient One', 'pat1@test.com', '9800000003', TRUE, TRUE, 'approved'),
      (v_pat2_uid, v_pat2_uid, 'patient', v_pat2_id, 'Patient Two', 'pat2@test.com', '9800000004', TRUE, TRUE, 'approved'),
      (v_pharma1_uid, v_pharma1_uid, 'medicalStore', v_store1_id, 'Apollo Meds 1', 'pharma1@test.com', '9800000005', TRUE, TRUE, 'approved'),
      (v_pharma2_uid, v_pharma2_uid, 'medicalStore', v_store2_id, 'Apollo Meds 2', 'pharma2@test.com', '9800000006', TRUE, TRUE, 'approved'),
      (v_lab1_uid, v_lab1_uid, 'lab', v_lab1_id, 'Thyrocare Lab 1', 'lab1@test.com', '9800000007', TRUE, TRUE, 'approved'),
      (v_lab2_uid, v_lab2_uid, 'lab', v_lab2_id, 'Thyrocare Lab 2', 'lab2@test.com', '9800000008', TRUE, TRUE, 'approved'),
      (v_amb1_uid, v_amb1_uid, 'ambulance', v_amb1_id, 'Rapid 108 A', 'amb1@test.com', '9800000009', TRUE, TRUE, 'approved'),
      (v_amb2_uid, v_amb2_uid, 'ambulance', v_amb2_id, 'Rapid 108 B', 'amb2@test.com', '9800000010', TRUE, TRUE, 'approved')
    ON CONFLICT (id) DO UPDATE SET verified = EXCLUDED.verified;

    -- Seed Doctor
    INSERT INTO doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
    VALUES (v_doc1_id, v_doc1_uid, 'Dr. Alpha', 'doc1@test.com', '9800000001', 'Cardiology', 'MD', TRUE, FALSE, TRUE)
    ON CONFLICT (doctor_id) DO NOTHING;

    -- Seed Patients
    INSERT INTO patients (patient_id, owner_uid, name, mobile, share_records_with_doctors, profile_completed, verified)
    VALUES 
      (v_pat1_id, v_pat1_uid, 'Patient One', '9800000003', TRUE, TRUE, TRUE),
      (v_pat2_id, v_pat2_uid, 'Patient Two', '9800000004', TRUE, TRUE, TRUE)
    ON CONFLICT (patient_id) DO NOTHING;

    -- Seed Medical Stores
    INSERT INTO medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email, verified)
    VALUES 
      (v_store1_id, v_pharma1_uid, 'Apollo Meds 1', 'Owner 1', 'DL-001', '9800000005', 'pharma1@test.com', TRUE),
      (v_store2_id, v_pharma2_uid, 'Apollo Meds 2', 'Owner 2', 'DL-002', '9800000006', 'pharma2@test.com', TRUE)
    ON CONFLICT (store_id) DO NOTHING;

    -- Seed Prescriptions
    INSERT INTO prescriptions (prescription_id, doctor_id, patient_id, patient_name, patient_age)
    VALUES 
      ('rx_d_01', v_doc1_id, v_pat1_id, 'Patient One', 35),
      ('rx_d_02', v_doc1_id, v_pat2_id, 'Patient Two', 42)
    ON CONFLICT (prescription_id) DO NOTHING;

    INSERT INTO prescription_medicines (prescription_id, medicine_entry_id, name, dosage, form, frequency, quantity, duration)
    VALUES 
      ('rx_d_01', 'med_01', 'Paracetamol', '500mg', 'tablet', '1-0-1', '10', '5 days'),
      ('rx_d_02', 'med_02', 'Amoxicillin', '250mg', 'capsule', '1-1-1', '15', '5 days')
    ON CONFLICT DO NOTHING;

    -- Seed Pharmacy Deliveries
    INSERT INTO pharmacy_deliveries (delivery_id, prescription_id, doctor_id, store_id, patient_id, doctor_name, store_name, patient_name, status)
    VALUES 
      ('deliv_d_01', 'rx_d_01', v_doc1_id, v_store1_id, v_pat1_id, 'Dr. Alpha', 'Apollo Meds 1', 'Patient One', 'sent'),
      ('deliv_d_02', 'rx_d_02', v_doc1_id, v_store2_id, v_pat2_id, 'Dr. Alpha', 'Apollo Meds 2', 'Patient Two', 'sent')
    ON CONFLICT (delivery_id) DO NOTHING;

    INSERT INTO pharmacy_delivery_medicines (delivery_id, medicine_entry_id, availability)
    VALUES 
      ('deliv_d_01', 'med_01', 'pending'),
      ('deliv_d_02', 'med_02', 'pending')
    ON CONFLICT DO NOTHING;

    -- Seed Labs
    INSERT INTO labs (lab_id, owner_uid, lab_name, license_number, phone, email, verified)
    VALUES 
      (v_lab1_id, v_lab1_uid, 'Thyrocare Lab 1', 'LIC-LAB-01', '9800000007', 'lab1@test.com', TRUE),
      (v_lab2_id, v_lab2_uid, 'Thyrocare Lab 2', 'LIC-LAB-02', '9800000008', 'lab2@test.com', TRUE)
    ON CONFLICT (lab_id) DO NOTHING;

    -- Seed Lab Bookings
    INSERT INTO lab_bookings (booking_id, patient_id, lab_id, patient_name, patient_age, test_id, test_name, test_names, collection_type, date_time, slot_label, status)
    VALUES 
      ('bkg_d_01', v_pat1_id, v_lab1_id, 'Patient One', 35, 'test_cbf', 'Complete Blood Count', ARRAY['Complete Blood Count'], 'labVisit', NOW(), '09:00 AM', 'confirmed'),
      ('bkg_d_02', v_pat2_id, v_lab2_id, 'Patient Two', 42, 'test_lft', 'Liver Function Test', ARRAY['Liver Function Test'], 'labVisit', NOW(), '10:00 AM', 'confirmed')
    ON CONFLICT (booking_id) DO NOTHING;

    -- Seed Lab Orders
    INSERT INTO lab_orders (order_id, doctor_id, patient_id, lab_id, doctor_name, patient_name, patient_age, test_ids, test_names, status)
    VALUES 
      ('ord_d_01', v_doc1_id, v_pat1_id, v_lab1_id, 'Dr. Alpha', 'Patient One', 35, ARRAY['t1'], ARRAY['Lipid Profile'], 'ordered'),
      ('ord_d_02', v_doc1_id, v_pat2_id, v_lab2_id, 'Dr. Alpha', 'Patient Two', 42, ARRAY['t2'], ARRAY['Thyroid Profile'], 'ordered')
    ON CONFLICT (order_id) DO NOTHING;

    -- Seed Ambulances
    INSERT INTO ambulances (ambulance_id, auth_uid, service_name, driver_name, phone, vehicle_number, ambulance_type, city, verified, is_available)
    VALUES 
      (v_amb1_id, v_amb1_uid, 'Rapid 108 A', 'Driver One', '9800000009', 'MH-01-AB-1001', 'als', 'Mumbai', TRUE, TRUE),
      (v_amb2_id, v_amb2_uid, 'Rapid 108 B', 'Driver Two', '9800000010', 'MH-01-AB-1002', 'als', 'Mumbai', TRUE, TRUE)
    ON CONFLICT (ambulance_id) DO NOTHING;

    -- Seed Private Settings
    INSERT INTO ambulance_private_settings (ambulance_id, pin_hash, fcm_token)
    VALUES 
      (v_amb1_id, 'hash_pin_1', 'fcm_amb_1'),
      (v_amb2_id, 'hash_pin_2', 'fcm_amb_2')
    ON CONFLICT (ambulance_id) DO NOTHING;

    -- Seed Ambulance Broadcast
    INSERT INTO ambulance_broadcasts (broadcast_id, patient_id, patient_name, pickup_location, drop_location, status)
    VALUES 
      ('bc_race_01', v_pat1_id, 'Patient One', 'Andheri West', 'Nanavati Hospital', 'pending'),
      ('bc_active_01', v_pat2_id, 'Patient Two', 'Bandra West', 'Lilavati Hospital', 'accepted')
    ON CONFLICT (broadcast_id) DO NOTHING;

    UPDATE ambulance_broadcasts 
    SET accepted_driver_id = v_amb1_id, accepted_driver_name = 'Driver One', accepted_driver_phone = '9800000009'
    WHERE broadcast_id = 'bc_active_01';

    INSERT INTO ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone)
    VALUES 
      ('bc_race_01', '9800000003', NULL),
      ('bc_active_01', '9800000004', '9800000009')
    ON CONFLICT (broadcast_id) DO NOTHING;

    INSERT INTO ambulance_requests (request_id, broadcast_id, driver_id, patient_id, patient_name, pickup_location, drop_location, status)
    VALUES 
      ('req_race_01', 'bc_race_01', v_amb1_id, v_pat1_id, 'Patient One', 'Andheri West', 'Nanavati Hospital', 'pending'),
      ('req_race_02', 'bc_race_01', v_amb2_id, v_pat1_id, 'Patient One', 'Andheri West', 'Nanavati Hospital', 'pending')
    ON CONFLICT (request_id) DO NOTHING;
END $$;

-- ============================================================================
-- TEST 1: CROSS-STORE PHARMACY ISOLATION
-- Store 1 must see ONLY delivery 1 and prescription 1; Store 2 delivery is invisible
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_store_001", "role": "authenticated", "user_role": "medicalStore", "app_role": "medicalStore"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    1,
    'Cross-Store Pharmacy Isolation (sees own delivery only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.pharmacy_deliveries;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    2,
    'Store sees prescription ONLY for its own connected delivery',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.prescriptions;

-- ============================================================================
-- TEST 2: CROSS-LAB ISOLATION
-- Lab 1 must see ONLY booking 1 and order 1; Lab 2 records are invisible
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_lab_001", "role": "authenticated", "user_role": "lab", "app_role": "lab"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    3,
    'Cross-Lab Booking Isolation (sees own booking only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_bookings;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    4,
    'Cross-Lab Order Isolation (sees own order only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_orders;

-- ============================================================================
-- TEST 3: CROSS-DRIVER AMBULANCE ISOLATION
-- Driver 1 must see own private settings; Driver 2 private settings are invisible
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    5,
    'Ambulance Private Settings Isolation (owner-only)',
    '1',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM public.ambulance_private_settings;

DO $$
BEGIN
    PERFORM COUNT(*) FROM public.ambulance_locations;
    INSERT INTO phase_d_test_results VALUES (6, 'Ambulance raw locations table denied to authenticated client', '42501', 'READ_ALLOWED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (6, 'Ambulance raw locations table denied to authenticated client', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (6, 'Ambulance raw locations table denied to authenticated client', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- ============================================================================
-- TEST 4: UNRELATED PATIENT BLOCKED
-- Patient 2 must NOT see Patient 1 deliveries, bookings, orders, or broadcasts
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_002", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    7,
    'Patient 2 cannot see Patient 1 pharmacy delivery',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.pharmacy_deliveries
WHERE delivery_id = 'deliv_d_01';

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    8,
    'Patient 2 cannot see Patient 1 lab booking',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_bookings
WHERE booking_id = 'bkg_d_01';

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    9,
    'Patient 2 cannot see Patient 1 lab order',
    '0',
    COUNT(*)::text,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.lab_orders
WHERE order_id = 'ord_d_01';

-- ============================================================================
-- TEST 5: DOUBLE-ACCEPT RACE SAFETY (accept_ambulance_request)
-- Driver 1 accepts -> succeeds. Driver 2 accepts same broadcast -> raises 42501
-- Sibling request for Driver 2 is automatically marked 'taken'
-- ============================================================================
-- Switch to Driver 1
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.accept_ambulance_request('bc_race_01', 'req_race_01');
    IF v_res ->> 'success' = 'true' THEN
        INSERT INTO phase_d_test_results VALUES (10, 'Double-Accept Race (first driver succeeds)', 'true', 'true', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (10, 'Double-Accept Race (first driver succeeds)', 'true', 'false', 'FAIL');
    END IF;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO phase_d_test_results VALUES (10, 'Double-Accept Race (first driver succeeds)', 'true', SQLERRM, 'FAIL');
END $$;

-- Switch to Driver 2 attempting to accept the same broadcast
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_002", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.accept_ambulance_request('bc_race_01', 'req_race_02');
    -- Should not reach here
    INSERT INTO phase_d_test_results VALUES (11, 'Double-Accept Race (second driver blocked with 42501)', '42501', 'SUCCEEDED_UNEXPECTEDLY', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (11, 'Double-Accept Race (second driver blocked with 42501)', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (11, 'Double-Accept Race (second driver blocked with 42501)', '42501', SQLSTATE || ': ' || SQLERRM, 'FAIL');
    END IF;
END $$;

-- Verify sibling request status became 'taken'
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_002", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    12,
    'Sibling request automatically marked taken for losing driver',
    'taken',
    status,
    CASE WHEN status = 'taken' THEN 'PASS' ELSE 'FAIL' END
FROM public.ambulance_requests
WHERE request_id = 'req_race_02';

-- ============================================================================
-- TEST 6: ANON BLOCKED FROM EVERY RPC
-- Anonymous / unauthenticated callers must be rejected from every Phase D RPC
-- ============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

-- RPC 1: update_pharmacy_delivery_status
DO $$
BEGIN
    PERFORM public.update_pharmacy_delivery_status('deliv_d_01', 'processing');
    INSERT INTO phase_d_test_results VALUES (13, 'Anon blocked from update_pharmacy_delivery_status', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (13, 'Anon blocked from update_pharmacy_delivery_status', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (13, 'Anon blocked from update_pharmacy_delivery_status', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 2: update_lab_booking_status
DO $$
BEGIN
    PERFORM public.update_lab_booking_status('bkg_d_01', 'sampleCollected');
    INSERT INTO phase_d_test_results VALUES (14, 'Anon blocked from update_lab_booking_status', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (14, 'Anon blocked from update_lab_booking_status', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (14, 'Anon blocked from update_lab_booking_status', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 3: update_lab_order_status
DO $$
BEGIN
    PERFORM public.update_lab_order_status('ord_d_01', 'received');
    INSERT INTO phase_d_test_results VALUES (15, 'Anon blocked from update_lab_order_status', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (15, 'Anon blocked from update_lab_order_status', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (15, 'Anon blocked from update_lab_order_status', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 4: accept_ambulance_request
DO $$
BEGIN
    PERFORM public.accept_ambulance_request('bc_race_01');
    INSERT INTO phase_d_test_results VALUES (16, 'Anon blocked from accept_ambulance_request', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (16, 'Anon blocked from accept_ambulance_request', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (16, 'Anon blocked from accept_ambulance_request', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 5: complete_ambulance_trip
DO $$
BEGIN
    PERFORM public.complete_ambulance_trip('bc_active_01');
    INSERT INTO phase_d_test_results VALUES (17, 'Anon blocked from complete_ambulance_trip', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (17, 'Anon blocked from complete_ambulance_trip', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (17, 'Anon blocked from complete_ambulance_trip', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 6: cancel_ambulance_broadcast
DO $$
BEGIN
    PERFORM public.cancel_ambulance_broadcast('bc_active_01');
    INSERT INTO phase_d_test_results VALUES (18, 'Anon blocked from cancel_ambulance_broadcast', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (18, 'Anon blocked from cancel_ambulance_broadcast', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (18, 'Anon blocked from cancel_ambulance_broadcast', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 7: update_ambulance_location
DO $$
BEGIN
    PERFORM public.update_ambulance_location('bc_active_01', 19.0760, 72.8777);
    INSERT INTO phase_d_test_results VALUES (19, 'Anon blocked from update_ambulance_location', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (19, 'Anon blocked from update_ambulance_location', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (19, 'Anon blocked from update_ambulance_location', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 8: get_ambulance_trip_location
DO $$
BEGIN
    PERFORM public.get_ambulance_trip_location('bc_active_01');
    INSERT INTO phase_d_test_results VALUES (20, 'Anon blocked from get_ambulance_trip_location', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (20, 'Anon blocked from get_ambulance_trip_location', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (20, 'Anon blocked from get_ambulance_trip_location', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 9: get_ambulance_trip_contact
DO $$
BEGIN
    PERFORM public.get_ambulance_trip_contact('bc_active_01');
    INSERT INTO phase_d_test_results VALUES (21, 'Anon blocked from get_ambulance_trip_contact', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (21, 'Anon blocked from get_ambulance_trip_contact', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (21, 'Anon blocked from get_ambulance_trip_contact', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- RPC 10: expire_stale_ambulance_broadcasts
DO $$
BEGIN
    PERFORM public.expire_stale_ambulance_broadcasts();
    INSERT INTO phase_d_test_results VALUES (22, 'Anon blocked from expire_stale_ambulance_broadcasts', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (22, 'Anon blocked from expire_stale_ambulance_broadcasts', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (22, 'Anon blocked from expire_stale_ambulance_broadcasts', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- ============================================================================
-- TEST 7: COLUMN LOCKS (status, verified, rating)
-- Direct client UPDATE on status/verified/rating must raise 42501
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_store_001", "role": "authenticated", "user_role": "medicalStore", "app_role": "medicalStore"}', true);
SET LOCAL ROLE authenticated;

SELECT set_config('app.allow_delivery_status_change', '', true);
SELECT set_config('app.allow_lab_status_change', '', true);
SELECT set_config('app.allow_ambulance_status_change', '', true);

-- Direct UPDATE on pharmacy_deliveries.status -> BLOCKED
DO $$
BEGIN
    UPDATE public.pharmacy_deliveries SET status = 'delivered' WHERE delivery_id = 'deliv_d_01';
    INSERT INTO phase_d_test_results VALUES (23, 'Column Lock: Direct UPDATE pharmacy status blocked', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (23, 'Column Lock: Direct UPDATE pharmacy status blocked', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (23, 'Column Lock: Direct UPDATE pharmacy status blocked', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Direct UPDATE on medical_stores.verified -> BLOCKED
DO $$
BEGIN
    UPDATE public.medical_stores SET verified = FALSE WHERE store_id = 'ms_001';
    -- Column lock trigger prevents changing verified
    INSERT INTO phase_d_test_results VALUES (24, 'Column Lock: Direct UPDATE medical_stores verified locked', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (24, 'Column Lock: Direct UPDATE medical_stores verified locked', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (24, 'Column Lock: Direct UPDATE medical_stores verified locked', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Direct UPDATE on lab_bookings.status -> BLOCKED
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_lab_001", "role": "authenticated", "user_role": "lab", "app_role": "lab"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.lab_bookings SET status = 'completed' WHERE booking_id = 'bkg_d_01';
    INSERT INTO phase_d_test_results VALUES (25, 'Column Lock: Direct UPDATE lab booking status blocked', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (25, 'Column Lock: Direct UPDATE lab booking status blocked', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (25, 'Column Lock: Direct UPDATE lab booking status blocked', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Direct UPDATE on lab_orders.status -> BLOCKED
DO $$
BEGIN
    UPDATE public.lab_orders SET status = 'completed' WHERE order_id = 'ord_d_01';
    INSERT INTO phase_d_test_results VALUES (26, 'Column Lock: Direct UPDATE lab order status blocked', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (26, 'Column Lock: Direct UPDATE lab order status blocked', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (26, 'Column Lock: Direct UPDATE lab order status blocked', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Direct UPDATE on ambulance_broadcasts.status -> BLOCKED
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.ambulance_broadcasts SET status = 'completed' WHERE broadcast_id = 'bc_active_01';
    INSERT INTO phase_d_test_results VALUES (27, 'Column Lock: Direct UPDATE ambulance broadcast status blocked', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (27, 'Column Lock: Direct UPDATE ambulance broadcast status blocked', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (27, 'Column Lock: Direct UPDATE ambulance broadcast status blocked', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Driver cannot rate themselves on ambulance_broadcasts
DO $$
BEGIN
    UPDATE public.ambulance_broadcasts SET rating = 5 WHERE broadcast_id = 'bc_active_01';
    INSERT INTO phase_d_test_results VALUES (28, 'Column Lock: Driver cannot update rating on ambulance trip', '42501', 'PASSED', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (28, 'Column Lock: Driver cannot update rating on ambulance trip', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (28, 'Column Lock: Driver cannot update rating on ambulance trip', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- ============================================================================
-- TEST 8: VALIDATED PHARMACY STATE MACHINE VIA RPC
-- Valid transitions: sent -> processing -> dispatched -> delivered
-- Patient cancel after dispatch is blocked with 42501
-- ============================================================================
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_store_001", "role": "authenticated", "user_role": "medicalStore", "app_role": "medicalStore"}', true);
SET LOCAL ROLE authenticated;

-- Valid transition: sent -> processing
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.update_pharmacy_delivery_status('deliv_d_01', 'processing', 'Medicines verified and packed');
    IF v_res ->> 'success' = 'true' AND v_res ->> 'new_status' = 'processing' THEN
        INSERT INTO phase_d_test_results VALUES (29, 'Pharmacy State Machine (sent -> processing)', 'processing', v_res ->> 'new_status', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (29, 'Pharmacy State Machine (sent -> processing)', 'processing', v_res::text, 'FAIL');
    END IF;
END $$;

-- Valid transition: processing -> dispatched
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.update_pharmacy_delivery_status('deliv_d_01', 'dispatched', 'Out for delivery with rider');
    IF v_res ->> 'success' = 'true' AND v_res ->> 'new_status' = 'dispatched' THEN
        INSERT INTO phase_d_test_results VALUES (30, 'Pharmacy State Machine (processing -> dispatched)', 'dispatched', v_res ->> 'new_status', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (30, 'Pharmacy State Machine (processing -> dispatched)', 'dispatched', v_res::text, 'FAIL');
    END IF;
END $$;

-- Patient attempts to cancel AFTER dispatch -> BLOCKED with 42501
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_001", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.update_pharmacy_delivery_status('deliv_d_01', 'cancelled');
    INSERT INTO phase_d_test_results VALUES (31, 'Pharmacy State Machine (patient cancel blocked after dispatch)', '42501', 'CANCELLED_UNEXPECTEDLY', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (31, 'Pharmacy State Machine (patient cancel blocked after dispatch)', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (31, 'Pharmacy State Machine (patient cancel blocked after dispatch)', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- ============================================================================
-- TEST 9: LAB S3 REPORT CONFIRM & AUTO-LINK TO HEALTH RECORDS
-- Uploading S3 report to lab_bookings triggers auto-insert into health_records
-- ============================================================================
RESET ROLE;
SET LOCAL ROLE postgres;

-- S3 report confirmed by storage webhook
UPDATE public.lab_bookings
SET report_s3_key = 'lab_reports/bkg_d_01_report.pdf',
    report_s3_bucket = 'doctornect-clinical-vault',
    report_file_size_bytes = 1048576,
    report_mime_type = 'application/pdf',
    report_uploaded_at = NOW()
WHERE booking_id = 'bkg_d_01';

INSERT INTO phase_d_test_results (test_num, test_name, expected, actual, status)
SELECT 
    32,
    'Lab report auto-linked to patient health_records via trigger',
    'labReport',
    type,
    CASE WHEN type = 'labReport' AND s3_key = 'lab_reports/bkg_d_01_report.pdf' THEN 'PASS' ELSE 'FAIL' END
FROM public.health_records
WHERE record_id = 'hr_bkg_bkg_d_01';

-- ============================================================================
-- TEST 10: AMBULANCE LIVE LOCATION & CONTACT PRIVACY
-- Location updates & refetch only during active trip; contacts counterpart only
-- ============================================================================
-- Driver 1 transmits location for active trip 'bc_active_01'
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.update_ambulance_location('bc_active_01', 19.0760, 72.8777, 45.0, 30.5);
    IF v_res ->> 'success' = 'true' THEN
        INSERT INTO phase_d_test_results VALUES (33, 'Driver transmits live location for active trip', 'true', 'true', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (33, 'Driver transmits live location for active trip', 'true', 'false', 'FAIL');
    END IF;
END $$;

-- Counterpart Patient 2 queries live trip location -> coordinates returned
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_002", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.get_ambulance_trip_location('bc_active_01');
    IF v_res ->> 'active' = 'true' AND (v_res ->> 'latitude')::numeric = 19.0760 THEN
        INSERT INTO phase_d_test_results VALUES (34, 'Patient reads live location during active trip', '19.076', v_res ->> 'latitude', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (34, 'Patient reads live location during active trip', '19.076', v_res::text, 'FAIL');
    END IF;
END $$;

-- Counterpart Patient 2 queries driver phone -> returned during active trip
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.get_ambulance_trip_contact('bc_active_01');
    IF v_res ->> 'driver_phone' = '9800000009' THEN
        INSERT INTO phase_d_test_results VALUES (35, 'Patient reads driver phone during active trip', '9800000009', v_res ->> 'driver_phone', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (35, 'Patient reads driver phone during active trip', '9800000009', v_res::text, 'FAIL');
    END IF;
END $$;

-- Unrelated Driver 2 attempts to query trip contact for 'bc_active_01' -> BLOCKED with 42501
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_002", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.get_ambulance_trip_contact('bc_active_01');
    INSERT INTO phase_d_test_results VALUES (36, 'Unrelated driver blocked from trip contact', '42501', 'READ_UNEXPECTEDLY', 'FAIL');
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN
        INSERT INTO phase_d_test_results VALUES (36, 'Unrelated driver blocked from trip contact', '42501', SQLSTATE, 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (36, 'Unrelated driver blocked from trip contact', '42501', SQLSTATE, 'FAIL');
    END IF;
END $$;

-- Assigned Driver completes trip
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_amb_001", "role": "authenticated", "user_role": "ambulance", "app_role": "ambulance"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.complete_ambulance_trip('bc_active_01');
    IF v_res ->> 'status' = 'completed' THEN
        INSERT INTO phase_d_test_results VALUES (37, 'Driver completes ambulance trip', 'completed', v_res ->> 'status', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (37, 'Driver completes ambulance trip', 'completed', v_res::text, 'FAIL');
    END IF;
END $$;

-- Live location coordinates deleted and return NULL after trip completion
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.get_ambulance_trip_location('bc_active_01');
    IF v_res ->> 'active' = 'false' AND v_res ->> 'location' IS NULL THEN
        INSERT INTO phase_d_test_results VALUES (38, 'Location wiped and returns NULL after trip completion', 'false', v_res ->> 'active', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (38, 'Location wiped and returns NULL after trip completion', 'false', v_res::text, 'FAIL');
    END IF;
END $$;

-- Contact driver phone wiped after trip completion
SELECT set_config('request.jwt.claims', '{"sub": "fb_uid_pat_002", "role": "authenticated", "user_role": "patient", "app_role": "patient"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.get_ambulance_trip_contact('bc_active_01');
    IF v_res ->> 'active' = 'false' AND v_res ->> 'driver_phone' IS NULL THEN
        INSERT INTO phase_d_test_results VALUES (39, 'Driver phone hidden after trip completion', 'NULL', 'NULL', 'PASS');
    ELSE
        INSERT INTO phase_d_test_results VALUES (39, 'Driver phone hidden after trip completion', 'NULL', v_res ->> 'driver_phone', 'FAIL');
    END IF;
END $$;

-- ============================================================================
-- SUMMARY OUTPUT
-- ============================================================================
RESET ROLE;
SET LOCAL ROLE postgres;

SELECT 
    test_num,
    test_name,
    expected,
    actual,
    status
FROM phase_d_test_results
ORDER BY test_num;

SELECT 
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status = 'FAIL') AS failed
FROM phase_d_test_results;

ROLLBACK;
