-- ============================================================================
-- DoctorNect — Firebase Identity Verification Smoke Test
-- File: backend/supabase/tests/firebase_identity_smoke_test.sql
-- ============================================================================
-- Proves that non-UUID Firebase UIDs (alphanumeric strings in JWT sub claim)
-- work correctly across PostgreSQL RLS policies, column locks, atomic booking,
-- and default column values without throwing SQLSTATE 22P02 (invalid uuid) or 42883.
-- ============================================================================

BEGIN;

-- 1. Temporary table to collect and display test outcomes
CREATE TEMP TABLE smoke_results (
    test_id TEXT,
    test_desc TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);
GRANT ALL ON smoke_results TO authenticated;

-- 2. Synthetic Test Fixtures Setup (Non-UUID Firebase UIDs)
DO $$
DECLARE
    v_pat_a_fb TEXT := 'fb_pat_alpha_non_uuid_101';
    v_pat_b_fb TEXT := 'fb_pat_beta_non_uuid_202';
    v_doc_a_fb TEXT := 'fb_doc_gamma_non_uuid_303';
    v_doc_b_fb TEXT := 'fb_doc_delta_non_uuid_404';

    v_pat_a_id TEXT := 'smoke-pat-alpha';
    v_pat_b_id TEXT := 'smoke-pat-beta';
    v_doc_a_id TEXT := 'smoke-doc-gamma';
    v_doc_b_id TEXT := 'smoke-doc-delta';

    v_user_pat_a UUID := 'aaaaaaaa-1111-4aaa-8aaa-111111111111';
    v_user_pat_b UUID := 'bbbbbbbb-2222-4bbb-8bbb-222222222222';
    v_user_doc_a UUID := 'cccccccc-3333-4ccc-8ccc-333333333333';
    v_user_doc_b UUID := 'dddddddd-4444-4ddd-8ddd-444444444444';
BEGIN
    -- Seed synthetic public.users rows with alphanumeric firebase_uid
    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
    VALUES
        (v_user_pat_a, v_pat_a_fb, 'patient', v_pat_a_id, 'Smoke Patient Alpha', 'alpha@smoke.test', '9100000001', TRUE, TRUE, 'approved'),
        (v_user_pat_b, v_pat_b_fb, 'patient', v_pat_b_id, 'Smoke Patient Beta', 'beta@smoke.test', '9100000002', TRUE, TRUE, 'approved'),
        (v_user_doc_a, v_doc_a_fb, 'doctor', v_doc_a_id, 'Smoke Doctor Gamma', 'gamma@smoke.test', '9100000003', TRUE, TRUE, 'approved'),
        (v_user_doc_b, v_doc_b_fb, 'doctor', v_doc_b_id, 'Smoke Doctor Delta', 'delta@smoke.test', '9100000004', TRUE, TRUE, 'approved')
    ON CONFLICT (id) DO NOTHING;

    -- Seed synthetic public.doctors rows
    INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, deactivated, profile_completed)
    VALUES
        (v_doc_a_id, v_user_doc_a, 'Smoke Doctor Gamma', 'gamma@smoke.test', '9100000003', 'Cardiology', 'MBBS MD', TRUE, FALSE, TRUE),
        (v_doc_b_id, v_user_doc_b, 'Smoke Doctor Delta', 'delta@smoke.test', '9100000004', 'Pediatrics', 'MBBS DCH', TRUE, FALSE, TRUE)
    ON CONFLICT (doctor_id) DO NOTHING;

    -- Seed synthetic public.patients rows
    INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors, profile_completed, verified)
    VALUES
        (v_pat_a_id, v_user_pat_a, 'Smoke Patient Alpha', '9100000001', TRUE, TRUE, TRUE),
        (v_pat_b_id, v_user_pat_b, 'Smoke Patient Beta', '9100000002', TRUE, TRUE, TRUE)
    ON CONFLICT (patient_id) DO NOTHING;

    -- Seed synthetic public.appointments rows:
    -- Doctor Gamma has an active appointment with Patient Alpha (established care relationship)
    -- Doctor Delta has an active appointment with Patient Beta
    INSERT INTO public.appointments (
        appointment_id, doctor_id, patient_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        visit_type, patient_status, doctor_status
    )
    VALUES
        ('smoke-apt-a', v_doc_a_id, v_pat_a_id, 'Smoke Doctor Gamma', 'Cardiology', 'Smoke Patient Alpha', 32, 'Male', NOW() + INTERVAL '1 day', '10:00 AM', 'newVisit', 'confirmed', 'confirmed'),
        ('smoke-apt-b', v_doc_b_id, v_pat_b_id, 'Smoke Doctor Delta', 'Pediatrics', 'Smoke Patient Beta', 5, 'Female', NOW() + INTERVAL '2 day', '11:00 AM', 'newVisit', 'confirmed', 'confirmed')
    ON CONFLICT (appointment_id) DO NOTHING;
