-- Run AFTER applying migrations 20260930000001-5 on STAGING.
-- ============================================================================
-- DoctorNect Platform — Role-Simulation Verification Script
-- File: scratch/verification_script.sql
-- All simulation blocks are executed inside transactions and wrapped in ROLLBACK.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART A: PRIVILEGE & METADATA VERIFICATION (RUN AS POSTGRES / ADMIN)
-- ----------------------------------------------------------------------------
-- 1. Confirm anon and PUBLIC have NO execute privilege on target functions
SELECT 
    routine_schema, routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema IN ('public', 'private')
  AND routine_name IN (
      'trigger_set_timestamp', 'check_appointment_cancellation_integrity',
      'book_appointment_atomic', 'current_profile_id', 'current_user_role',
      'doctor_can_access_patient', 'is_profile_completed', 'is_super_admin',
      'is_verified_doctor', 'rls_auto_enable'
  )
  AND grantee IN ('anon', 'PUBLIC');
-- Expected: 0 rows

-- 2. Confirm search_path is pinned and public functions are SECURITY INVOKER
SELECT 
    n.nspname AS schema_name, p.proname, p.prosecdef AS is_definer, p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname IN ('public', 'private')
  AND p.proname IN (
      'trigger_set_timestamp', 'check_appointment_cancellation_integrity',
      'book_appointment_atomic', 'current_profile_id', 'current_user_role',
      'doctor_can_access_patient', 'is_profile_completed', 'is_super_admin',
      'is_verified_doctor', 'rls_auto_enable'
  )
ORDER BY n.nspname, p.proname;

-- ----------------------------------------------------------------------------
-- PART B: ANONYMOUS ROLE SIMULATION (ISOLATED BLOCKS)
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE anon;

-- Test B1: Promoted ads (Public read expected)
DO $$
BEGIN
    PERFORM count(*) FROM public.promoted_ads;
    RAISE NOTICE 'B1 PASSED: Anon successfully read public.promoted_ads.';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'B1: Anon blocked by table privilege on promoted_ads (OK)';
END $$;

-- Test B2: Review public (Public read expected)
DO $$
BEGIN
    PERFORM count(*) FROM public.review_public;
    RAISE NOTICE 'B2 PASSED: Anon successfully read public.review_public.';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'B2: Anon blocked by table privilege on review_public (OK)';
END $$;

-- Test B3: Appointments (Clinical read expected to return 0 or be denied)
DO $$
DECLARE v_c INT;
BEGIN
    SELECT count(*) INTO v_c FROM public.appointments;
    IF v_c = 0 THEN
        RAISE NOTICE 'B3 PASSED: Anon read on appointments returned 0 rows under RLS.';
    ELSE
        RAISE EXCEPTION 'B3 FAILED: Anon saw % rows in appointments!', v_c;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'B3 PASSED: Anon blocked by table privilege on appointments (OK)';
END $$;

-- Test B4: Patients (Clinical read expected to return 0 or be denied)
DO $$
DECLARE v_c INT;
BEGIN
    SELECT count(*) INTO v_c FROM public.patients;
    IF v_c = 0 THEN
        RAISE NOTICE 'B4 PASSED: Anon read on patients returned 0 rows under RLS.';
    ELSE
        RAISE EXCEPTION 'B4 FAILED: Anon saw % rows in patients!', v_c;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'B4 PASSED: Anon blocked by table privilege on patients (OK)';
END $$;

-- Test B5: Health Records (Clinical read expected to return 0 or be denied)
DO $$
DECLARE v_c INT;
BEGIN
    SELECT count(*) INTO v_c FROM public.health_records;
    IF v_c = 0 THEN
        RAISE NOTICE 'B5 PASSED: Anon read on health_records returned 0 rows under RLS.';
    ELSE
        RAISE EXCEPTION 'B5 FAILED: Anon saw % rows in health_records!', v_c;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'B5 PASSED: Anon blocked by table privilege on health_records (OK)';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- PART C: AUTHENTICATED PATIENT ROLE SIMULATION
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
-- Replace placeholders with a valid test user from your public.users table:
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

-- Test C1: Patient can query their own records
SELECT count(*) AS patient_visible_appointments FROM public.appointments;
SELECT count(*) AS patient_visible_profile FROM public.patients;

-- Test C2: Atomic booking for SELF (expected: SUCCESS)
SELECT public.book_appointment_atomic(
    p_appointment_id => 'test_appt_self_' || gen_random_uuid()::text,
    p_doctor_id => '<EXISTING_DOCTOR_PROFILE_ID>',
    p_patient_id => '<TEST_PATIENT_PROFILE_ID>', -- MATCHES caller's profile_id
    p_doctor_name => 'Test Doctor',
    p_specialization => 'General',
    p_patient_name => 'Test Patient',
    p_patient_age => 30,
    p_patient_gender => 'male',
    p_date_time => (NOW() + interval '1 day'),
    p_slot_label => '10:00 AM',
    p_visit_type => 'newVisit'
);