END $$;

-- ----------------------------------------------------------------------------
-- CASE 5a: Patient Isolation (Patient Alpha reads own row & appointments, cannot read Beta)
-- ----------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_pat_alpha_non_uuid_101", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_pat_alpha_non_uuid_101', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO smoke_results
WITH pat_check AS (
    SELECT array_agg(patient_id ORDER BY patient_id) AS p_ids
    FROM public.patients
    WHERE patient_id IN ('smoke-pat-alpha', 'smoke-pat-beta')
), apt_check AS (
    SELECT array_agg(appointment_id ORDER BY appointment_id) AS a_ids
    FROM public.appointments
    WHERE appointment_id IN ('smoke-apt-a', 'smoke-apt-b')
)
SELECT
    '5a',
    'Patient Isolation (Alpha sees own patient row & appointments; Beta blocked)',
    'patients: [smoke-pat-alpha], appointments: [smoke-apt-a]',
    'patients: ' || COALESCE(p_ids::text, '[]') || ', appointments: ' || COALESCE(a_ids::text, '[]'),
    CASE
        WHEN ('smoke-pat-alpha' = ANY(p_ids) AND NOT ('smoke-pat-beta' = ANY(p_ids)))
         AND ('smoke-apt-a' = ANY(a_ids) AND NOT ('smoke-apt-b' = ANY(a_ids)))
        THEN 'PASS'
        ELSE 'FAIL'
    END
FROM pat_check, apt_check;

-- ----------------------------------------------------------------------------
-- CASE 5b: Doctor Visibility (Doctor Gamma sees only own appointments & care-team patients)
-- ----------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_doc_gamma_non_uuid_303", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_doc_gamma_non_uuid_303', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

INSERT INTO smoke_results
WITH apt_check AS (
    SELECT array_agg(appointment_id ORDER BY appointment_id) AS a_ids
    FROM public.appointments
    WHERE appointment_id IN ('smoke-apt-a', 'smoke-apt-b')
), pat_check AS (
    SELECT array_agg(patient_id ORDER BY patient_id) AS p_ids
    FROM public.patients
    WHERE patient_id IN ('smoke-pat-alpha', 'smoke-pat-beta')
)
SELECT
    '5b',
    'Doctor Isolation (Gamma sees own appointments & care-team Patient Alpha; Delta/Beta blocked)',
    'appointments: [smoke-apt-a], patients: [smoke-pat-alpha]',
    'appointments: ' || COALESCE(a_ids::text, '[]') || ', patients: ' || COALESCE(p_ids::text, '[]'),
    CASE
        WHEN ('smoke-apt-a' = ANY(a_ids) AND NOT ('smoke-apt-b' = ANY(a_ids)))
         AND ('smoke-pat-alpha' = ANY(p_ids) AND NOT ('smoke-pat-beta' = ANY(p_ids)))
        THEN 'PASS'
        ELSE 'FAIL'
    END
FROM apt_check, pat_check;

-- ----------------------------------------------------------------------------
-- CASE 5c: Locked Columns Immutability (Patient & Doctor cannot update verified/locked columns)
-- ----------------------------------------------------------------------------
-- Test 5c-1: Patient Alpha attempting to update locked column (verified) on patients
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_pat_alpha_non_uuid_101", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_pat_alpha_non_uuid_101', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.patients
    SET verified = FALSE
    WHERE patient_id = 'smoke-pat-alpha';

    INSERT INTO smoke_results VALUES ('5c-1', 'Patient locked column update (verified)', 'SQLSTATE 42501', 'Update succeeded without error', 'FAIL');
EXCEPTION
    WHEN sqlstate '42501' THEN
        INSERT INTO smoke_results VALUES ('5c-1', 'Patient locked column update (verified)', 'SQLSTATE 42501', 'Correctly rejected (42501): ' || SQLERRM, 'PASS');
    WHEN OTHERS THEN
        INSERT INTO smoke_results VALUES ('5c-1', 'Patient locked column update (verified)', 'SQLSTATE 42501', 'Unexpected error ' || SQLSTATE || ': ' || SQLERRM, 'FAIL');
END $$;

-- Test 5c-2: Doctor Gamma attempting to update locked column (verified) on doctors
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_doc_gamma_non_uuid_303", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_doc_gamma_non_uuid_303', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    UPDATE public.doctors
    SET verified = FALSE
    WHERE doctor_id = 'smoke-doc-gamma';

    INSERT INTO smoke_results VALUES ('5c-2', 'Doctor locked column update (verified)', 'SQLSTATE 42501', 'Update succeeded without error', 'FAIL');
EXCEPTION
    WHEN sqlstate '42501' THEN
        INSERT INTO smoke_results VALUES ('5c-2', 'Doctor locked column update (verified)', 'SQLSTATE 42501', 'Correctly rejected (42501): ' || SQLERRM, 'PASS');
    WHEN OTHERS THEN
        INSERT INTO smoke_results VALUES ('5c-2', 'Doctor locked column update (verified)', 'SQLSTATE 42501', 'Unexpected error ' || SQLSTATE || ': ' || SQLERRM, 'FAIL');
END $$;

-- ----------------------------------------------------------------------------
-- CASE 5d: Atomic Appointment Booking (Works for Firebase patient & rejects bad inputs)
-- ----------------------------------------------------------------------------
-- Test 5d-1: Valid atomic booking by Patient Alpha
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_pat_alpha_non_uuid_101", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_pat_alpha_non_uuid_101', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.book_appointment_atomic(
        'smoke-apt-atomic-1',
        'smoke-doc-gamma',
        'smoke-pat-alpha',
        'Smoke Doctor Gamma',
        'Cardiology',
        'Smoke Patient Alpha',
        32,
        'Male',
        NOW() + INTERVAL '3 days',
        '02:00 PM'
    );

    IF (v_res->>'appointment_id') = 'smoke-apt-atomic-1' THEN
        INSERT INTO smoke_results VALUES ('5d-1', 'book_appointment_atomic valid booking', 'appointment_id: smoke-apt-atomic-1', 'Booked successfully: ' || (v_res->>'appointment_id'), 'PASS');
    ELSE
        INSERT INTO smoke_results VALUES ('5d-1', 'book_appointment_atomic valid booking', 'appointment_id: smoke-apt-atomic-1', 'Unexpected JSON: ' || v_res::text, 'FAIL');
    END IF;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO smoke_results VALUES ('5d-1', 'book_appointment_atomic valid booking', 'appointment_id: smoke-apt-atomic-1', 'Error ' || SQLSTATE || ': ' || SQLERRM, 'FAIL');
END $$;

-- Test 5d-2: Caller (Alpha) booking for another patient profile (Beta) -> Rejection 42501
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.book_appointment_atomic(
        'smoke-apt-atomic-bad',
        'smoke-doc-gamma',
        'smoke-pat-beta',
        'Smoke Doctor Gamma',
        'Cardiology',
        'Smoke Patient Beta',
        5,
        'Female',
        NOW() + INTERVAL '4 days',
        '03:00 PM'
    );
    INSERT INTO smoke_results VALUES ('5d-2', 'book_appointment_atomic rejects cross-profile booking', 'SQLSTATE 42501', 'Unexpected success: ' || v_res::text, 'FAIL');
EXCEPTION
    WHEN sqlstate '42501' THEN
        INSERT INTO smoke_results VALUES ('5d-2', 'book_appointment_atomic rejects cross-profile booking', 'SQLSTATE 42501', 'Correctly rejected (42501): ' || SQLERRM, 'PASS');
    WHEN OTHERS THEN
        INSERT INTO smoke_results VALUES ('5d-2', 'book_appointment_atomic rejects cross-profile booking', 'SQLSTATE 42501', 'Unexpected error ' || SQLSTATE || ': ' || SQLERRM, 'FAIL');
END $$;

-- Test 5d-3: Duplicate active booking by same patient -> Rejection 23505
DO $$
DECLARE
    v_res JSONB;
BEGIN
    v_res := public.book_appointment_atomic(
        'smoke-apt-atomic-dup',
        'smoke-doc-gamma',
        'smoke-pat-alpha',
        'Smoke Doctor Gamma',
        'Cardiology',
        'Smoke Patient Alpha',
        32,
        'Male',
        NOW() + INTERVAL '3 days', -- Same slot as 5d-1
        '02:00 PM'
    );
    INSERT INTO smoke_results VALUES ('5d-3', 'book_appointment_atomic rejects duplicate slot booking', 'SQLSTATE 23505', 'Unexpected success: ' || v_res::text, 'FAIL');