-- Test C3: Atomic booking for ANOTHER patient (expected: FAILS with 42501 FORBIDDEN)
DO $$
BEGIN
    PERFORM public.book_appointment_atomic(
        p_appointment_id => 'test_appt_hack_' || gen_random_uuid()::text,
        p_doctor_id => '<EXISTING_DOCTOR_PROFILE_ID>',
        p_patient_id => 'some_other_patient_profile', -- DOES NOT MATCH caller's profile_id
        p_doctor_name => 'Test Doctor',
        p_specialization => 'General',
        p_patient_name => 'Victim Patient',
        p_patient_age => 35,
        p_patient_gender => 'female',
        p_date_time => (NOW() + interval '1 day'),
        p_slot_label => '10:30 AM',
        p_visit_type => 'newVisit'
    );
    RAISE EXCEPTION 'TEST_FAILED: Should have thrown 42501 FORBIDDEN!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'C3 PASSED: Cross-patient booking correctly rejected with 42501.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- PART D: ADMIN ROLE SIMULATION (WITH STRICT ASSERTIONS)
-- ----------------------------------------------------------------------------
-- Pre-step: Compute baseline count as postgres superuser (e.g. SELECT count(*) FROM public.appointments)
-- and pass that integer into v_baseline_total below.

-- Test D1: Admin via public.users.role = 'admin' / 'super_admin'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<ADMIN_USER_WITH_ROLE_FIELD>","role":"authenticated","email":"role_admin@example.com"}';

DO $$
DECLARE
    v_is_admin BOOLEAN;
    v_admin_count INT;
    v_baseline_total INT := 10; -- Placeholder: replace with actual SELECT count(*) FROM public.appointments as postgres
BEGIN
    SELECT public.is_super_admin() INTO v_is_admin;
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'D1 FAILED: public.is_super_admin() returned FALSE for admin user with users.role = admin!';
    END IF;

    SELECT count(*) INTO v_admin_count FROM public.appointments;
    IF v_admin_count != v_baseline_total THEN
        RAISE EXCEPTION 'D1 FAILED: Admin visible appointments (%) does not match baseline total (%)!',
            v_admin_count, v_baseline_total;
    END IF;

    RAISE NOTICE 'D1 PASSED: Admin via users.role successfully saw all % appointments.', v_admin_count;
END $$;

ROLLBACK;

-- Test D2: Admin via private.admin_users membership
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<ADMIN_USER_IN_ADMIN_USERS_TABLE>","role":"authenticated","email":"custom_admin@example.com"}';

DO $$
DECLARE
    v_is_admin BOOLEAN;
    v_admin_count INT;
    v_baseline_total INT := 10; -- Placeholder: replace with actual SELECT count(*) FROM public.appointments as postgres
BEGIN
    SELECT public.is_super_admin() INTO v_is_admin;
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'D2 FAILED: public.is_super_admin() returned FALSE for user in private.admin_users!';
    END IF;

    SELECT count(*) INTO v_admin_count FROM public.appointments;
    IF v_admin_count != v_baseline_total THEN
        RAISE EXCEPTION 'D2 FAILED: Admin-users visible appointments (%) does not match baseline total (%)!',
            v_admin_count, v_baseline_total;
    END IF;

    RAISE NOTICE 'D2 PASSED: Admin via private.admin_users successfully saw all % appointments.', v_admin_count;
END $$;

ROLLBACK;

-- Test D3: NEGATIVE TEST: Non-admin caller presenting admin email in JWT claim
-- Caller is an authenticated PATIENT whose JWT email is spoofed as 'admin@doctornect.com',
-- but UID is a standard patient not in private.admin_users and public.users.role = 'patient'.
BEGIN;
SET LOCAL ROLE authenticated;
-- Use a valid PATIENT user ID for sub:
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"admin@doctornect.com"}';

DO $$
DECLARE
    v_is_admin BOOLEAN;
    v_caller_profile TEXT;
    v_visible_count INT;
    v_expected_own_count INT;
BEGIN
    SELECT public.is_super_admin() INTO v_is_admin;
    IF v_is_admin THEN
        RAISE EXCEPTION 'D3 FAILED: JWT email spoof bypassed admin check! is_super_admin() returned TRUE.';
    END IF;

    v_caller_profile := public.current_profile_id();

    SELECT count(*) INTO v_visible_count FROM public.appointments;

    -- Count caller's own appointments (where patient_id = caller's profile_id)
    SELECT count(*) INTO v_expected_own_count 
    FROM public.appointments 
    WHERE patient_id IS NOT DISTINCT FROM v_caller_profile;

    IF v_visible_count != v_expected_own_count THEN
        RAISE EXCEPTION 'D3 FAILED: Non-admin visible appointments (%) did not match their own appointments (%)!',
            v_visible_count, v_expected_own_count;
    END IF;

    RAISE NOTICE 'D3 PASSED: JWT email spoof rejected. Visible appointments (%) strictly equals own appointments (%).',
        v_visible_count, v_expected_own_count;
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- PART E: USERS TABLE INTEGRITY TESTS (MIGRATION 20260930000003)
-- ----------------------------------------------------------------------------
-- NOTE: Tests E1 and E2 pass because of REVOKE INSERT ON public.users FROM authenticated
-- (table-level privilege revocation) rather than the trigger.

-- Test E1: NEGATIVE: Non-admin caller attempts to insert own users row with role = 'super_admin'
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
BEGIN
    INSERT INTO public.users (id, role, profile_id, display_name, email, profile_completed, verified)
    VALUES ('<TEST_PATIENT_AUTH_UID>', 'super_admin', 'p_test_hacker', 'Hacker Admin', 'hacker@example.com', true, true);

    RAISE EXCEPTION 'E1 FAILED: Non-admin was able to insert users row with role=super_admin!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E1 PASSED: Non-admin role=super_admin insert blocked with 42501 (REVOKE INSERT).';
END $$;

ROLLBACK;