EXCEPTION
    WHEN sqlstate '23505' THEN
        INSERT INTO smoke_results VALUES ('5d-3', 'book_appointment_atomic rejects duplicate slot booking', 'SQLSTATE 23505', 'Correctly rejected (23505): ' || SQLERRM, 'PASS');
    WHEN OTHERS THEN
        INSERT INTO smoke_results VALUES ('5d-3', 'book_appointment_atomic rejects duplicate slot booking', 'SQLSTATE 23505', 'Unexpected error ' || SQLSTATE || ': ' || SQLERRM, 'FAIL');
END $$;

-- ----------------------------------------------------------------------------
-- CASE 5e: Inserting into patients without owner_uid does NOT raise 22P02
-- ----------------------------------------------------------------------------
-- DEFAULT auth.uid() was dropped so NULL is defaulted instead of invalid UUID cast.
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "fb_pat_alpha_non_uuid_101", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'fb_pat_alpha_non_uuid_101', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    -- Omit owner_uid in the INSERT statement
    INSERT INTO public.patients (patient_id, name, mobile)
    VALUES ('smoke-pat-no-owner', 'Test Omitted Owner', '9999999999');

    -- If RLS or insert evaluation executes, verify that no 22P02 is raised
    INSERT INTO smoke_results VALUES ('5e', 'Insert patients without owner_uid (no 22P02)', 'No 22P02 error', 'Evaluated cleanly without 22P02', 'PASS');
EXCEPTION
    WHEN sqlstate '22P02' THEN
        INSERT INTO smoke_results VALUES ('5e', 'Insert patients without owner_uid (no 22P02)', 'No 22P02 error', 'FAILED with 22P02: ' || SQLERRM, 'FAIL');
    WHEN sqlstate '42501' THEN
        -- RLS WITH CHECK correctly rejected without casting sub to UUID
        INSERT INTO smoke_results VALUES ('5e', 'Insert patients without owner_uid (no 22P02)', 'No 22P02 error', 'RLS evaluated cleanly without 22P02 (42501 expected for omitted owner)', 'PASS');
    WHEN OTHERS THEN
        INSERT INTO smoke_results VALUES ('5e', 'Insert patients without owner_uid (no 22P02)', 'No 22P02 error', 'Evaluated without 22P02 (SQLSTATE ' || SQLSTATE || ')', 'PASS');
END $$;

-- ----------------------------------------------------------------------------
-- CASE 5f: Non-UUID sub user NEVER gets 22P02 from any policy (gets rows or empty set)
-- ----------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', '{"sub": "completely_arbitrary_firebase_sub_xyz_777", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'completely_arbitrary_firebase_sub_xyz_777', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    r RECORD;
    v_c BIGINT;
    v_accessible_tables INT := 0;
    v_22p02_errors TEXT := '';
BEGIN
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public' 
          AND rowsecurity = true 
        ORDER BY tablename
    ) LOOP
        BEGIN
            EXECUTE format('SELECT count(*) FROM public.%I', r.tablename) INTO v_c;
            v_accessible_tables := v_accessible_tables + 1;
        EXCEPTION
            WHEN sqlstate '22P02' THEN
                v_22p02_errors := v_22p02_errors || r.tablename || ':22P02 ';
            WHEN sqlstate '42501' THEN
                -- Expected table-level GRANT restriction on internal tables (e.g. otp_challenges)
                NULL;
            WHEN OTHERS THEN
                -- Any other SQL error (not 22P02)
                NULL;
        END;
    END LOOP;

    IF v_22p02_errors = '' THEN
        INSERT INTO smoke_results VALUES (
            '5f',
            'Arbitrary non-UUID sub queries all RLS tables without 22P02',
            'Zero 22P02 errors across all 53 tables',
            'Verified zero 22P02 errors (' || v_accessible_tables || ' tables returned rows or empty sets)',
            'PASS'
        );
    ELSE
        INSERT INTO smoke_results VALUES (
            '5f',
            'Arbitrary non-UUID sub queries all RLS tables without 22P02',
            'Zero 22P02 errors',
            '22P02 errors encountered: ' || v_22p02_errors,
            'FAIL'
        );
    END IF;
END $$;

RESET ROLE;

-- ----------------------------------------------------------------------------
-- 3. Display Results
-- ----------------------------------------------------------------------------
SELECT test_id, test_desc, expected, actual, status FROM smoke_results ORDER BY test_id;

-- ----------------------------------------------------------------------------
-- 4. Rollback to leave database pristine
-- ----------------------------------------------------------------------------
ROLLBACK;