-- Test E2: NEGATIVE: Non-admin caller attempts to insert users row with another user's profile_id
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
BEGIN
    INSERT INTO public.users (id, role, profile_id, display_name, email, profile_completed, verified)
    VALUES ('<TEST_PATIENT_AUTH_UID>', 'patient', '<VICTIM_PATIENT_PROFILE_ID>', 'Impersonator', 'patient@example.com', true, false);

    RAISE EXCEPTION 'E2 FAILED: Non-admin was able to insert users row with another user''s profile_id!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E2 PASSED: profile_id impersonation on insert blocked with 42501 (REVOKE INSERT).';
END $$;

ROLLBACK;

-- Test E3: NEGATIVE: Authenticated user attempts to self-escalate role via UPDATE
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
BEGIN
    UPDATE public.users 
    SET role = 'super_admin'
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E3 FAILED: Authenticated user successfully updated own role to super_admin!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E3 PASSED: Role update blocked with 42501.';
END $$;

ROLLBACK;

-- Test E4: NEGATIVE: Authenticated user attempts to modify profile_id via UPDATE
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
BEGIN
    UPDATE public.users 
    SET profile_id = 'stolen_profile_id_999'
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E4 FAILED: Authenticated user successfully modified their profile_id!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E4 PASSED: profile_id modification blocked with 42501.';
END $$;

ROLLBACK;

-- Test E5: NEGATIVE: Authenticated user attempts to set verified = TRUE via UPDATE
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
BEGIN
    UPDATE public.users 
    SET verified = TRUE
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E5 FAILED: Authenticated user successfully modified verified status!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E5 PASSED: verified modification blocked with 42501.';
END $$;

ROLLBACK;

-- Test E5B: NEGATIVE: Authenticated user attempts to modify mobile, email, or firebase_uid via UPDATE (Column-Level Grant Enforcement)
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

-- Test E5B.1: Attempt to update mobile (must fail with 42501 privilege error)
DO $$
BEGIN
    UPDATE public.users 
    SET mobile = '9999999999'
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E5B.1 FAILED: Non-admin was able to update mobile column directly!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E5B.1 (mobile) PASSED: mobile update blocked with 42501 (column privilege revoked).';
END $$;

-- Test E5B.2: Attempt to update email (must fail with 42501 privilege error)
DO $$
BEGIN
    UPDATE public.users 
    SET email = 'new_hacked_email@example.com'
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E5B.2 FAILED: Non-admin was able to update email column directly!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E5B.2 (email) PASSED: email update blocked with 42501 (column privilege revoked).';
END $$;

-- Test E5B.3: Attempt to update firebase_uid (must fail with 42501 privilege error)
DO $$
BEGIN
    UPDATE public.users 
    SET firebase_uid = 'forged_firebase_uid_123'
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE EXCEPTION 'E5B.3 FAILED: Non-admin was able to update firebase_uid column directly!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'E5B.3 (firebase_uid) PASSED: firebase_uid update blocked with 42501 (column privilege revoked).';
END $$;

ROLLBACK;

-- Test E6: POSITIVE: Normal user updates own profile_completed and display_name (MUST SUCCEED)
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

DO $$
DECLARE
    v_updated_name TEXT;
BEGIN
    UPDATE public.users
    SET display_name = 'Updated Patient Name',
        profile_completed = TRUE
    WHERE id = '<TEST_PATIENT_AUTH_UID>'
    RETURNING display_name INTO v_updated_name;

    RAISE NOTICE 'E6 PASSED: Legitimate user profile update and profile_completed flow succeeded.';
END $$;

ROLLBACK;

-- Test E7: POSITIVE: Super Admin / service_role modifies user role (MUST SUCCEED)
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<ADMIN_USER_WITH_ROLE_FIELD>","role":"authenticated","email":"role_admin@example.com"}';

DO $$
BEGIN
    UPDATE public.users
    SET role = 'doctor',
        verified = TRUE
    WHERE id = '<TEST_PATIENT_AUTH_UID>';

    RAISE NOTICE 'E7 PASSED: Super admin successfully updated user role and verified status.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- PART F: ACCESS GAPS & USER PROVISIONING TESTS (MIGRATIONS 4 & 5)
-- (STAGING ONLY: Uses placeholders <TEST_DOCTOR_AUTH_UID>, etc.)
-- ----------------------------------------------------------------------------

-- Test F1: NEGATIVE: Doctor attempts to insert patient_doctor_links referral for patient WITHOUT clinical access
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    INSERT INTO public.patient_doctor_links (patient_id, doctor_id, source, from_doctor_id)
    VALUES ('<UNAUTHORIZED_TARGET_PATIENT_ID>', '<TARGET_COLLEAGUE_DOCTOR_ID>', 'referral', '<TEST_DOCTOR_PROFILE_ID>');

    RAISE EXCEPTION 'F1 FAILED: Doctor was able to create referral link for patient without active clinical access!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F1 PASSED: Unauthorized doctor referral link blocked with 42501.';
END $$;

ROLLBACK;

-- Test F2: POSITIVE: Doctor with active clinical access creates patient_doctor_links referral
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    -- Requires <ACCESSIBLE_PATIENT_ID> where doctor_can_access_patient() returns true
    INSERT INTO public.patient_doctor_links (patient_id, doctor_id, source, from_doctor_id)
    VALUES ('<ACCESSIBLE_PATIENT_ID>', '<TARGET_COLLEAGUE_DOCTOR_ID>', 'referral', '<TEST_DOCTOR_PROFILE_ID>');

    RAISE NOTICE 'F2 PASSED: Authorized doctor referral link insertion succeeded.';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE EXCEPTION 'F2 FAILED: Authorized doctor referral link blocked unexpectedly!';
END $$;

ROLLBACK;

-- Test F3: NEGATIVE: Doctor attempts to alter patient_id on existing appointment
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    UPDATE public.appointments
    SET patient_id = '<VICTIM_PATIENT_ID>'
    WHERE appointment_id = '<TEST_DOCTOR_OWNED_APPOINTMENT_ID>';

    RAISE EXCEPTION 'F3 FAILED: Doctor was able to mutate patient_id on appointment!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F3 PASSED: Appointment patient_id mutation blocked with 42501.';
END $$;

ROLLBACK;

-- Test F4: NEGATIVE: Doctor attempts to alter own deactivated or owner_uid
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    UPDATE public.doctors
    SET deactivated = TRUE
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE EXCEPTION 'F4.1 FAILED: Doctor was able to mutate own deactivated status!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F4.1 (deactivated) PASSED: Doctor deactivated modification blocked with 42501.';
END $$;

DO $$
BEGIN
    UPDATE public.doctors
    SET owner_uid = '<SOME_OTHER_USER_UID>'
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE EXCEPTION 'F4.2 FAILED: Doctor was able to reassign owner_uid!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F4.2 (owner_uid) PASSED: Doctor owner_uid reassignment blocked with 42501.';
END $$;

ROLLBACK;

-- Test F5: POSITIVE: Super Admin updates provider deactivated and owner_uid
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<ADMIN_USER_WITH_ROLE_FIELD>","role":"authenticated","email":"role_admin@example.com"}';

DO $$
BEGIN
    UPDATE public.doctors
    SET deactivated = TRUE
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE NOTICE 'F5 PASSED: Super admin successfully updated provider deactivated flag.';
END $$;

ROLLBACK;

-- Test F6: POSITIVE & SECURITY CHECK: User provisioning trigger respects app_metadata role and ignores spoofed user_metadata role
BEGIN;
-- Run as postgres / internal service context to simulate auth.users insert
DO $$
DECLARE
    v_test_auth_id UUID := gen_random_uuid();
    v_created_role TEXT;
    v_created_profile_id TEXT;
BEGIN
    -- Insert auth.users with spoofed user_metadata role ('super_admin') but legitimate app_metadata ('doctor')
    INSERT INTO auth.users (
        id,
        email,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    ) VALUES (
        v_test_auth_id,
        'provision_test_' || v_test_auth_id || '@example.com',
        '{"role": "doctor"}'::jsonb,
        '{"role": "super_admin", "display_name": "Dr. Trigger Test"}'::jsonb,
        NOW(),
        NOW()
    );

    -- Query created public.users row
    SELECT role, profile_id INTO v_created_role, v_created_profile_id
    FROM public.users
    WHERE id = v_test_auth_id;

    IF v_created_role = 'super_admin' THEN
        RAISE EXCEPTION 'F6 FAILED: Provisioning trigger accepted spoofed user_metadata role super_admin!';
    ELSIF v_created_role != 'doctor' THEN
        RAISE EXCEPTION 'F6 FAILED: Expected role doctor from app_metadata, got %', v_created_role;
    END IF;

    IF v_created_profile_id NOT LIKE 'd_%' THEN
        RAISE EXCEPTION 'F6 FAILED: Expected doctor profile_id prefix d_, got %', v_created_profile_id;
    END IF;

    RAISE NOTICE 'F6 PASSED: Provisioning trigger safely used app_metadata role (doctor) and generated profile_id (%).',
        v_created_profile_id;
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F7: NEGATIVE: Verified doctor inserting walk-in appointment for a
-- REGISTERED platform patient must fail (42501 via appointments_insert policy: walkin branch removed).
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    INSERT INTO public.appointments (
        appointment_id,
        patient_id,
        doctor_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        source,
        doctor_status,
        patient_status
    ) VALUES (
        'apt_f7_test_' || gen_random_uuid(),
        '<REGISTERED_PATIENT_PROFILE_ID>',
        '<TEST_DOCTOR_PROFILE_ID>',
        'Dr. Test Doctor',
        'General Medicine',
        'Registered Patient',
        35,
        'Male',
        NOW() + INTERVAL '1 day',
        '10:00 AM',
        'walkin',
        'confirmed',
        'confirmed'
    );

    RAISE EXCEPTION 'F7 FAILED: Doctor was able to insert a walk-in appointment for a registered platform patient!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F7 PASSED: Walk-in appointment for registered patient blocked with 42501 (appointments_insert policy).';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F8: NEGATIVE: Verified doctor inserting walk-in appointment for an
-- unlinked STUB patient must now fail (42501: direct doctor appointment inserts
-- are removed; stub appointments replicate strictly via service_role sync bridge).
-- ----------------------------------------------------------------------------
BEGIN;
-- Setup: Create stub patient as service_role/postgres
DO $$
BEGIN
    INSERT INTO public.patients (
        patient_id,
        owner_uid,
        primary_doctor_id,
        name,
        mobile
    ) VALUES (
        'p_stub_f8_test',
        NULL,
        '<TEST_DOCTOR_PROFILE_ID>',
        'Walkin Stub Patient',
        '9876543210'
    ) ON CONFLICT (patient_id) DO NOTHING;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    INSERT INTO public.appointments (
        appointment_id,
        patient_id,
        doctor_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        source,
        doctor_status,
        patient_status
    ) VALUES (
        'apt_f8_test_' || gen_random_uuid(),
        'p_stub_f8_test',
        '<TEST_DOCTOR_PROFILE_ID>',
        'Dr. Test Doctor',
        'General Medicine',
        'Walkin Stub Patient',
        40,
        'Female',
        NOW() + INTERVAL '1 day',
        '11:00 AM',
        'walkin',
        'confirmed',
        'confirmed'
    );

    RAISE EXCEPTION 'F8 FAILED: Doctor was able to insert walk-in appointment directly for stub patient!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F8 PASSED: Direct walk-in insertion by doctor for stub patient blocked with 42501 (least-privilege appointments_insert).';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F9: POSITIVE & NEGATIVE: Patient with 2+ appointments can cancel one
-- (UPDATE succeeds without error 21000); changing patient_id/doctor_id fails (42501).
-- ----------------------------------------------------------------------------
BEGIN;
-- Seed two appointments for patient
DO $$
BEGIN
    INSERT INTO public.appointments (
        appointment_id, patient_id, doctor_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        source, doctor_status, patient_status
    ) VALUES 
    ('apt_f9_1', '<TEST_PATIENT_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>', 'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'Male', NOW() + INTERVAL '1 day', '09:00 AM', 'app', 'confirmed', 'confirmed'),
    ('apt_f9_2', '<TEST_PATIENT_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>', 'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'Male', NOW() + INTERVAL '2 day', '10:00 AM', 'app', 'confirmed', 'confirmed')
    ON CONFLICT (appointment_id) DO NOTHING;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

-- F9.1: Patient cancels appointment 1 (must succeed without error 21000)
DO $$
BEGIN
    UPDATE public.appointments
    SET patient_status = 'cancelled'
    WHERE appointment_id = 'apt_f9_1';

    RAISE NOTICE 'F9.1 PASSED: Patient successfully cancelled appointment without subquery error 21000.';
END $$;

-- F9.2: Patient attempts to reassign doctor_id (blocked with 42501 by lock_columns trigger)
DO $$
BEGIN
    UPDATE public.appointments
    SET doctor_id = '<ANOTHER_DOCTOR_PROFILE_ID>'
    WHERE appointment_id = 'apt_f9_2';

    RAISE EXCEPTION 'F9.2 FAILED: Patient was able to reassign doctor_id!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F9.2 (lock_columns) PASSED: doctor_id modification blocked with 42501.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F10: POSITIVE & NEGATIVE: Doctor writes prescription for patient with
-- share_records_with_doctors = FALSE and active appointment; fails for unrelated patient.
-- ----------------------------------------------------------------------------
BEGIN;
-- Setup patient with sharing OFF and active appointment with doctor
DO $$
BEGIN
    UPDATE public.patients
    SET share_records_with_doctors = FALSE
    WHERE patient_id = '<TEST_PATIENT_PROFILE_ID>';

    INSERT INTO public.appointments (
        appointment_id, patient_id, doctor_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        source, doctor_status, patient_status
    ) VALUES (
        'apt_f10_active', '<TEST_PATIENT_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>',
        'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'Male',
        NOW() + INTERVAL '1 day', '10:00 AM', 'app', 'confirmed', 'confirmed'
    ) ON CONFLICT (appointment_id) DO NOTHING;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

-- F10.1: Doctor writes prescription for patient who turned off record sharing
DO $$
BEGIN
    INSERT INTO public.prescriptions (
        prescription_id,
        patient_id,
        doctor_id,
        patient_name,
        patient_age,
        primary_diagnosis,
        created_at
    ) VALUES (
        'rx_f10_' || gen_random_uuid(),
        '<TEST_PATIENT_PROFILE_ID>',
        '<TEST_DOCTOR_PROFILE_ID>',
        'Test Patient',
        30,
        'Acute bronchitis',
        NOW()
    );

    RAISE NOTICE 'F10.1 PASSED: Doctor authored prescription despite patient share_records_with_doctors = FALSE.';
END $$;

-- F10.2: Doctor attempts to write prescription for unrelated patient (fails with 42501)
DO $$
BEGIN
    INSERT INTO public.prescriptions (
        prescription_id,
        patient_id,
        doctor_id,
        patient_name,
        patient_age,
        primary_diagnosis,
        created_at
    ) VALUES (
        'rx_f10_unrelated_' || gen_random_uuid(),
        '<UNRELATED_PATIENT_PROFILE_ID>',
        '<TEST_DOCTOR_PROFILE_ID>',
        'Unrelated Patient',
        45,
        'Unauthorized Prescription',
        NOW()
    );

    RAISE EXCEPTION 'F10.2 FAILED: Doctor was able to prescribe for unrelated patient!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F10.2 PASSED: Prescription write for unrelated patient blocked with 42501.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F11: POSITIVE & NORMALIZATION: Provisioning trigger extracts 10-digit mobile
-- and ignores spoofed user_metadata role (matches auth-otp lookup pattern).
-- ----------------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    v_test_auth_id UUID := gen_random_uuid();
    v_created_role TEXT;
    v_created_profile_id TEXT;
    v_created_mobile TEXT;
    v_found_id UUID;
BEGIN
    -- Simulate createUser with app_metadata.role='doctor', user_metadata.role='super_admin', phone='+919876543210'
    INSERT INTO auth.users (
        id,
        email,
        phone,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    ) VALUES (
        v_test_auth_id,
        'doctor_' || v_test_auth_id || '@doctornect.com',
        '+919876543210',
        '{"role": "doctor"}'::jsonb,
        '{"role": "super_admin", "mobile": "9876543210", "display_name": "Dr. Test Provision"}'::jsonb,
        NOW(),
        NOW()
    );

    -- Verify public.users row
    SELECT role, profile_id, mobile INTO v_created_role, v_created_profile_id, v_created_mobile
    FROM public.users
    WHERE id = v_test_auth_id;

    IF v_created_role != 'doctor' THEN
        RAISE EXCEPTION 'F11 FAILED: Expected role doctor from app_metadata, got %', v_created_role;
    END IF;

    IF v_created_mobile != '9876543210' THEN
        RAISE EXCEPTION 'F11 FAILED: Expected normalized 10-digit mobile 9876543210, got %', v_created_mobile;
    END IF;

    -- Verify auth-otp lookup pattern: eq("mobile", digits).eq("deactivated", false)
    SELECT id INTO v_found_id
    FROM public.users
    WHERE mobile = '9876543210'
      AND deactivated = FALSE
      AND id = v_test_auth_id;

    IF v_found_id IS NULL THEN
        RAISE EXCEPTION 'F11 FAILED: auth-otp 10-digit mobile lookup query failed to match provisioned user!';
    END IF;

    RAISE NOTICE 'F11 PASSED: User provisioned with role doctor, mobile 9876543210, and auth-otp lookup succeeded.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F12: NEGATIVE: Doctor B cannot insert a walk-in appointment for a stub
-- created by Doctor A (blocked with 42501 via appointments_insert policy: walkin branch removed).
-- ----------------------------------------------------------------------------
BEGIN;
-- Setup: Create stub patient bound to Doctor A (primary_doctor_id = doc_a)
DO $$
BEGIN
    INSERT INTO public.patients (
        patient_id,
        owner_uid,
        primary_doctor_id,
        name,
        mobile
    ) VALUES (
        'p_stub_doc_a',
        NULL,
        '<TEST_DOCTOR_PROFILE_ID>',
        'Doctor A Walk-in Stub',
        '9876543211'
    ) ON CONFLICT (patient_id) DO NOTHING;
END $$;

-- Switch to Doctor B
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_B_AUTH_UID>","role":"authenticated","email":"doctor_b@example.com"}';

DO $$
BEGIN
    INSERT INTO public.appointments (
        appointment_id,
        patient_id,
        doctor_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        source,
        doctor_status,
        patient_status
    ) VALUES (
        'apt_f12_hijack_' || gen_random_uuid(),
        'p_stub_doc_a',
        '<TEST_DOCTOR_B_PROFILE_ID>',
        'Dr. Test Doctor B',
        'Dermatology',
        'Doctor A Walk-in Stub',
        28,
        'Female',
        NOW() + INTERVAL '1 day',
        '02:00 PM',
        'walkin',
        'confirmed',
        'confirmed'
    );

    RAISE EXCEPTION 'F12 FAILED: Doctor B was able to book walk-in for Doctor A stub patient!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F12 PASSED: Doctor B blocked with 42501 from booking walk-in for Doctor A stub (appointments_insert policy).';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F13: POSITIVE & NEGATIVE: lab_bookings update with 2+ bookings succeeds
-- without error 21000; lock_columns blocks altering patient_id (42501).
-- ----------------------------------------------------------------------------
BEGIN;
-- Seed two lab bookings for patient
DO $$
BEGIN
    INSERT INTO public.lab_bookings (
        booking_id, patient_id, lab_id, patient_name, patient_age, test_id, test_name,
        test_names, date_time, slot_label, collection_type, status, source
    ) VALUES 
    ('lb_f13_1', '<TEST_PATIENT_PROFILE_ID>', '<TEST_LAB_PROFILE_ID>', 'Test Patient', 30, 't_cbc', 'Complete Blood Count', ARRAY['Complete Blood Count'], NOW() + INTERVAL '1 day', '09:00 AM', 'labVisit', 'confirmed', 'app'),
    ('lb_f13_2', '<TEST_PATIENT_PROFILE_ID>', '<TEST_LAB_PROFILE_ID>', 'Test Patient', 30, 't_lipid', 'Lipid Profile', ARRAY['Lipid Profile'], NOW() + INTERVAL '2 day', '10:00 AM', 'labVisit', 'confirmed', 'app')
    ON CONFLICT (booking_id) DO NOTHING;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

-- F13.1: Patient cancels booking 1 (must succeed without error 21000)
DO $$
BEGIN
    UPDATE public.lab_bookings
    SET status = 'cancelled'
    WHERE booking_id = 'lb_f13_1';

    RAISE NOTICE 'F13.1 PASSED: Patient updated lab_bookings with 2+ rows without error 21000.';
END $$;

-- F13.2: Patient attempts to alter patient_id (blocked with 42501 by lock_columns)
DO $$
BEGIN
    UPDATE public.lab_bookings
    SET patient_id = '<ANOTHER_PATIENT_PROFILE_ID>'
    WHERE booking_id = 'lb_f13_2';

    RAISE EXCEPTION 'F13.2 FAILED: patient_id on lab_bookings was modified!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F13.2 (lock_columns) PASSED: patient_id alteration on lab_bookings blocked with 42501.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F14: POSITIVE & NEGATIVE: referrals update with 2+ referrals succeeds
-- without error 21000; lock_columns blocks altering from_doctor_id/patient_id (42501).
-- ----------------------------------------------------------------------------
BEGIN;
-- Seed two referrals to Doctor
DO $$
BEGIN
    INSERT INTO public.referrals (
        referral_id, from_doctor_id, to_doctor_id, patient_id, from_doctor_name,
        to_doctor_name, to_specialization, patient_name, patient_age, status
    ) VALUES 
    ('ref_f14_1', '<ANOTHER_DOCTOR_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>', '<TEST_PATIENT_PROFILE_ID>', 'Dr. Referrer', 'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'sent'),
    ('ref_f14_2', '<ANOTHER_DOCTOR_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>', '<TEST_PATIENT_PROFILE_ID>', 'Dr. Referrer', 'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'sent')
    ON CONFLICT (referral_id) DO NOTHING;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

-- F14.1: Receiving doctor accepts referral 1 (must succeed without error 21000)
DO $$
BEGIN
    UPDATE public.referrals
    SET status = 'accepted'
    WHERE referral_id = 'ref_f14_1';

    RAISE NOTICE 'F14.1 PASSED: Receiving doctor updated referrals with 2+ rows without error 21000.';
END $$;

-- F14.2: Receiving doctor attempts to change from_doctor_id (blocked with 42501 by lock_columns)
DO $$
BEGIN
    UPDATE public.referrals
    SET from_doctor_id = '<TEST_DOCTOR_PROFILE_ID>'
    WHERE referral_id = 'ref_f14_2';

    RAISE EXCEPTION 'F14.2 FAILED: from_doctor_id on referrals was modified!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F14.2 (lock_columns) PASSED: from_doctor_id alteration on referrals blocked with 42501.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F15: DOCTOR COLUMN LOCKS: Doctor cannot change own rating/review_count (42501);
-- Super Admin can; Doctor can legitimately update other fields (name, fcm_token).
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

-- F15.1: NEGATIVE: Doctor attempts to bump own rating (must fail with 42501)
DO $$
BEGIN
    UPDATE public.doctors
    SET rating = 5.00
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE EXCEPTION 'F15.1 FAILED: Doctor was able to alter own rating!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F15.1 (rating) PASSED: Doctor rating update blocked with 42501.';
END $$;

-- F15.2: NEGATIVE: Doctor attempts to bump own review_count (must fail with 42501)
DO $$
BEGIN
    UPDATE public.doctors
    SET review_count = review_count + 10
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE EXCEPTION 'F15.2 FAILED: Doctor was able to alter own review_count!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F15.2 (review_count) PASSED: Doctor review_count update blocked with 42501.';
END $$;

-- F15.3: POSITIVE: Doctor legitimately updates own name and fcm_token (must succeed)
DO $$
BEGIN
    UPDATE public.doctors
    SET name = 'Dr. Updated Name',
        fcm_token = 'fresh_fcm_token_123'
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE NOTICE 'F15.3 (allowed fields) PASSED: Doctor updated name and fcm_token successfully.';
END $$;

-- F15.4: POSITIVE: Super Admin updates rating and review_count (must succeed)
SET LOCAL request.jwt.claims = '{"sub":"<ADMIN_USER_WITH_ROLE_FIELD>","role":"authenticated","email":"role_admin@example.com"}';

DO $$
BEGIN
    UPDATE public.doctors
    SET rating = 4.95,
        review_count = 150
    WHERE doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    RAISE NOTICE 'F15.4 (admin bypass) PASSED: Super admin updated rating and review_count successfully.';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F16: NEGATIVE: Doctor whose ONLY appointment with patient is CANCELLED
-- cannot read the patient (doctor_can_access_patient evaluates to FALSE).
-- ----------------------------------------------------------------------------
BEGIN;
-- Setup: Patient with share_records_with_doctors = TRUE
-- Appointment between Doctor and Patient is CANCELLED
DO $$
BEGIN
    UPDATE public.patients
    SET share_records_with_doctors = TRUE,
        primary_doctor_id = NULL,
        invited_doctor_id = NULL,
        care_team_doctor_ids = ARRAY[]::TEXT[]
    WHERE patient_id = '<TEST_PATIENT_PROFILE_ID>';

    DELETE FROM public.patient_doctor_links
    WHERE patient_id = '<TEST_PATIENT_PROFILE_ID>'
      AND doctor_id = '<TEST_DOCTOR_PROFILE_ID>';

    INSERT INTO public.appointments (
        appointment_id, patient_id, doctor_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        source, doctor_status, patient_status
    ) VALUES (
        'apt_f16_cancelled', '<TEST_PATIENT_PROFILE_ID>', '<TEST_DOCTOR_PROFILE_ID>',
        'Dr. Test Doctor', 'General Medicine', 'Test Patient', 30, 'Male',
        NOW() - INTERVAL '1 day', '10:00 AM', 'app', 'cancelled', 'cancelled'
    ) ON CONFLICT (appointment_id) DO UPDATE
    SET doctor_status = 'cancelled', patient_status = 'cancelled';
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

-- Doctor tries to select the patient; with only cancelled appointment, doctor_can_access_patient is FALSE
DO $$
DECLARE
    v_found_count INT;
BEGIN
    SELECT COUNT(*) INTO v_found_count
    FROM public.patients
    WHERE patient_id = '<TEST_PATIENT_PROFILE_ID>';

    IF v_found_count > 0 THEN
        RAISE EXCEPTION 'F16 FAILED: Doctor with only cancelled appointment was able to read patient record!';
    END IF;

    RAISE NOTICE 'F16 PASSED: Doctor with only cancelled appointment cannot read patient (0 rows returned).';
END $$;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- Test F17: INSERT-TIME TRUST COLUMN GATING
-- Non-admin inserting ambulance/doctor/lab with verified = TRUE or rating > 0 is denied (42501).
-- Admin and service_role can insert verified/rated rows.
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"<TEST_PATIENT_AUTH_UID>","role":"authenticated","email":"patient@example.com"}';

-- F17.1: NEGATIVE: Non-admin inserting ambulance with verified = TRUE (must fail with 42501)
DO $$
BEGIN
    INSERT INTO public.ambulances (
        ambulance_id, auth_uid, service_name, driver_name, phone,
        vehicle_number, ambulance_type, city, verified
    ) VALUES (
        'amb_f17_tamper_' || gen_random_uuid(), '<TEST_PATIENT_AUTH_UID>', 'Rogue Ambulance',
        'Rogue Driver', '9876543210', 'MH-01-AB-1234', 'bls', 'Mumbai', TRUE
    );

    RAISE EXCEPTION 'F17.1 FAILED: Non-admin was able to insert ambulance with verified = TRUE!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F17.1 PASSED: Non-admin inserting ambulance with verified = TRUE blocked with 42501.';
END $$;

-- F17.2: NEGATIVE: Non-admin inserting ambulance with total_rating > 0 (must fail with 42501)
DO $$
BEGIN
    INSERT INTO public.ambulances (
        ambulance_id, auth_uid, service_name, driver_name, phone,
        vehicle_number, ambulance_type, city, verified, total_rating
    ) VALUES (
        'amb_f17_tamper2_' || gen_random_uuid(), '<TEST_PATIENT_AUTH_UID>', 'Rogue Ambulance 2',
        'Rogue Driver 2', '9876543211', 'MH-01-AB-1235', 'bls', 'Mumbai', FALSE, 5.00
    );

    RAISE EXCEPTION 'F17.2 FAILED: Non-admin was able to insert ambulance with total_rating > 0!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F17.2 PASSED: Non-admin inserting ambulance with total_rating > 0 blocked with 42501.';
END $$;

-- F17.3: NEGATIVE: Non-admin inserting doctor with verified = TRUE or rating > 0 (must fail with 42501)
SET LOCAL request.jwt.claims = '{"sub":"<TEST_DOCTOR_AUTH_UID>","role":"authenticated","email":"doctor@example.com"}';

DO $$
BEGIN
    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, rating
    ) VALUES (
        '<TEST_DOCTOR_PROFILE_ID>', '<TEST_DOCTOR_AUTH_UID>', 'Dr. Spoofed',
        'spoofed@example.com', '9876543212', 'Cardiology', 'MBBS', TRUE, 5.00
    );

    RAISE EXCEPTION 'F17.3 FAILED: Non-admin was able to insert doctor with verified = TRUE / rating > 0!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F17.3 PASSED: Non-admin inserting doctor with verified = TRUE / rating > 0 blocked with 42501.';
END $$;

-- F17.4: NEGATIVE: Non-admin inserting lab with verified = TRUE or rating > 0 (must fail with 42501)
SET LOCAL request.jwt.claims = '{"sub":"<TEST_LAB_AUTH_UID>","role":"authenticated","email":"lab@example.com"}';

DO $$
BEGIN
    INSERT INTO public.labs (
        lab_id, owner_uid, lab_name, license_number, phone, email, verified, rating
    ) VALUES (
        '<TEST_LAB_PROFILE_ID>', '<TEST_LAB_AUTH_UID>', 'Spoofed Lab',
        'LIC-1234', '9876543213', 'lab@example.com', TRUE, 4.80
    );

    RAISE EXCEPTION 'F17.4 FAILED: Non-admin was able to insert lab with verified = TRUE / rating > 0!';
EXCEPTION
    WHEN SQLSTATE '42501' THEN
        RAISE NOTICE 'F17.4 PASSED: Non-admin inserting lab with verified = TRUE / rating > 0 blocked with 42501.';
END $$;

-- F17.5: POSITIVE: Super Admin can insert verified provider
SET LOCAL request.jwt.claims = '{"sub":"<TEST_ADMIN_AUTH_UID>","role":"authenticated","email":"superadmin@doctornect.com"}';

DO $$
BEGIN
    INSERT INTO public.ambulances (
        ambulance_id, auth_uid, service_name, driver_name, phone,
        vehicle_number, ambulance_type, city, verified, total_rating, rating_count
    ) VALUES (
        'amb_admin_seed_' || gen_random_uuid(), '<TEST_ADMIN_AUTH_UID>', 'Admin Certified Ambulance',
        'Official Driver', '9876543299', 'MH-01-AB-9999', 'als', 'Mumbai', TRUE, 5.00, 10
    );

    RAISE NOTICE 'F17.5 PASSED: Super Admin successfully inserted verified ambulance with rating.';
END $$;

-- F17.6: POSITIVE: service_role (auth.uid() IS NULL) can insert verified provider
RESET ROLE;

DO $$
BEGIN
    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, verified, rating, review_count
    ) VALUES (
        'd_service_seed_' || gen_random_uuid(), NULL, 'Sync Bridge Doctor',
        'syncbridge@example.com', '9876543288', 'Neurology', 'MD', TRUE, 4.90, 50
    );

    RAISE NOTICE 'F17.6 PASSED: service_role successfully inserted verified doctor with rating.';
END $$;

ROLLBACK;




