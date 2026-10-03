-- ============================================================================
-- DoctorNect Platform -- Local Verification Script
-- File: supabase/scratch/verification_script.sql
-- Run after: npx supabase db reset
-- Execution command:
--   psql -v ON_ERROR_STOP=0 -f supabase/scratch/verification_script.sql 2>&1 | tee verify.out
--   grep -E "FAIL|ERROR" verify.out
-- ============================================================================

-- ============================================================================
-- PRE-FLIGHT SCHEMA AUDIT BLOCK
-- Queries information_schema, private.admin_users, and pg_constraint.
-- RAISEs EXCEPTION if any table, column, or CHECK constraint used later is missing.
-- ============================================================================
DO $$
DECLARE
    v_missing TEXT := '';
BEGIN
    -- 1. Verify required tables
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'patients') THEN
        v_missing := v_missing || ' table:public.patients';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'doctors') THEN
        v_missing := v_missing || ' table:public.doctors';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
        v_missing := v_missing || ' table:public.appointments';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reviews') THEN
        v_missing := v_missing || ' table:public.reviews';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'health_records') THEN
        v_missing := v_missing || ' table:public.health_records';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'labs') THEN
        v_missing := v_missing || ' table:public.labs';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'medical_stores') THEN
        v_missing := v_missing || ' table:public.medical_stores';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'promoted_ads') THEN
        v_missing := v_missing || ' table:public.promoted_ads';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ambulances') THEN
        v_missing := v_missing || ' table:public.ambulances';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        v_missing := v_missing || ' table:public.users';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'prescriptions') THEN
        v_missing := v_missing || ' table:public.prescriptions';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'patient_doctor_links') THEN
        v_missing := v_missing || ' table:public.patient_doctor_links';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'lab_bookings') THEN
        v_missing := v_missing || ' table:public.lab_bookings';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'lab_orders') THEN
        v_missing := v_missing || ' table:public.lab_orders';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'in_app_notifications') THEN
        v_missing := v_missing || ' table:public.in_app_notifications';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'private' AND table_name = 'admin_users') THEN
        v_missing := v_missing || ' table:private.admin_users';
    END IF;

    -- 2. Verify columns on public.patients
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'sync_origin') THEN
        v_missing := v_missing || ' column:patients.sync_origin';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'pincode') THEN
        v_missing := v_missing || ' column:patients.pincode';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'city') THEN
        v_missing := v_missing || ' column:patients.city';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'state') THEN
        v_missing := v_missing || ' column:patients.state';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'photo_key') THEN
        v_missing := v_missing || ' column:patients.photo_key';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patients' AND column_name = 'photo_storage') THEN
        v_missing := v_missing || ' column:patients.photo_storage';
    END IF;

    -- 3. Verify columns on public.appointments
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'appointments' AND column_name = 'sync_origin') THEN
        v_missing := v_missing || ' column:appointments.sync_origin';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'appointments' AND column_name = 'date_time') THEN
        v_missing := v_missing || ' column:appointments.date_time';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'appointments' AND column_name = 'source') THEN
        v_missing := v_missing || ' column:appointments.source';
    END IF;

    -- 4. Verify columns on public.reviews
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'sync_origin') THEN
        v_missing := v_missing || ' column:reviews.sync_origin';
    END IF;

    -- 5. Verify columns on public.health_records
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'health_records' AND column_name = 'storage_key') THEN
        v_missing := v_missing || ' column:health_records.storage_key';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'health_records' AND column_name = 'storage_provider') THEN
        v_missing := v_missing || ' column:health_records.storage_provider';
    END IF;

    -- 6. Verify CHECK constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'appointments_source_check') THEN
        v_missing := v_missing || ' constraint:appointments_source_check';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'health_records_type_check') THEN
        v_missing := v_missing || ' constraint:health_records_type_check';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'health_records_source_check') THEN
        v_missing := v_missing || ' constraint:health_records_source_check';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'patients_gender_check') THEN
        v_missing := v_missing || ' constraint:patients_gender_check';
    END IF;

    IF v_missing <> '' THEN
        RAISE EXCEPTION '[FAIL] Pre-flight schema validation failed. Missing components:%', v_missing;
    END IF;

    RAISE NOTICE '[PASS] Pre-flight schema audit: All required tables, columns, and constraints exist.';
END $$;


-- ============================================================================
-- DISPLAY FINAL RLS POLICIES FOR CORE TABLES
-- ============================================================================
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('patients', 'appointments', 'reviews', 'health_records')
ORDER BY tablename, cmd, policyname;


-- ============================================================================
-- SECTION A: service_role can UPDATE locked columns on doctors
-- ============================================================================
DO $$
DECLARE
    v_doctor_id TEXT := 'd_svc_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid       UUID := gen_random_uuid();
BEGIN
    -- Setup auth.users + public.users for doctor
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'svc@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'doctor', v_doctor_id, 'Svc Doctor', 'svc@test.com', '9000000001',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification,
        experience_years, rating, review_count, deactivated, profile_completed, verified
    ) VALUES (
        v_doctor_id, v_uid, 'Svc Doctor', 'svc@test.com', '9000000001',
        'General Physician', 'MBBS', 1, 0, 0, FALSE, FALSE, FALSE
    );

    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
    SET LOCAL ROLE service_role;

    UPDATE public.doctors
    SET verified = TRUE, rating = 4.5, review_count = 10
    WHERE doctor_id = v_doctor_id;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF NOT EXISTS (
        SELECT 1 FROM public.doctors
        WHERE doctor_id = v_doctor_id AND verified = TRUE AND rating = 4.5
    ) THEN
        RAISE EXCEPTION '[FAIL] A1 - service_role UPDATE not reflected';
    END IF;
    RAISE NOTICE '[PASS] A1 - service_role can UPDATE verified/rating/review_count on doctors';

    DELETE FROM public.doctors WHERE doctor_id = v_doctor_id;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ============================================================================
-- SECTION B: authenticated cannot UPDATE locked columns on doctors
-- Includes positive control: UPDATE allowed column (name) asserts row count = 1
-- ============================================================================
DO $$
DECLARE
    v_doctor_id TEXT := 'd_auth_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid       UUID := gen_random_uuid();
    v_blocked   BOOLEAN;
    v_rowcount  INT;
BEGIN
    -- Setup auth.users + public.users so current_profile_id() returns v_doctor_id
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'doctor_b@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'doctor', v_doctor_id, 'Auth Doctor', 'doctor_b@test.com', '9000000002',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification,
        experience_years, rating, review_count, deactivated, profile_completed, verified
    ) VALUES (
        v_doctor_id, v_uid, 'Auth Doctor', 'auth@test.com', '9000000002',
        'General Physician', 'MBBS', 1, 0, 0, FALSE, FALSE, FALSE
    );

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Positive control: authenticated CAN update allowed column (name)
    UPDATE public.doctors SET name = 'Dr. Allowed Name Update' WHERE doctor_id = v_doctor_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 1 THEN
        RAISE EXCEPTION '[FAIL] B_ctrl - positive control name UPDATE on doctors failed (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] B_ctrl - positive control: authenticated can UPDATE allowed column (name) on doctors (rowcount=1)';

    -- B1: locked column verified
    v_blocked := FALSE;
    BEGIN
        UPDATE public.doctors SET verified = TRUE WHERE doctor_id = v_doctor_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] B1 - authenticated updated verified on doctors'; END IF;
    RAISE NOTICE '[PASS] B1 - authenticated cannot UPDATE verified on doctors';

    -- B2: locked column rating
    v_blocked := FALSE;
    BEGIN
        UPDATE public.doctors SET rating = 5.0 WHERE doctor_id = v_doctor_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] B2 - authenticated updated rating on doctors'; END IF;
    RAISE NOTICE '[PASS] B2 - authenticated cannot UPDATE rating on doctors';

    -- B3: locked column review_count
    v_blocked := FALSE;
    BEGIN
        UPDATE public.doctors SET review_count = 100 WHERE doctor_id = v_doctor_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] B3 - authenticated updated review_count on doctors'; END IF;
    RAISE NOTICE '[PASS] B3 - authenticated cannot UPDATE review_count on doctors';

    -- B4: locked column owner_uid
    v_blocked := FALSE;
    BEGIN
        UPDATE public.doctors SET owner_uid = gen_random_uuid() WHERE doctor_id = v_doctor_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] B4 - authenticated updated owner_uid on doctors'; END IF;
    RAISE NOTICE '[PASS] B4 - authenticated cannot UPDATE owner_uid on doctors';

    -- B5: locked column deactivated
    v_blocked := FALSE;
    BEGIN
        UPDATE public.doctors SET deactivated = TRUE WHERE doctor_id = v_doctor_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] B5 - authenticated updated deactivated on doctors'; END IF;
    RAISE NOTICE '[PASS] B5 - authenticated cannot UPDATE deactivated on doctors';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);
    DELETE FROM public.doctors WHERE doctor_id = v_doctor_id;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ============================================================================
-- SECTION C: service_role can UPDATE locked columns on ambulances
-- ============================================================================
DO $$
DECLARE
    v_amb_id TEXT := 'a_svc_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid    UUID := gen_random_uuid();
BEGIN
    -- Setup auth.users + public.users for ambulance
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'amb_c@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'ambulance', v_amb_id, 'Svc Amb User', 'amb_c@test.com', '9000000003',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.ambulances (
        ambulance_id, auth_uid, service_name, driver_name, phone,
        vehicle_number, ambulance_type, city, is_available,
        total_rating, rating_count, verified
    ) VALUES (
        v_amb_id, v_uid, 'Svc Amb', 'Driver Svc', '9000000003',
        'MH-12-AB-1234', 'bls', 'Pune', TRUE,
        0, 0, FALSE
    );

    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
    SET LOCAL ROLE service_role;

    UPDATE public.ambulances
    SET verified = TRUE, total_rating = 50.0, rating_count = 10
    WHERE ambulance_id = v_amb_id;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF NOT EXISTS (
        SELECT 1 FROM public.ambulances
        WHERE ambulance_id = v_amb_id AND verified = TRUE AND rating_count = 10
    ) THEN
        RAISE EXCEPTION '[FAIL] C1 - service_role UPDATE not reflected on ambulances';
    END IF;
    RAISE NOTICE '[PASS] C1 - service_role can UPDATE verified/ratings on ambulances';

    DELETE FROM public.ambulances WHERE ambulance_id = v_amb_id;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ============================================================================
-- SECTION D: authenticated cannot UPDATE locked columns on ambulances
-- Includes positive control: UPDATE allowed column (service_name) asserts row count = 1
-- ============================================================================
DO $$
DECLARE
    v_amb_id   TEXT := 'a_auth_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid      UUID := gen_random_uuid();
    v_blocked  BOOLEAN;
    v_rowcount INT;
BEGIN
    -- Setup auth.users + public.users so current_profile_id() returns v_amb_id
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'amb_d@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'ambulance', v_amb_id, 'Auth Amb User', 'amb_d@test.com', '9000000004',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.ambulances (
        ambulance_id, auth_uid, service_name, driver_name, phone,
        vehicle_number, ambulance_type, city, is_available,
        total_rating, rating_count, verified
    ) VALUES (
        v_amb_id, v_uid, 'Auth Amb', 'Driver Auth', '9000000004',
        'MH-12-CD-5678', 'bls', 'Pune', TRUE,
        0, 0, FALSE
    );

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Positive control: authenticated CAN update allowed column (service_name)
    UPDATE public.ambulances SET service_name = 'Allowed Service Name Update' WHERE ambulance_id = v_amb_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 1 THEN
        RAISE EXCEPTION '[FAIL] D_ctrl - positive control service_name UPDATE on ambulances failed (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] D_ctrl - positive control: authenticated can UPDATE allowed column (service_name) on ambulances (rowcount=1)';

    -- D1: verified
    v_blocked := FALSE;
    BEGIN
        UPDATE public.ambulances SET verified = TRUE WHERE ambulance_id = v_amb_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] D1 - authenticated updated verified on ambulances'; END IF;
    RAISE NOTICE '[PASS] D1 - authenticated cannot UPDATE verified on ambulances';

    -- D2: total_rating
    v_blocked := FALSE;
    BEGIN
        UPDATE public.ambulances SET total_rating = 99.0 WHERE ambulance_id = v_amb_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] D2 - authenticated updated total_rating on ambulances'; END IF;
    RAISE NOTICE '[PASS] D2 - authenticated cannot UPDATE total_rating on ambulances';

    -- D3: rating_count
    v_blocked := FALSE;
    BEGIN
        UPDATE public.ambulances SET rating_count = 50 WHERE ambulance_id = v_amb_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] D3 - authenticated updated rating_count on ambulances'; END IF;
    RAISE NOTICE '[PASS] D3 - authenticated cannot UPDATE rating_count on ambulances';

    -- D4: auth_uid
    v_blocked := FALSE;
    BEGIN
        UPDATE public.ambulances SET auth_uid = gen_random_uuid() WHERE ambulance_id = v_amb_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] D4 - authenticated updated auth_uid on ambulances'; END IF;
    RAISE NOTICE '[PASS] D4 - authenticated cannot UPDATE auth_uid on ambulances';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);
    DELETE FROM public.ambulances WHERE ambulance_id = v_amb_id;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ============================================================================
-- SECTION E: Column lock enforcement on patients and labs
-- Includes service_role success for labs.rating and positive controls (rowcount = 1)
-- ============================================================================
DO $$
DECLARE
    v_pat_id   TEXT := 'p_lock_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_lab_id   TEXT := 'l_lock_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_pat_uid  UUID := gen_random_uuid();
    v_lab_uid  UUID := gen_random_uuid();
    v_blocked  BOOLEAN;
    v_rowcount INT;
BEGIN
    -- Setup auth.users + public.users for patient
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_pat_uid, 'authenticated', 'authenticated', 'pat_e@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_pat_uid, 'patient', v_pat_id, 'Lock Patient', 'pat_e@test.com', '9000000005',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile, verified)
    VALUES (v_pat_id, v_pat_uid, 'Lock Patient', '9000000005', FALSE);

    -- Setup auth.users + public.users for lab
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_lab_uid, 'authenticated', 'authenticated', 'lab_e@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_lab_uid, 'lab', v_lab_id, 'Lock Lab', 'lab_e@test.com', '9000000006',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.labs (
        lab_id, owner_uid, lab_name, license_number, phone, email, rating, verified, deactivated
    ) VALUES (
        v_lab_id, v_lab_uid, 'Lock Lab', 'LIC-100', '9000000006', 'lab@test.com', 0.0, FALSE, FALSE
    );

    -- E_svc: service_role can successfully UPDATE labs.rating and labs.verified
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);
    SET LOCAL ROLE service_role;

    UPDATE public.labs SET rating = 4.8, verified = TRUE WHERE lab_id = v_lab_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 1 THEN
        RAISE EXCEPTION '[FAIL] E_svc - service_role failed to UPDATE labs.rating (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] E_svc - service_role can UPDATE rating and verified on labs (rowcount=1)';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- --- PATIENT SESSION ---
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_pat_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Positive control: patient can UPDATE allowed column (name)
    UPDATE public.patients SET name = 'Allowed Patient Name Update' WHERE patient_id = v_pat_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 1 THEN
        RAISE EXCEPTION '[FAIL] E_pat_ctrl - positive control name UPDATE on patients failed (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] E_pat_ctrl - positive control: authenticated can UPDATE allowed column (name) on patients (rowcount=1)';

    -- E1: patients.verified locked
    v_blocked := FALSE;
    BEGIN
        UPDATE public.patients SET verified = TRUE WHERE patient_id = v_pat_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] E1 - authenticated updated verified on patients'; END IF;
    RAISE NOTICE '[PASS] E1 - authenticated cannot UPDATE verified on patients';

    -- E2: patients.owner_uid locked
    v_blocked := FALSE;
    BEGIN
        UPDATE public.patients SET owner_uid = gen_random_uuid() WHERE patient_id = v_pat_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] E2 - authenticated updated owner_uid on patients'; END IF;
    RAISE NOTICE '[PASS] E2 - authenticated cannot UPDATE owner_uid on patients';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- --- LAB SESSION ---
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_lab_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Positive control: lab can UPDATE allowed column (lab_name)
    UPDATE public.labs SET lab_name = 'Allowed Lab Name Update' WHERE lab_id = v_lab_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 1 THEN
        RAISE EXCEPTION '[FAIL] E_lab_ctrl - positive control lab_name UPDATE on labs failed (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] E_lab_ctrl - positive control: authenticated can UPDATE allowed column (lab_name) on labs (rowcount=1)';

    -- E3: labs.verified locked
    v_blocked := FALSE;
    BEGIN
        UPDATE public.labs SET verified = FALSE WHERE lab_id = v_lab_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] E3 - authenticated updated verified on labs'; END IF;
    RAISE NOTICE '[PASS] E3 - authenticated cannot UPDATE verified on labs';

    -- E4: labs.rating locked
    v_blocked := FALSE;
    BEGIN
        UPDATE public.labs SET rating = 5.0 WHERE lab_id = v_lab_id;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;
    IF NOT v_blocked THEN RAISE EXCEPTION '[FAIL] E4 - authenticated updated rating on labs'; END IF;
    RAISE NOTICE '[PASS] E4 - authenticated cannot UPDATE rating on labs';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    DELETE FROM public.patients WHERE patient_id = v_pat_id;
    DELETE FROM public.labs WHERE lab_id = v_lab_id;
    DELETE FROM public.users WHERE id IN (v_pat_uid, v_lab_uid);
    DELETE FROM auth.users WHERE id IN (v_pat_uid, v_lab_uid);
END $$;


-- ============================================================================
-- SECTION F1: patients upsert & fresh insert as authenticated owner
-- Repository source:
--   Payload keys: updateProfile (lib/core/supabase/supabase_patient_repository.dart:261-266)
--   Fields map: persistProfile (lib/features/patient/profile/data/patient_profile_mock.dart:387-413)
-- Exact column list (22 columns):
--   patient_id, name, age, gender, mobile, email, blood_group, height, weight,
--   photo_url, photo_key, photo_storage, address, city, state, pincode, country,
--   conditions, allergies, share_records_with_doctors, profile_completed,
--   sync_origin, updated_at
-- (Note: owner_uid has DEFAULT auth.uid() via migration 20261001000002)
-- ============================================================================
DO $$
DECLARE
    v_uid             UUID := gen_random_uuid();
    v_patient_id      TEXT := 'p_upsert_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid_fresh       UUID := gen_random_uuid();
    v_patient_fresh   TEXT := 'p_fresh_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked         BOOLEAN;
BEGIN
    -- Setup auth.users + public.users for authenticated testing
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'patient_f1@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_patient_id, 'F1 Patient', 'patient_f1@test.com', '9000000010',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    -- Initial patient row
    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id, v_uid, 'Original Name', '9000000010');

    -- Switch to authenticated owner
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- (a) Conflict path: upsert on existing patient row with exact repo keys.
    -- DO UPDATE SET mirrors ALL 21 non-conflict keys from the real PostgREST payload.
    BEGIN
        INSERT INTO public.patients (
            patient_id, name, age, gender, mobile, email, blood_group,
            height, weight, photo_url, photo_key, photo_storage,
            address, city, state, pincode, country, conditions, allergies,
            share_records_with_doctors, profile_completed, sync_origin, updated_at
        ) VALUES (
            v_patient_id, 'Updated Patient Name', 35, 'Male', '9000000010', 'patient_f1@test.com', 'O+',
            '175', '70', 'https://example.com/photo.jpg', 'patients/photo.jpg', 's3',
            'Flat 101, Test Road', 'Mumbai', 'Maharashtra', '400001', 'India',
            ARRAY['None']::TEXT[], ARRAY['None']::TEXT[], TRUE, TRUE, 'patient_supabase', NOW()
        )
        ON CONFLICT (patient_id) DO UPDATE SET
            name                       = EXCLUDED.name,
            age                        = EXCLUDED.age,
            gender                     = EXCLUDED.gender,
            mobile                     = EXCLUDED.mobile,
            email                      = EXCLUDED.email,
            blood_group                = EXCLUDED.blood_group,
            height                     = EXCLUDED.height,
            weight                     = EXCLUDED.weight,
            photo_url                  = EXCLUDED.photo_url,
            photo_key                  = EXCLUDED.photo_key,
            photo_storage              = EXCLUDED.photo_storage,
            address                    = EXCLUDED.address,
            city                       = EXCLUDED.city,
            state                      = EXCLUDED.state,
            pincode                    = EXCLUDED.pincode,
            country                    = EXCLUDED.country,
            conditions                 = EXCLUDED.conditions,
            allergies                  = EXCLUDED.allergies,
            share_records_with_doctors = EXCLUDED.share_records_with_doctors,
            profile_completed          = EXCLUDED.profile_completed,
            sync_origin                = EXCLUDED.sync_origin,
            updated_at                 = EXCLUDED.updated_at;

        RAISE NOTICE '[PASS] F1a - patients upsert UPDATE conflict path succeeds as authenticated owner with mirrored payload';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F1a - patients upsert conflict path failed: % %', SQLSTATE, SQLERRM;
    END;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Setup second user for fresh insert
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid_fresh, 'authenticated', 'authenticated', 'patient_fresh@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid_fresh, 'patient', v_patient_fresh, 'Fresh Patient', 'patient_fresh@test.com', '9000000011',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid_fresh::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- (b1) Fresh INSERT using exactly the repository payload (NO owner_uid):
    -- With DEFAULT auth.uid() applied via migration 20261001000002, owner_uid defaults to auth.uid(),
    -- satisfying the patients_insert policy (owner_uid = auth.uid() AND patient_id = current_profile_id()).
    BEGIN
        INSERT INTO public.patients (
            patient_id, name, age, gender, mobile, email, blood_group,
            height, weight, photo_url, photo_key, photo_storage,
            address, city, state, pincode, country, conditions, allergies,
            share_records_with_doctors, profile_completed, sync_origin, updated_at
        ) VALUES (
            v_patient_fresh, 'Fresh Patient Repo Payload', 28, 'Female', '9000000011', 'fresh@test.com', 'A+',
            '165', '55', 'https://example.com/p.jpg', 'patients/p.jpg', 's3',
            'Suite 202', 'Pune', 'Maharashtra', '411001', 'India',
            ARRAY['None']::TEXT[], ARRAY['None']::TEXT[],
            TRUE, TRUE, 'patient_supabase', NOW()
        );

        RAISE NOTICE '[PASS] F1b_repo - fresh INSERT using exact repository payload (no owner_uid) succeeds via DEFAULT auth.uid()';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F1b_repo - fresh INSERT using exact repository payload failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (b2) Negative test: second user attempting to insert with someone else's owner_uid must FAIL with 42501
    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.patients (
            patient_id, owner_uid, name, mobile
        ) VALUES (
            'p_spoof_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_uid, -- Someone else's UID (v_uid, while session is v_uid_fresh)
            'Spoofed Owner Patient',
            '9000000099'
        );
    EXCEPTION WHEN sqlstate '42501' THEN
        v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F1b_spoof - insert with someone else''s owner_uid should be blocked by patients_insert RLS';
    END IF;
    RAISE NOTICE '[PASS] F1b_spoof - insert specifying someone else''s owner_uid is blocked (42501) by patients_insert policy';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Cleanup
    DELETE FROM public.patients WHERE patient_id IN (v_patient_id, v_patient_fresh);
    DELETE FROM public.users WHERE id IN (v_uid, v_uid_fresh);
    DELETE FROM auth.users WHERE id IN (v_uid, v_uid_fresh);
END $$;


-- ============================================================================
-- SECTION F2: reviews upsert & fresh insert as authenticated owner
-- Repository source: submitReview (lib/core/supabase/supabase_patient_repository.dart:213-223)
-- Exact column list (9 columns):
--   review_id, patient_id, doctor_id, appointment_id, patient_name, rating,
--   comment, sync_origin, updated_at
-- Conflict target: (patient_id, doctor_id)
-- Negative test uses a second REAL patient (auth.users + public.users + patients)
-- ============================================================================
DO $$
DECLARE
    v_uid          UUID := gen_random_uuid();
    v_patient_id   TEXT := 'p_rev_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_doctor_id    TEXT := 'd_rev_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_appt_id      TEXT := 'ap_rev_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_review_id    TEXT := v_patient_id || '_' || v_doctor_id;
    v_uid2         UUID := gen_random_uuid();
    v_patient_id2  TEXT := 'p_rev2_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid_doc      UUID := gen_random_uuid();
    v_blocked      BOOLEAN;
BEGIN
    -- Superuser setup for patient 1 (auth, users, doctor, appointment)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'reviewer@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_patient_id, 'Reviewer Patient', 'reviewer@test.com', '9000000020',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id, v_uid, 'Reviewer Patient', '9000000020');

    -- Setup target doctor
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid_doc, 'authenticated', 'authenticated', 'doc_target@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid_doc, 'doctor', v_doctor_id, 'Dr. Review Target', 'doc_target@test.com', '9000000021',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years
    ) VALUES (
        v_doctor_id, v_uid_doc, 'Dr. Review Target', 'doc_target@test.com',
        '9000000021', 'Cardiologist', 'MD', 5
    );

    -- Setup appointment linking patient 1 to doctor
    INSERT INTO public.appointments (
        appointment_id, patient_id, doctor_id,
        doctor_name, specialization, patient_name, patient_age, patient_gender,
        date_time, slot_label, visit_type, patient_status, doctor_status, source
    ) VALUES (
        v_appt_id, v_patient_id, v_doctor_id,
        'Dr. Review Target', 'Cardiologist', 'Reviewer Patient', 30, 'Male',
        NOW(), '10:00 AM', 'newVisit', 'confirmed', 'completed', 'app'
    );

    -- Setup second REAL patient (v_uid2 + v_patient_id2)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid2, 'authenticated', 'authenticated', 'patient2@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid2, 'patient', v_patient_id2, 'Second Patient', 'patient2@test.com', '9000000022',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id2, v_uid2, 'Second Patient', '9000000022');

    -- Switch to authenticated patient 1 owner
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- (a) Fresh INSERT with exact repository payload keys
    BEGIN
        INSERT INTO public.reviews (
            review_id, patient_id, doctor_id, appointment_id,
            patient_name, rating, comment, sync_origin, updated_at
        ) VALUES (
            v_review_id, v_patient_id, v_doctor_id, v_appt_id,
            'Reviewer Patient', 5, 'Exceptional care and consultation.', 'patient_supabase', NOW()
        );
        RAISE NOTICE '[PASS] F2a - reviews fresh INSERT succeeds as authenticated patient owner';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F2a - reviews fresh INSERT failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (b) Conflict path upsert with DO UPDATE SET mirroring ALL 7 non-conflict keys from payload
    BEGIN
        INSERT INTO public.reviews (
            review_id, patient_id, doctor_id, appointment_id,
            patient_name, rating, comment, sync_origin, updated_at
        ) VALUES (
            v_review_id, v_patient_id, v_doctor_id, v_appt_id,
            'Reviewer Patient', 4, 'Updated comment: very satisfied.', 'patient_supabase', NOW()
        )
        ON CONFLICT (patient_id, doctor_id) DO UPDATE SET
            review_id      = EXCLUDED.review_id,
            appointment_id = EXCLUDED.appointment_id,
            patient_name   = EXCLUDED.patient_name,
            rating         = EXCLUDED.rating,
            comment        = EXCLUDED.comment,
            sync_origin    = EXCLUDED.sync_origin,
            updated_at     = EXCLUDED.updated_at;

        RAISE NOTICE '[PASS] F2b - reviews upsert UPDATE conflict path succeeds as authenticated patient owner with mirrored payload';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F2b - reviews upsert conflict path failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (c) Negative test: second REAL patient session cannot insert review for patient 1
    RESET ROLE;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid2::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.reviews (
            review_id, patient_id, doctor_id, appointment_id,
            patient_name, rating, comment, sync_origin
        ) VALUES (
            'r_unauth_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_patient_id, v_doctor_id, v_appt_id,
            'Attacker', 1, 'Fake Review', 'patient_supabase'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F2c - reviews INSERT should be blocked for second real patient';
    END IF;
    RAISE NOTICE '[PASS] F2c - reviews INSERT blocked (42501) when second real patient attempts review for unrelated patient';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Cleanup
    DELETE FROM public.reviews WHERE review_id = v_review_id;
    DELETE FROM public.appointments WHERE appointment_id = v_appt_id;
    DELETE FROM public.doctors WHERE doctor_id = v_doctor_id;
    DELETE FROM public.patients WHERE patient_id IN (v_patient_id, v_patient_id2);
    DELETE FROM public.users WHERE id IN (v_uid, v_uid2, v_uid_doc);
    DELETE FROM auth.users WHERE id IN (v_uid, v_uid2, v_uid_doc);
END $$;


-- ============================================================================
-- SECTION F3: health_records upsert & fresh insert as authenticated owner
-- Repository source: addHealthRecord (lib/core/supabase/supabase_patient_repository.dart:327-346)
-- Exact column list (18 columns):
--   record_id, patient_id, title, type, date, source, file_name, doctor_name,
--   lab_name, is_image, notes, shared_with_doctors, file_storage, storage_url,
--   storage_key, storage_provider, created_at, updated_at
-- Conflict target: (record_id)
-- Negative test uses a second REAL patient (auth.users + public.users + patients)
-- ============================================================================
DO $$
DECLARE
    v_uid          UUID := gen_random_uuid();
    v_patient_id   TEXT := 'p_hr_'   || replace(gen_random_uuid()::TEXT, '-', '');
    v_record_id    TEXT := 'rec_hr_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid2         UUID := gen_random_uuid();
    v_patient_id2  TEXT := 'p_hr2_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked      BOOLEAN;
BEGIN
    -- Superuser setup for patient 1
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'hr_patient@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_patient_id, 'HR Patient', 'hr_patient@test.com', '9000000030',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id, v_uid, 'HR Patient', '9000000030');

    -- Setup second REAL patient (v_uid2 + v_patient_id2)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid2, 'authenticated', 'authenticated', 'patient2_hr@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid2, 'patient', v_patient_id2, 'Second HR Patient', 'patient2_hr@test.com', '9000000031',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id2, v_uid2, 'Second HR Patient', '9000000031');

    -- Switch to authenticated patient owner
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- (a) Fresh INSERT with exact repository payload keys
    BEGIN
        INSERT INTO public.health_records (
            record_id, patient_id, title, type, date, source, file_name,
            doctor_name, lab_name, is_image, notes, shared_with_doctors,
            file_storage, storage_url, storage_key, storage_provider,
            created_at, updated_at
        ) VALUES (
            v_record_id, v_patient_id, 'Complete Blood Count', 'labReport', NOW(),
            'selfUploaded', 'cbc_report.pdf', 'Dr. Pathologist', 'City Diagnostic',
            FALSE, 'Routine checkup', TRUE, 'cloudUploaded', 'https://storage/cbc.pdf',
            'health_records/cbc.pdf', 's3', NOW(), NOW()
        );
        RAISE NOTICE '[PASS] F3a - health_records fresh INSERT succeeds as authenticated patient owner';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F3a - health_records fresh INSERT failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (b) Conflict path upsert with DO UPDATE SET mirroring ALL 17 non-conflict keys from payload
    BEGIN
        INSERT INTO public.health_records (
            record_id, patient_id, title, type, date, source, file_name,
            doctor_name, lab_name, is_image, notes, shared_with_doctors,
            file_storage, storage_url, storage_key, storage_provider,
            created_at, updated_at
        ) VALUES (
            v_record_id, v_patient_id, 'Updated CBC Report', 'labReport', NOW(),
            'selfUploaded', 'cbc_report_v2.pdf', 'Dr. Pathologist', 'City Diagnostic',
            FALSE, 'Reviewed with doctor', TRUE, 'cloudUploaded', 'https://storage/cbc_v2.pdf',
            'health_records/cbc_v2.pdf', 's3', NOW(), NOW()
        )
        ON CONFLICT (record_id) DO UPDATE SET
            patient_id          = EXCLUDED.patient_id,
            title               = EXCLUDED.title,
            type                = EXCLUDED.type,
            date                = EXCLUDED.date,
            source              = EXCLUDED.source,
            file_name           = EXCLUDED.file_name,
            doctor_name         = EXCLUDED.doctor_name,
            lab_name            = EXCLUDED.lab_name,
            is_image            = EXCLUDED.is_image,
            notes               = EXCLUDED.notes,
            shared_with_doctors = EXCLUDED.shared_with_doctors,
            file_storage        = EXCLUDED.file_storage,
            storage_url         = EXCLUDED.storage_url,
            storage_key         = EXCLUDED.storage_key,
            storage_provider    = EXCLUDED.storage_provider,
            created_at          = EXCLUDED.created_at,
            updated_at          = EXCLUDED.updated_at;

        RAISE NOTICE '[PASS] F3b - health_records upsert UPDATE conflict path succeeds as authenticated patient owner with mirrored payload';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F3b - health_records upsert conflict path failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (c) Negative test: second REAL patient cannot insert record for patient 1
    RESET ROLE;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid2::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.health_records (
            record_id, patient_id, title, type, date, source, file_name,
            shared_with_doctors, file_storage
        ) VALUES (
            'rec_unauth_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_patient_id, 'Unauthorized Report', 'prescription', NOW(),
            'selfUploaded', 'fake.pdf', TRUE, 'none'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F3c - health_records INSERT should be blocked for second real patient';
    END IF;
    RAISE NOTICE '[PASS] F3c - health_records INSERT blocked (42501) when second real patient attempts insert for unrelated patient';

    -- (d) CHECK constraint validation: invalid type or source
    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.health_records (
            record_id, patient_id, title, type, date, source, file_name,
            shared_with_doctors, file_storage
        ) VALUES (
            'rec_chk_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_patient_id2, 'Bad Type Report', 'invalid_type', NOW(),
            'selfUploaded', 'test.pdf', TRUE, 'none'
        );
    EXCEPTION WHEN check_violation THEN v_blocked := TRUE; END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F3d - health_records CHECK constraint did not reject invalid type';
    END IF;
    RAISE NOTICE '[PASS] F3d - health_records CHECK constraint rejects invalid type';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Cleanup
    DELETE FROM public.health_records WHERE record_id = v_record_id;
    DELETE FROM public.patients WHERE patient_id IN (v_patient_id, v_patient_id2);
    DELETE FROM public.users WHERE id IN (v_uid, v_uid2);
    DELETE FROM auth.users WHERE id IN (v_uid, v_uid2);
END $$;


-- ============================================================================
-- SECTION F4: appointments upsert & fresh insert as authenticated owner
-- Repository source: bookAppointment fallback (lib/core/supabase/supabase_patient_repository.dart:96-120)
-- Exact column list (19 columns):
--   appointment_id, doctor_id, patient_id, doctor_name, specialization,
--   patient_name, patient_age, patient_gender, date_time, slot_label, visit_type,
--   patient_status, doctor_status, token_number, clinic_name, clinic_address,
--   sync_origin, source, updated_at
-- Conflict target: (appointment_id)
-- Negative test uses a second REAL patient (auth.users + public.users + patients)
-- Also verifies doctor unpermitted appointment insert fails and doctor_can_access_patient() stays false
-- ============================================================================
DO $$
DECLARE
    v_uid              UUID := gen_random_uuid();
    v_patient_id       TEXT := 'p_apt_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_doctor_id        TEXT := 'd_apt_'  || replace(gen_random_uuid()::TEXT, '-', '');
    v_appt_id          TEXT := 'ap_apt_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid2             UUID := gen_random_uuid();
    v_patient_id2      TEXT := 'p_apt2_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_uid_doc          UUID := gen_random_uuid();
    v_uid_doc_booked   UUID := gen_random_uuid();
    v_doc_unrelated    TEXT := 'd_unrel_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked          BOOLEAN;
BEGIN
    -- Superuser setup for patient 1
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'apt_patient@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_patient_id, 'Apt Patient', 'apt_patient@test.com', '9000000040',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile, share_records_with_doctors)
    VALUES (v_patient_id, v_uid, 'Apt Patient', '9000000040', TRUE);

    -- Setup booked doctor
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid_doc_booked, 'authenticated', 'authenticated', 'apt_doc@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid_doc_booked, 'doctor', v_doctor_id, 'Dr. Appointment Doctor', 'apt_doc@test.com', '9000000041',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified
    ) VALUES (
        v_doctor_id, v_uid_doc_booked, 'Dr. Appointment Doctor', 'apt_doc@test.com',
        '9000000041', 'Orthopedic', 'MS', 8, TRUE
    );

    -- Setup second REAL patient (v_uid2 + v_patient_id2)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid2, 'authenticated', 'authenticated', 'patient2_apt@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid2, 'patient', v_patient_id2, 'Second Apt Patient', 'patient2_apt@test.com', '9000000042',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_patient_id2, v_uid2, 'Second Apt Patient', '9000000042');

    -- Setup an unrelated VERIFIED doctor (v_uid_doc + v_doc_unrelated)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid_doc, 'authenticated', 'authenticated', 'unrelated_doc@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid_doc, 'doctor', v_doc_unrelated, 'Dr. Unrelated', 'unrelated_doc@test.com', '9000000043',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified
    ) VALUES (
        v_doc_unrelated, v_uid_doc, 'Dr. Unrelated', 'unrelated_doc@test.com',
        '9000000043', 'Dermatology', 'MD', 6, TRUE
    );

    -- Switch to authenticated patient owner
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- (a) Fresh INSERT with exact repository payload keys (source='app')
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name,
            specialization, patient_name, patient_age, patient_gender,
            date_time, slot_label, visit_type, patient_status,
            doctor_status, token_number, clinic_name, clinic_address,
            sync_origin, source, updated_at
        ) VALUES (
            v_appt_id, v_doctor_id, v_patient_id, 'Dr. Appointment Doctor',
            'Orthopedic', 'Apt Patient', 32, 'Male',
            NOW(), '11:00 AM', 'newVisit', 'confirmed',
            'pendingRequest', 1, 'City Ortho Clinic', 'Main Street 42',
            'patient_supabase', 'app', NOW()
        );

        RAISE NOTICE '[PASS] F4a - appointments fresh INSERT succeeds as authenticated patient owner';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F4a - appointments fresh INSERT failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (b) Conflict path upsert with DO UPDATE SET mirroring ALL 18 non-conflict keys from payload
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name,
            specialization, patient_name, patient_age, patient_gender,
            date_time, slot_label, visit_type, patient_status,
            doctor_status, token_number, clinic_name, clinic_address,
            sync_origin, source, updated_at
        ) VALUES (
            v_appt_id, v_doctor_id, v_patient_id, 'Dr. Appointment Doctor',
            'Orthopedic', 'Apt Patient', 32, 'Male',
            NOW(), '11:00 AM', 'newVisit', 'confirmed',
            'confirmed', 1, 'City Ortho Clinic', 'Main Street 42',
            'patient_supabase', 'app', NOW()
        )
        ON CONFLICT (appointment_id) DO UPDATE SET
            doctor_id      = EXCLUDED.doctor_id,
            patient_id     = EXCLUDED.patient_id,
            doctor_name    = EXCLUDED.doctor_name,
            specialization = EXCLUDED.specialization,
            patient_name   = EXCLUDED.patient_name,
            patient_age    = EXCLUDED.patient_age,
            patient_gender = EXCLUDED.patient_gender,
            date_time      = EXCLUDED.date_time,
            slot_label     = EXCLUDED.slot_label,
            visit_type     = EXCLUDED.visit_type,
            patient_status = EXCLUDED.patient_status,
            doctor_status  = EXCLUDED.doctor_status,
            token_number   = EXCLUDED.token_number,
            clinic_name    = EXCLUDED.clinic_name,
            clinic_address = EXCLUDED.clinic_address,
            sync_origin    = EXCLUDED.sync_origin,
            source         = EXCLUDED.source,
            updated_at     = EXCLUDED.updated_at;

        RAISE NOTICE '[PASS] F4b - appointments upsert UPDATE conflict path succeeds as authenticated patient owner with mirrored payload';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '[FAIL] F4b - appointments upsert conflict path failed: % %', SQLSTATE, SQLERRM;
    END;

    -- (c) Negative test: second REAL patient cannot book appointment for patient 1
    RESET ROLE;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid2::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name,
            specialization, patient_name, patient_age, patient_gender,
            date_time, slot_label, visit_type, patient_status,
            doctor_status, source
        ) VALUES (
            'ap_unauth_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_doctor_id, v_patient_id, 'Dr. Appointment Doctor',
            'Orthopedic', 'Attacker', 25, 'Male',
            NOW(), '12:00 PM', 'newVisit', 'confirmed',
            'pendingRequest', 'app'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := TRUE; END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F4c - appointments INSERT should be blocked for second real patient';
    END IF;
    RAISE NOTICE '[PASS] F4c - appointments INSERT blocked (42501) when second real patient attempts insert for target patient';

    -- (d) Walkin restriction: direct client insert with source='walkin' must be blocked for client
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name,
            specialization, patient_name, patient_age, patient_gender,
            date_time, slot_label, visit_type, patient_status,
            doctor_status, source
        ) VALUES (
            'ap_walkin_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_doctor_id, v_patient_id, 'Dr. Appointment Doctor',
            'Orthopedic', 'Apt Patient', 32, 'Male',
            NOW(), '01:00 PM', 'newVisit', 'confirmed',
            'pendingRequest', 'walkin'
        );
    EXCEPTION
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F4d - appointments INSERT with source=''walkin'' should be blocked for authenticated client';
    END IF;
    RAISE NOTICE '[PASS] F4d - appointments INSERT with source=''walkin'' blocked (42501) for authenticated client';

    -- (e) Negative test: verified doctor session directly INSERTing appointment with source='app' for unrelated patient must fail,
    -- and doctor_can_access_patient() for that patient must remain false
    RESET ROLE;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid_doc::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_blocked := FALSE;
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name,
            specialization, patient_name, patient_age, patient_gender,
            date_time, slot_label, visit_type, patient_status,
            doctor_status, source
        ) VALUES (
            'ap_doc_attack_' || replace(gen_random_uuid()::TEXT, '-', ''),
            v_doc_unrelated, v_patient_id, 'Dr. Unrelated',
            'Dermatology', 'Apt Patient', 32, 'Male',
            NOW(), '02:00 PM', 'newVisit', 'confirmed',
            'pendingRequest', 'app'
        );
    EXCEPTION
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] F4e - verified doctor directly inserting appointment with source=''app'' should be blocked';
    END IF;

    -- Assert doctor_can_access_patient() for that patient remains false
    IF public.doctor_can_access_patient(v_patient_id) THEN
        RAISE EXCEPTION '[FAIL] F4e - doctor_can_access_patient is TRUE for unrelated patient';
    END IF;

    RAISE NOTICE '[PASS] F4e - verified doctor direct INSERT for unrelated patient blocked (42501) and doctor_can_access_patient remains false';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Cleanup
    DELETE FROM public.appointments WHERE appointment_id = v_appt_id;
    DELETE FROM public.doctors WHERE doctor_id IN (v_doctor_id, v_doc_unrelated);
    DELETE FROM public.patients WHERE patient_id IN (v_patient_id, v_patient_id2);
    DELETE FROM public.users WHERE id IN (v_uid, v_uid2, v_uid_doc, v_uid_doc_booked);
    DELETE FROM auth.users WHERE id IN (v_uid, v_uid2, v_uid_doc, v_uid_doc_booked);
END $$;


-- ============================================================================
-- SECTION G: RPC access control (find_auth_user, consume_otp_attempt, check_and_increment_rate_limit)
-- ============================================================================
DO $$
BEGIN
    -- G1: find_auth_user
    IF has_function_privilege('anon', 'public.find_auth_user(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G1 - anon has EXECUTE on find_auth_user';
    ELSE
        RAISE NOTICE '[PASS] G1 - anon does NOT have EXECUTE on find_auth_user';
    END IF;

    IF has_function_privilege('authenticated', 'public.find_auth_user(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G1 - authenticated has EXECUTE on find_auth_user';
    ELSE
        RAISE NOTICE '[PASS] G1 - authenticated does NOT have EXECUTE on find_auth_user';
    END IF;

    IF has_function_privilege('service_role', 'public.find_auth_user(text)', 'execute') THEN
        RAISE NOTICE '[PASS] G1 - service_role has EXECUTE on find_auth_user';
    ELSE
        RAISE EXCEPTION '[FAIL] G1 - service_role missing EXECUTE on find_auth_user';
    END IF;

    -- G2: consume_otp_attempt
    IF has_function_privilege('anon', 'public.consume_otp_attempt(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G2 - anon has EXECUTE on consume_otp_attempt';
    ELSE
        RAISE NOTICE '[PASS] G2 - anon does NOT have EXECUTE on consume_otp_attempt';
    END IF;

    IF has_function_privilege('authenticated', 'public.consume_otp_attempt(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G2 - authenticated has EXECUTE on consume_otp_attempt';
    ELSE
        RAISE NOTICE '[PASS] G2 - authenticated does NOT have EXECUTE on consume_otp_attempt';
    END IF;

    IF has_function_privilege('service_role', 'public.consume_otp_attempt(text)', 'execute') THEN
        RAISE NOTICE '[PASS] G2 - service_role has EXECUTE on consume_otp_attempt';
    ELSE
        RAISE EXCEPTION '[FAIL] G2 - service_role missing EXECUTE on consume_otp_attempt';
    END IF;

    -- G3: check_and_increment_rate_limit
    IF has_function_privilege('anon', 'public.check_and_increment_rate_limit(text, int, int, text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G3 - anon has EXECUTE on check_and_increment_rate_limit';
    ELSE
        RAISE NOTICE '[PASS] G3 - anon does NOT have EXECUTE on check_and_increment_rate_limit';
    END IF;

    IF has_function_privilege('authenticated', 'public.check_and_increment_rate_limit(text, int, int, text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] G3 - authenticated has EXECUTE on check_and_increment_rate_limit';
    ELSE
        RAISE NOTICE '[PASS] G3 - authenticated does NOT have EXECUTE on check_and_increment_rate_limit';
    END IF;

    IF has_function_privilege('service_role', 'public.check_and_increment_rate_limit(text, int, int, text)', 'execute') THEN
        RAISE NOTICE '[PASS] G3 - service_role has EXECUTE on check_and_increment_rate_limit';
    ELSE
        RAISE EXCEPTION '[FAIL] G3 - service_role missing EXECUTE on check_and_increment_rate_limit';
    END IF;
END $$;


-- ============================================================================
-- SECTION H: Pre-registration hijack defense & find_auth_user verification
-- ============================================================================
DO $$
DECLARE
    v_victim_mobile TEXT := '9876543210';
    v_attacker_uid  UUID := gen_random_uuid();
    v_found_user    RECORD;
BEGIN
    -- 1. Plain signup: insert auth.users with NO role in raw_app_meta_data,
    -- and raw_user_meta_data containing victim's mobile (attacker spoof attempt)
    INSERT INTO auth.users (
        id, aud, role, email,
        raw_app_meta_data,
        raw_user_meta_data
    ) VALUES (
        v_attacker_uid, 'authenticated', 'authenticated', 'victim_pre_hijack@test.com',
        '{}'::jsonb, -- raw_app_meta_data without 'role'
        json_build_object('mobile', v_victim_mobile, 'name', 'Victim Hijack Attempt')::jsonb
    );

    -- Assert NO public.users row was created by private.on_auth_user_created
    IF EXISTS (SELECT 1 FROM public.users WHERE id = v_attacker_uid) THEN
        RAISE EXCEPTION '[FAIL] H1 - public.users row was created for unprivileged signup without app_metadata role!';
    END IF;
    RAISE NOTICE '[PASS] H1 - plain signup without role in raw_app_meta_data created NO public.users profile';

    -- 2. find_auth_user must NOT return an email-only match
    -- If we query find_auth_user with a different phone, it must return 0 rows
    SELECT * INTO v_found_user FROM public.find_auth_user('+919999999999');
    IF v_found_user.id IS NOT NULL THEN
        RAISE EXCEPTION '[FAIL] H2 - find_auth_user matched non-existent phone: %', v_found_user.id;
    END IF;

    -- Query find_auth_user with the attacker's mobile digits: since auth.users.phone was NULL, it must NOT match
    SELECT * INTO v_found_user FROM public.find_auth_user('+91' || v_victim_mobile);
    IF v_found_user.id IS NOT NULL THEN
        RAISE EXCEPTION '[FAIL] H2 - find_auth_user matched user via unconfirmed user_metadata mobile!';
    END IF;
    RAISE NOTICE '[PASS] H2 - find_auth_user matches phone strictly and ignores email/user_metadata';

    -- Cleanup
    DELETE FROM auth.users WHERE id = v_attacker_uid;
END $$;


-- ============================================================================
-- SECTION I: Demo Doctor Isolation Test
-- As the demo doctor's profile (a verified doctor with NO patient links),
-- verify that querying patients, health_records, appointments, prescriptions,
-- and patient_doctor_links returns 0 rows not owned by/linked to that doctor.
-- ============================================================================
DO $$
DECLARE
    v_demo_doc_uid   UUID := gen_random_uuid();
    v_demo_doc_id    TEXT := 'd_demo_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_uid      UUID := gen_random_uuid();
    v_other_pat_id   TEXT := 'p_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_doc_id   TEXT := 'd_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_appt_id  TEXT := 'ap_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_rec_id   TEXT := 'rec_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_rx_id    TEXT := 'rx_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_link_id  TEXT := 'pdl_other_isolate_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_other_doc_uid  UUID := gen_random_uuid();
    v_linked_pat_uid UUID := gen_random_uuid();
    v_linked_pat_id  TEXT := 'p_linked_iso_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_cnt            INT;
BEGIN
    -- 1. Setup Demo Doctor (verified = true, status = 'approved', NO patient links)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_demo_doc_uid, 'authenticated', 'authenticated', 'demo_doctor_iso@doctornect.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_demo_doc_uid, 'doctor', v_demo_doc_id, 'Dr. Demo Doctor', 'demo_doctor_iso@doctornect.com', '7666892394',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified
    ) VALUES (
        v_demo_doc_id, v_demo_doc_uid, 'Dr. Demo Doctor', 'demo_doctor_iso@doctornect.com',
        '7666892394', 'General Medicine', 'MBBS, MD', 10, TRUE
    );

    -- 2. Setup completely unlinked patient and doctor data
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_other_uid, 'authenticated', 'authenticated', 'unlinked_pat@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_other_uid, 'patient', v_other_pat_id, 'Unlinked Patient', 'unlinked_pat@test.com', '9998887776',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (
        patient_id, owner_uid, name, mobile, share_records_with_doctors
    ) VALUES (
        v_other_pat_id, v_other_uid, 'Unlinked Patient', '9998887776', TRUE
    );

    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_other_doc_uid, 'authenticated', 'authenticated', 'other_doc@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_other_doc_uid, 'doctor', v_other_doc_id, 'Dr. Other Doctor', 'other_doc@test.com', '9998887777',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified
    ) VALUES (
        v_other_doc_id, v_other_doc_uid, 'Dr. Other Doctor', 'other_doc@test.com',
        '9998887777', 'Cardiology', 'MD', 8, TRUE
    );

    INSERT INTO public.appointments (
        appointment_id, doctor_id, patient_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        visit_type, patient_status, doctor_status, source
    ) VALUES (
        v_other_appt_id, v_other_doc_id, v_other_pat_id, 'Dr. Other Doctor', 'Cardiology',
        'Unlinked Patient', 40, 'Male', NOW(), '09:00 AM', 'newVisit', 'confirmed', 'confirmed', 'app'
    );

    INSERT INTO public.health_records (
        record_id, patient_id, title, type, date, source, file_name, shared_with_doctors, file_storage
    ) VALUES (
        v_other_rec_id, v_other_pat_id, 'Private Record', 'prescription', NOW(), 'selfUploaded', 'rec.pdf', TRUE, 'none'
    );

    INSERT INTO public.prescriptions (
        prescription_id, doctor_id, patient_id, appointment_id,
        doctor_name, doctor_specialization, patient_name, patient_age, patient_gender,
        primary_diagnosis, symptoms, prescription_date
    ) VALUES (
        v_other_rx_id, v_other_doc_id, v_other_pat_id, v_other_appt_id,
        'Dr. Other Doctor', 'Cardiology', 'Unlinked Patient', 40, 'Male',
        'Hypertension', 'Headache', NOW()
    );

    INSERT INTO public.patient_doctor_links (
        patient_id, doctor_id, source
    ) VALUES (
        v_other_pat_id, v_other_doc_id, 'appointment'
    );

    -- 3. Setup linked patient for demo doctor (Positive Control)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_linked_pat_uid, 'authenticated', 'authenticated', 'linked_pat@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_linked_pat_uid, 'patient', v_linked_pat_id, 'Linked Patient', 'linked_pat@test.com', '9998887775',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (
        patient_id, owner_uid, name, mobile, share_records_with_doctors
    ) VALUES (
        v_linked_pat_id, v_linked_pat_uid, 'Linked Patient', '9998887775', TRUE
    );

    INSERT INTO public.patient_doctor_links (
        patient_id, doctor_id, source
    ) VALUES (
        v_linked_pat_id, v_demo_doc_id, 'appointment'
    );

    -- 4. Switch session to the demo doctor (v_demo_doc_uid)
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_demo_doc_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Positive control I_ctrl: demo doctor CAN read linked patient (count >= 1)
    SELECT count(*) INTO v_cnt FROM public.patients WHERE patient_id = v_linked_pat_id;
    IF v_cnt < 1 THEN
        RAISE EXCEPTION '[FAIL] I_ctrl - demo doctor cannot read linked patient (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I_ctrl - positive control: demo doctor CAN read linked patient (count=%)', v_cnt;

    -- Test I1: patients not owned/linked must return 0
    SELECT count(*) INTO v_cnt FROM public.patients WHERE patient_id = v_other_pat_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] I1 - demo doctor read unlinked patient row (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I1 - demo doctor cannot read unlinked patients (count=0)';

    -- Test I2: health_records not owned/linked must return 0
    SELECT count(*) INTO v_cnt FROM public.health_records WHERE record_id = v_other_rec_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] I2 - demo doctor read unlinked health_record row (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I2 - demo doctor cannot read unlinked health_records (count=0)';

    -- Test I3: appointments not owned/linked must return 0
    SELECT count(*) INTO v_cnt FROM public.appointments WHERE appointment_id = v_other_appt_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] I3 - demo doctor read unlinked appointment row (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I3 - demo doctor cannot read unlinked appointments (count=0)';

    -- Test I4: prescriptions not owned/linked must return 0
    SELECT count(*) INTO v_cnt FROM public.prescriptions WHERE prescription_id = v_other_rx_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] I4 - demo doctor read unlinked prescription row (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I4 - demo doctor cannot read unlinked prescriptions (count=0)';

    -- Test I5: patient_doctor_links not owned/linked must return 0
    SELECT count(*) INTO v_cnt FROM public.patient_doctor_links WHERE patient_id = v_other_pat_id AND doctor_id = v_other_doc_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] I5 - demo doctor read unlinked patient_doctor_links row (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] I5 - demo doctor cannot read unlinked patient_doctor_links (count=0)';

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- Cleanup
    DELETE FROM public.patient_doctor_links WHERE patient_id IN (v_other_pat_id, v_linked_pat_id);
    DELETE FROM public.prescriptions WHERE prescription_id = v_other_rx_id;
    DELETE FROM public.health_records WHERE record_id = v_other_rec_id;
    DELETE FROM public.appointments WHERE appointment_id = v_other_appt_id;
    DELETE FROM public.doctors WHERE doctor_id IN (v_demo_doc_id, v_other_doc_id);
    DELETE FROM public.patients WHERE patient_id IN (v_other_pat_id, v_linked_pat_id);
    DELETE FROM public.users WHERE id IN (v_demo_doc_uid, v_other_uid, v_other_doc_uid, v_linked_pat_uid);
    DELETE FROM auth.users WHERE id IN (v_demo_doc_uid, v_other_uid, v_other_doc_uid, v_linked_pat_uid);
END $$;


-- ============================================================================
-- SECTION J: NO-PROFILE USER ISOLATION & STORAGE AUDIT
-- ============================================================================
-- An authenticated user exists in auth.users, but has NO row in public.users.
-- For every table holding patient data:
--   patients, appointments, health_records, prescriptions, reviews,
--   patient_doctor_links, lab_bookings, lab_orders, in_app_notifications
-- 1. SELECT count must return 0
-- 2. INSERT and UPDATE must be blocked (v_blocked pattern or 0 rows updated)
-- ============================================================================
DO $$
DECLARE
    -- Fixture data owned by existing valid users
    v_fix_pat_uid UUID := gen_random_uuid();
    v_fix_pat_id TEXT := 'p_fixture_sec_j';
    v_fix_doc_uid UUID := gen_random_uuid();
    v_fix_doc_id TEXT := 'd_fixture_sec_j';
    v_fix_appt_id TEXT := 'apt_fixture_sec_j';
    v_fix_rec_id TEXT := 'hr_fixture_sec_j';
    v_fix_rx_id TEXT := 'rx_fixture_sec_j';
    v_fix_rev_id TEXT := 'rev_fixture_sec_j';
    v_fix_link_id TEXT := 'link_fixture_sec_j';
    v_fix_booking_id TEXT := 'bk_fixture_sec_j';
    v_fix_order_id TEXT := 'ord_fixture_sec_j';
    v_fix_notif_id TEXT := 'ntf_fixture_sec_j';

    -- No-profile authenticated user (auth.users only, NO public.users row)
    v_noprofile_uid UUID := gen_random_uuid();

    v_cnt INT;
    v_blocked BOOLEAN;
    v_rowcount INT;
    r RECORD;
    v_has_storage_policies BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '--- START SECTION J: No-Profile User Isolation & Storage Audit ---';

    -- 1. Setup fixture owner users and records via superuser
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data)
    VALUES
        (v_fix_pat_uid, 'authenticated', 'authenticated', 'fix_pat@doctornect.invalid', '{"skip_provision": "true"}'::jsonb),
        (v_fix_doc_uid, 'authenticated', 'authenticated', 'fix_doc@doctornect.invalid', '{"skip_provision": "true"}'::jsonb),
        (v_noprofile_uid, 'authenticated', 'authenticated', 'noprofile@doctornect.invalid', '{}'::jsonb);

    INSERT INTO public.users (id, role, profile_id, display_name, email, mobile, status)
    VALUES
        (v_fix_pat_uid, 'patient', v_fix_pat_id, 'Fixture Patient', 'fix_pat@doctornect.invalid', '9870000001', 'approved'),
        (v_fix_doc_uid, 'doctor', v_fix_doc_id, 'Dr Fixture', 'fix_doc@doctornect.invalid', '9870000002', 'approved');

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_fix_pat_id, v_fix_pat_uid, 'Fixture Patient', '9870000001');

    INSERT INTO public.doctors (doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified)
    VALUES (v_fix_doc_id, v_fix_doc_uid, 'Dr Fixture', 'fix_doc@signup.doctornect.app', '9870000002', 'General', 'MBBS', 5, TRUE);

    INSERT INTO public.appointments (
        appointment_id, doctor_id, patient_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        visit_type, patient_status, doctor_status, source
    ) VALUES (
        v_fix_appt_id, v_fix_doc_id, v_fix_pat_id, 'Dr Fixture', 'General',
        'Fixture Patient', 35, 'Male', NOW() + INTERVAL '1 day', '10:00 AM',
        'newVisit', 'confirmed', 'confirmed', 'app'
    );

    INSERT INTO public.health_records (
        record_id, patient_id, title, type, date, source, file_name, file_storage, storage_url
    ) VALUES (
        v_fix_rec_id, v_fix_pat_id, 'Fixture Record', 'prescription', NOW(), 'selfUploaded', 'record.pdf', 'none', 'http://none'
    );

    INSERT INTO public.prescriptions (
        prescription_id, doctor_id, patient_id, appointment_id,
        doctor_name, doctor_specialization, patient_name, patient_age, patient_gender,
        primary_diagnosis, symptoms, prescription_date
    ) VALUES (
        v_fix_rx_id, v_fix_doc_id, v_fix_pat_id, v_fix_appt_id,
        'Dr Fixture', 'General', 'Fixture Patient', 35, 'Male',
        'Fever', 'Chills', NOW()
    );

    INSERT INTO public.reviews (
        review_id, patient_id, doctor_id, appointment_id, patient_name, rating, comment
    ) VALUES (
        v_fix_rev_id, v_fix_pat_id, v_fix_doc_id, v_fix_appt_id, 'Fixture Patient', 5, 'Great doctor'
    );

    INSERT INTO public.patient_doctor_links (
        patient_id, doctor_id, source
    ) VALUES (
        v_fix_pat_id, v_fix_doc_id, 'appointment'
    );

    INSERT INTO public.lab_bookings (
        booking_id, patient_id, patient_name, patient_age, test_id, test_name, test_names,
        collection_type, date_time, slot_label, status, source
    ) VALUES (
        v_fix_booking_id, v_fix_pat_id, 'Fixture Patient', 35, 'test_cbc', 'CBC', ARRAY['CBC'],
        'labVisit', NOW() + INTERVAL '1 day', '09:00 AM', 'confirmed', 'app'
    );

    INSERT INTO public.lab_orders (
        order_id, doctor_id, patient_id, doctor_name, patient_name, patient_age,
        test_ids, test_names, urgency, status
    ) VALUES (
        v_fix_order_id, v_fix_doc_id, v_fix_pat_id, 'Dr Fixture', 'Fixture Patient', 35,
        ARRAY['test_cbc'], ARRAY['CBC'], 'Routine', 'ordered'
    );

    INSERT INTO public.in_app_notifications (
        notification_id, recipient_uid, title, body, type
    ) VALUES (
        v_fix_notif_id, v_fix_pat_uid, 'Fixture Notification', 'Welcome', 'system'
    );

    -- 2. Switch session to the NO-PROFILE authenticated user
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_noprofile_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- ========================================================================
    -- Table 1: patients
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.patients WHERE patient_id = v_fix_pat_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J1_patients_select: no-profile user read patient row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
        VALUES ('p_noprf', v_noprofile_uid, 'No Profile Hacker', '9999999991');
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J1_patients_insert: no-profile user inserted patient row without profile';
    END IF;

    UPDATE public.patients SET name = 'Hacked' WHERE patient_id = v_fix_pat_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J1_patients_update: no-profile user updated patient row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J1 - patients: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 2: appointments
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.appointments WHERE appointment_id = v_fix_appt_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J2_appointments_select: no-profile user read appointment row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.appointments (
            appointment_id, doctor_id, patient_id, doctor_name, specialization,
            patient_name, patient_age, patient_gender, date_time, slot_label,
            visit_type, patient_status, doctor_status, source
        ) VALUES (
            'apt_noprf', v_fix_doc_id, v_fix_pat_id, 'Dr Fixture', 'General',
            'Fixture Patient', 35, 'Male', NOW() + INTERVAL '2 days', '11:00 AM',
            'newVisit', 'confirmed', 'confirmed', 'app'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J2_appointments_insert: no-profile user inserted appointment row';
    END IF;

    UPDATE public.appointments SET patient_status = 'cancelled' WHERE appointment_id = v_fix_appt_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J2_appointments_update: no-profile user updated appointment row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J2 - appointments: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 3: health_records
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.health_records WHERE record_id = v_fix_rec_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J3_health_records_select: no-profile user read health_records row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.health_records (
            record_id, patient_id, title, type, date, source, file_name, file_storage, storage_url
        ) VALUES (
            'hr_noprf', v_fix_pat_id, 'Hacked HR', 'prescription', NOW(), 'selfUploaded', 'record.pdf', 'none', 'http://none'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J3_health_records_insert: no-profile user inserted health_records row';
    END IF;

    UPDATE public.health_records SET title = 'Hacked' WHERE record_id = v_fix_rec_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J3_health_records_update: no-profile user updated health_records row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J3 - health_records: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 4: prescriptions
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.prescriptions WHERE prescription_id = v_fix_rx_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J4_prescriptions_select: no-profile user read prescription row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.prescriptions (
            prescription_id, doctor_id, patient_id, appointment_id,
            doctor_name, doctor_specialization, patient_name, patient_age, patient_gender,
            primary_diagnosis, symptoms, prescription_date
        ) VALUES (
            'rx_noprf', v_fix_doc_id, v_fix_pat_id, v_fix_appt_id,
            'Dr Hack', 'General', 'Fixture Patient', 35, 'Male',
            'Hacked Dx', 'Hacked Sx', NOW()
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J4_prescriptions_insert: no-profile user inserted prescription row';
    END IF;

    UPDATE public.prescriptions SET primary_diagnosis = 'cancelled' WHERE prescription_id = v_fix_rx_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J4_prescriptions_update: no-profile user updated prescription row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J4 - prescriptions: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 5: reviews
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.reviews WHERE review_id = v_fix_rev_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J5_reviews_select: no-profile user read review row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.reviews (
            review_id, patient_id, doctor_id, appointment_id, patient_name, rating, comment
        ) VALUES (
            'rev_noprf', v_fix_pat_id, v_fix_doc_id, v_fix_appt_id, 'Hacker', 1, 'Spam Review'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J5_reviews_insert: no-profile user inserted review row';
    END IF;

    UPDATE public.reviews SET rating = 1 WHERE review_id = v_fix_rev_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J5_reviews_update: no-profile user updated review row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J5 - reviews: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 6: patient_doctor_links
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.patient_doctor_links WHERE patient_id = v_fix_pat_id AND doctor_id = v_fix_doc_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J6_links_select: no-profile user read patient_doctor_links row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.patient_doctor_links (patient_id, doctor_id, source)
        VALUES (v_fix_pat_id, v_fix_doc_id, 'manual');
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J6_links_insert: no-profile user inserted patient_doctor_links row';
    END IF;

    v_blocked := false;
    BEGIN
        UPDATE public.patient_doctor_links SET source = 'referral' WHERE patient_id = v_fix_pat_id AND doctor_id = v_fix_doc_id;
        GET DIAGNOSTICS v_rowcount = ROW_COUNT;
        IF v_rowcount = 0 THEN v_blocked := true; END IF;
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J6_links_update: no-profile user updated patient_doctor_links row';
    END IF;
    RAISE NOTICE '[PASS] J6 - patient_doctor_links: SELECT count=0, INSERT blocked 42501, UPDATE blocked';

    -- ========================================================================
    -- Table 7: lab_bookings (lab reports)
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.lab_bookings WHERE booking_id = v_fix_booking_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J7_lab_bookings_select: no-profile user read lab_bookings row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.lab_bookings (
            booking_id, patient_id, patient_name, patient_age, test_id, test_name, test_names,
            collection_type, date_time, slot_label, status, source
        ) VALUES (
            'bk_noprf', v_fix_pat_id, 'Hacker', 25, 'test_cbc', 'CBC', ARRAY['CBC'],
            'labVisit', NOW() + INTERVAL '2 days', '10:00 AM', 'confirmed', 'app'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J7_lab_bookings_insert: no-profile user inserted lab_bookings row';
    END IF;

    UPDATE public.lab_bookings SET status = 'cancelled' WHERE booking_id = v_fix_booking_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J7_lab_bookings_update: no-profile user updated lab_bookings row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J7 - lab_bookings: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 8: lab_orders (lab reports)
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.lab_orders WHERE order_id = v_fix_order_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J8_lab_orders_select: no-profile user read lab_orders row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.lab_orders (
            order_id, doctor_id, patient_id, doctor_name, patient_name, patient_age,
            test_ids, test_names, urgency, status
        ) VALUES (
            'ord_noprf', v_fix_doc_id, v_fix_pat_id, 'Dr Hack', 'Fixture Patient', 35,
            ARRAY['test_cbc'], ARRAY['CBC'], 'Routine', 'ordered'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J8_lab_orders_insert: no-profile user inserted lab_orders row';
    END IF;

    UPDATE public.lab_orders SET status = 'completed' WHERE order_id = v_fix_order_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J8_lab_orders_update: no-profile user updated lab_orders row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J8 - lab_orders: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- ========================================================================
    -- Table 9: in_app_notifications
    -- ========================================================================
    SELECT count(*) INTO v_cnt FROM public.in_app_notifications WHERE notification_id = v_fix_notif_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] J9_notifications_select: no-profile user read notification row (count=%)', v_cnt;
    END IF;

    v_blocked := false;
    BEGIN
        INSERT INTO public.in_app_notifications (
            notification_id, recipient_uid, title, body, type
        ) VALUES (
            'ntf_noprf', v_noprofile_uid, 'Hacked Notif', 'Body', 'system'
        );
    EXCEPTION WHEN sqlstate '42501' THEN v_blocked := true;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] J9_notifications_insert: no-profile user inserted notification row';
    END IF;

    UPDATE public.in_app_notifications SET is_read = TRUE WHERE notification_id = v_fix_notif_id;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount <> 0 THEN
        RAISE EXCEPTION '[FAIL] J9_notifications_update: no-profile user updated notification row (rowcount=%)', v_rowcount;
    END IF;
    RAISE NOTICE '[PASS] J9 - in_app_notifications: SELECT count=0, INSERT blocked 42501, UPDATE 0 rows';

    -- Reset back to superuser
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    -- 3. Audit storage.objects policies for authenticated role
    RAISE NOTICE '--- STORAGE.OBJECTS POLICIES FOR AUTHENTICATED ---';
    FOR r IN (
        SELECT policyname, tablename, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND ('authenticated' = ANY(roles) OR 'public' = ANY(roles))
    ) LOOP
        v_has_storage_policies := TRUE;
        RAISE NOTICE 'Storage Policy: % on % (CMD: %) QUAL: % WITH CHECK: %',
            r.policyname, r.tablename, r.cmd, r.qual, r.with_check;
    END LOOP;
    IF NOT v_has_storage_policies THEN
        RAISE NOTICE 'Storage Policy: No storage.objects policies found allowing authenticated without profile checks in current schema.';
    END IF;

    -- Cleanup Section J fixtures
    DELETE FROM public.in_app_notifications WHERE notification_id = v_fix_notif_id;
    DELETE FROM public.lab_orders WHERE order_id = v_fix_order_id;
    DELETE FROM public.lab_bookings WHERE booking_id = v_fix_booking_id;
    DELETE FROM public.patient_doctor_links WHERE patient_id = v_fix_pat_id AND doctor_id = v_fix_doc_id;
    DELETE FROM public.reviews WHERE review_id = v_fix_rev_id;
    DELETE FROM public.prescriptions WHERE prescription_id = v_fix_rx_id;
    DELETE FROM public.health_records WHERE record_id = v_fix_rec_id;
    DELETE FROM public.appointments WHERE appointment_id = v_fix_appt_id;
    DELETE FROM public.doctors WHERE doctor_id = v_fix_doc_id;
    DELETE FROM public.patients WHERE patient_id = v_fix_pat_id;
    DELETE FROM public.users WHERE id IN (v_fix_pat_uid, v_fix_doc_uid);
    DELETE FROM auth.users WHERE id IN (v_fix_pat_uid, v_fix_doc_uid, v_noprofile_uid);
END $$;


-- ============================================================================
-- SECTION K: DUPLICATE USERS REPORT QUERY (MOBILE & PROFILE_ID)
-- ============================================================================
-- Report-only query identifying duplicate mobiles or profile_ids across public.users
DO $$
DECLARE
    r RECORD;
    v_dup_mobile_count INT := 0;
    v_dup_profile_count INT := 0;
BEGIN
    RAISE NOTICE '--- START SECTION K: Duplicate public.users Audit Report ---';

    FOR r IN (
        SELECT mobile, COUNT(*) AS cnt, array_agg(id::text) AS user_ids, array_agg(role) AS roles
        FROM public.users
        WHERE mobile IS NOT NULL AND mobile <> ''
        GROUP BY mobile
        HAVING COUNT(*) > 1
    ) LOOP
        v_dup_mobile_count := v_dup_mobile_count + 1;
        RAISE WARNING 'Duplicate public.users.mobile: % (count: %, ids: %, roles: %)',
            r.mobile, r.cnt, r.user_ids, r.roles;
    END LOOP;

    FOR r IN (
        SELECT profile_id, COUNT(*) AS cnt, array_agg(id::text) AS user_ids, array_agg(role) AS roles
        FROM public.users
        WHERE profile_id IS NOT NULL AND profile_id <> ''
        GROUP BY profile_id
        HAVING COUNT(*) > 1
    ) LOOP
        v_dup_profile_count := v_dup_profile_count + 1;
        RAISE WARNING 'Duplicate public.users.profile_id: % (count: %, ids: %, roles: %)',
            r.profile_id, r.cnt, r.user_ids, r.roles;
    END LOOP;

    IF v_dup_mobile_count = 0 THEN
        RAISE NOTICE '[PASS] K1 - No duplicate public.users.mobile rows found';
    ELSE
        RAISE NOTICE '[INFO] K1 - Found % duplicate mobile group(s)', v_dup_mobile_count;
    END IF;

    IF v_dup_profile_count = 0 THEN
        RAISE NOTICE '[PASS] K2 - No duplicate public.users.profile_id rows found';
    ELSE
        RAISE NOTICE '[INFO] K2 - Found % duplicate profile_id group(s)', v_dup_profile_count;
    END IF;
END $$;


-- ============================================================================
-- SECTION L: TRIGGER PROVISIONING TEST FROM raw_app_meta_data
-- ============================================================================
-- Verifies that a new auth.users row with raw_app_meta_data {"role":"patient","mobile":"..."}
-- activates private.on_auth_user_created and provisions a public.users row with
-- public.users.mobile set to that exact mobile.
DO $$
DECLARE
    v_test_uid UUID := gen_random_uuid();
    v_expected_mobile TEXT := '9876501234';
    v_actual_mobile TEXT;
    v_actual_role TEXT;
BEGIN
    RAISE NOTICE '--- START SECTION L: Trigger Provisioning from raw_app_meta_data ---';

    -- 1. Insert into auth.users as a service_role signup with role and mobile in raw_app_meta_data
    INSERT INTO auth.users (
        id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
        is_sso_user, is_anonymous, created_at, updated_at
    ) VALUES (
        v_test_uid, 'authenticated', 'authenticated',
        v_test_uid::text || '@signup.doctornect.app',
        jsonb_build_object('role', 'patient', 'mobile', v_expected_mobile),
        jsonb_build_object('role', 'patient'),
        FALSE, FALSE, NOW(), NOW()
    );

    -- 2. Verify trigger provisioned public.users row with exact mobile and role
    SELECT mobile, role INTO v_actual_mobile, v_actual_role
    FROM public.users
    WHERE id = v_test_uid;

    IF v_actual_mobile IS DISTINCT FROM v_expected_mobile THEN
        RAISE EXCEPTION '[FAIL] L1 - Trigger did not set public.users.mobile correctly. Expected %, got %',
            v_expected_mobile, v_actual_mobile;
    END IF;

    IF v_actual_role IS DISTINCT FROM 'patient' THEN
        RAISE EXCEPTION '[FAIL] L2 - Trigger did not set public.users.role correctly. Expected patient, got %',
            v_actual_role;
    END IF;

    RAISE NOTICE '[PASS] L1/L2 - Trigger successfully provisioned public.users row with mobile=% and role=%',
        v_actual_mobile, v_actual_role;

    -- Cleanup
    DELETE FROM public.users WHERE id = v_test_uid;
    DELETE FROM auth.users WHERE id = v_test_uid;
END $$;


-- ============================================================================
-- SECTION N: ADMIN GATE & IS_SUPER_ADMIN() VERIFICATION
-- Tests private.admin_users RLS lockdown and is_super_admin() security gate.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- N1: Normal authenticated user (not in private.admin_users) has is_super_admin() = FALSE
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid      UUID := gen_random_uuid();
    v_pat_id   TEXT := 'p_n1_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_is_admin BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'user_n1@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'Normal User N1', 'user_n1@test.com', '9000000081',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_is_admin := public.is_super_admin();

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION '[FAIL] N1 - normal user without admin_users row returned is_super_admin() = % (expected FALSE)', v_is_admin;
    END IF;
    RAISE NOTICE '[PASS] N1 - normal authenticated user without admin_users row has is_super_admin() = FALSE';

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N2: User with row in private.admin_users has is_super_admin() = TRUE
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid      UUID := gen_random_uuid();
    v_pat_id   TEXT := 'p_n2_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_is_admin BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'admin_n2@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'Admin User N2', 'admin_n2@test.com', '9000000082',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    -- Superuser inserts row into private.admin_users
    INSERT INTO private.admin_users (user_id)
    VALUES (v_uid)
    ON CONFLICT (user_id) DO NOTHING;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_is_admin := public.is_super_admin();

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION '[FAIL] N2 - user with private.admin_users row returned is_super_admin() = % (expected TRUE)', v_is_admin;
    END IF;
    RAISE NOTICE '[PASS] N2 - user with private.admin_users row has is_super_admin() = TRUE';

    DELETE FROM private.admin_users WHERE user_id = v_uid;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N3: Authenticated user cannot SELECT/INSERT/UPDATE/DELETE on private.admin_users
-- (Self-promotion blocked via 42501 / insufficient_privilege)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid     UUID := gen_random_uuid();
    v_pat_id  TEXT := 'p_n3_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'user_n3@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'User N3', 'user_n3@test.com', '9000000083',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- 1. Attempt self-promotion INSERT into private.admin_users
    v_blocked := FALSE;
    BEGIN
        INSERT INTO private.admin_users (user_id) VALUES (v_uid);
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] N3 - authenticated user was able to INSERT into private.admin_users (self-promotion)';
    END IF;

    -- 2. Attempt SELECT on private.admin_users
    v_blocked := FALSE;
    BEGIN
        PERFORM 1 FROM private.admin_users;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] N3 - authenticated user was able to SELECT from private.admin_users';
    END IF;

    -- 3. Attempt UPDATE on private.admin_users
    v_blocked := FALSE;
    BEGIN
        UPDATE private.admin_users SET granted_at = NOW();
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] N3 - authenticated user was able to UPDATE private.admin_users';
    END IF;

    -- 4. Attempt DELETE on private.admin_users
    v_blocked := FALSE;
    BEGIN
        DELETE FROM private.admin_users WHERE user_id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION '[FAIL] N3 - authenticated user was able to DELETE from private.admin_users';
    END IF;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    RAISE NOTICE '[PASS] N3 - authenticated user denied SELECT/INSERT/UPDATE/DELETE on private.admin_users (42501)';

    DELETE FROM private.admin_users WHERE user_id = v_uid;
    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N4: public.users.role = 'super_admin' / 'admin' without private.admin_users row
-- (Informational only: report observed behavior with [INFO])
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid      UUID := gen_random_uuid();
    v_pat_id   TEXT := 'p_n4_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_is_admin BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'role_admin_n4@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'super_admin', v_pat_id, 'Role SuperAdmin N4', 'role_admin_n4@test.com', '9000000084',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_is_admin := public.is_super_admin();

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    RAISE NOTICE '[INFO] N4 - public.users.role=''super_admin'' without private.admin_users row returned is_super_admin() = %',
        v_is_admin;

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N5: Admin can read another patient's appointments (positive control); non-admin cannot
-- Verifies appointments_select policy is_super_admin() branch.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_target_pat_uid   UUID := gen_random_uuid();
    v_target_pat_id    TEXT := 'p_n5_tgt_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_target_doc_uid   UUID := gen_random_uuid();
    v_target_doc_id    TEXT := 'd_n5_tgt_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_target_appt_id   TEXT := 'ap_n5_tgt_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_non_admin_uid    UUID := gen_random_uuid();
    v_non_admin_pat_id TEXT := 'p_n5_norm_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_admin_uid        UUID := gen_random_uuid();
    v_admin_pat_id     TEXT := 'p_n5_adm_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_cnt              INT;
BEGIN
    -- 1. Setup target patient
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_target_pat_uid, 'authenticated', 'authenticated', 'tgt_pat_n5@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_target_pat_uid, 'patient', v_target_pat_id, 'Target Patient N5', 'tgt_pat_n5@test.com', '9000000085',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_target_pat_id, v_target_pat_uid, 'Target Patient N5', '9000000085');

    -- 2. Setup target doctor
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_target_doc_uid, 'authenticated', 'authenticated', 'tgt_doc_n5@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_target_doc_uid, 'doctor', v_target_doc_id, 'Dr. Target N5', 'tgt_doc_n5@test.com', '9000000086',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.doctors (
        doctor_id, owner_uid, name, email, mobile, specialization, qualification, experience_years, verified
    ) VALUES (
        v_target_doc_id, v_target_doc_uid, 'Dr. Target N5', 'tgt_doc_n5@test.com',
        '9000000086', 'General', 'MBBS', 5, TRUE
    );

    -- 3. Setup appointment between target patient and doctor
    INSERT INTO public.appointments (
        appointment_id, doctor_id, patient_id, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label,
        visit_type, patient_status, doctor_status, source
    ) VALUES (
        v_target_appt_id, v_target_doc_id, v_target_pat_id, 'Dr. Target N5', 'General',
        'Target Patient N5', 28, 'Female', NOW(), '02:00 PM',
        'newVisit', 'confirmed', 'confirmed', 'app'
    );

    -- 4. Setup non-admin user
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_non_admin_uid, 'authenticated', 'authenticated', 'norm_user_n5@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_non_admin_uid, 'patient', v_non_admin_pat_id, 'Normal User N5', 'norm_user_n5@test.com', '9000000087',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_non_admin_pat_id, v_non_admin_uid, 'Normal User N5', '9000000087');

    -- 5. Setup admin user (has row in private.admin_users)
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_admin_uid, 'authenticated', 'authenticated', 'admin_user_n5@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_admin_uid, 'patient', v_admin_pat_id, 'Admin User N5', 'admin_user_n5@test.com', '9000000088',
        TRUE, TRUE, FALSE, 'approved'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES (v_admin_pat_id, v_admin_uid, 'Admin User N5', '9000000088');

    INSERT INTO private.admin_users (user_id)
    VALUES (v_admin_uid)
    ON CONFLICT (user_id) DO NOTHING;

    -- Test 5a: non-admin session cannot read target appointment
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_non_admin_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO v_cnt FROM public.appointments WHERE appointment_id = v_target_appt_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '[FAIL] N5 - non-admin user read unrelated appointment (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] N5_ctrl - non-admin cannot read unrelated appointment (count=0)';

    -- Test 5b: admin session CAN read target appointment
    RESET ROLE;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO v_cnt FROM public.appointments WHERE appointment_id = v_target_appt_id;
    IF v_cnt < 1 THEN
        RAISE EXCEPTION '[FAIL] N5 - admin user cannot read unrelated appointment (count=%)', v_cnt;
    END IF;
    RAISE NOTICE '[PASS] N5 - admin CAN read unrelated appointment (count=%) via is_super_admin()', v_cnt;

    -- Cleanup
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    DELETE FROM private.admin_users WHERE user_id = v_admin_uid;
    DELETE FROM public.appointments WHERE appointment_id = v_target_appt_id;
    DELETE FROM public.doctors WHERE doctor_id = v_target_doc_id;
    DELETE FROM public.patients WHERE patient_id IN (v_target_pat_id, v_non_admin_pat_id, v_admin_pat_id);
    DELETE FROM public.users WHERE id IN (v_target_pat_uid, v_target_doc_uid, v_non_admin_uid, v_admin_uid);
    DELETE FROM auth.users WHERE id IN (v_target_pat_uid, v_target_doc_uid, v_non_admin_uid, v_admin_uid);
END $$;


-- ----------------------------------------------------------------------------
-- N6a: Authenticated patient attempting UPDATE role='admin' on public.users
-- (Must be blocked by column grants / trigger / RLS; role must stay 'patient')
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid      UUID := gen_random_uuid();
    v_pat_id   TEXT := 'p_n6a_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked  BOOLEAN := FALSE;
    v_role     TEXT;
    v_is_admin BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'patient_n6a@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'Patient N6a', 'patient_n6a@test.com', '9000000091',
        TRUE, FALSE, FALSE, 'pending'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    -- Switch to authenticated patient session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    BEGIN
        UPDATE public.users SET role = 'admin' WHERE id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    -- Reset to superuser to verify DB state
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    SELECT role INTO v_role FROM public.users WHERE id = v_uid;

    -- Also check is_super_admin() under patient session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;
    v_is_admin := public.is_super_admin();
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF NOT v_blocked AND v_role = 'admin' THEN
        RAISE EXCEPTION '[FAIL] N6a - authenticated patient successfully escalated role to admin!';
    END IF;

    IF v_role IS DISTINCT FROM 'patient' THEN
        RAISE EXCEPTION '[FAIL] N6a - public.users.role was modified (current: %, expected: patient)', v_role;
    END IF;

    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION '[FAIL] N6a - is_super_admin() returned % after failed escalation (expected FALSE)', v_is_admin;
    END IF;

    RAISE NOTICE '[PASS] N6a - authenticated patient blocked from UPDATE role=''admin'' (role=%, is_super_admin=FALSE)',
        v_role;

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N6b: Authenticated patient attempting UPDATE role='super_admin' or 'superAdmin'
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid      UUID := gen_random_uuid();
    v_pat_id   TEXT := 'p_n6b_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked1 BOOLEAN := FALSE;
    v_blocked2 BOOLEAN := FALSE;
    v_role     TEXT;
    v_is_admin BOOLEAN;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'patient_n6b@test.com')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'Patient N6b', 'patient_n6b@test.com', '9000000092',
        TRUE, FALSE, FALSE, 'pending'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    -- Switch to authenticated patient session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- Try UPDATE role = 'super_admin'
    BEGIN
        UPDATE public.users SET role = 'super_admin' WHERE id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked1 := TRUE;
        WHEN sqlstate '42501' THEN v_blocked1 := TRUE;
    END;

    -- Try UPDATE role = 'superAdmin'
    BEGIN
        UPDATE public.users SET role = 'superAdmin' WHERE id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked2 := TRUE;
        WHEN sqlstate '42501' THEN v_blocked2 := TRUE;
    END;

    -- Reset to superuser to verify DB state
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    SELECT role INTO v_role FROM public.users WHERE id = v_uid;

    -- Verify is_super_admin() under patient session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;
    v_is_admin := public.is_super_admin();
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    IF (NOT v_blocked1 OR NOT v_blocked2) AND v_role IN ('super_admin', 'superAdmin') THEN
        RAISE EXCEPTION '[FAIL] N6b - authenticated patient escalated role to %!', v_role;
    END IF;

    IF v_role IS DISTINCT FROM 'patient' THEN
        RAISE EXCEPTION '[FAIL] N6b - public.users.role was modified (current: %, expected: patient)', v_role;
    END IF;

    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION '[FAIL] N6b - is_super_admin() returned % (expected FALSE)', v_is_admin;
    END IF;

    RAISE NOTICE '[PASS] N6b - authenticated patient blocked from UPDATE role to super_admin/superAdmin (role=%, is_super_admin=FALSE)',
        v_role;

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N6c: Authenticated user without public.users row attempting INSERT role='admin'
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid     UUID := gen_random_uuid();
    v_pat_id  TEXT := 'p_n6c_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked BOOLEAN := FALSE;
    v_exists  BOOLEAN;
BEGIN
    -- Auth user exists in auth.users, but NO row in public.users
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data)
    VALUES (v_uid, 'authenticated', 'authenticated', 'noprofile_n6c@test.com', '{"skip_provision":"true"}'::jsonb)
    ON CONFLICT (id) DO NOTHING;

    -- Switch to authenticated session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    BEGIN
        INSERT INTO public.users (
            id, role, profile_id, display_name, email, mobile,
            profile_completed, verified, deactivated, status
        ) VALUES (
            v_uid, 'admin', v_pat_id, 'Attacker N6c', 'noprofile_n6c@test.com', '9000000093',
            TRUE, TRUE, FALSE, 'approved'
        );
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked := TRUE;
        WHEN sqlstate '42501' THEN v_blocked := TRUE;
    END;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    SELECT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid) INTO v_exists;

    IF NOT v_blocked AND v_exists THEN
        RAISE EXCEPTION '[FAIL] N6c - authenticated user without profile was able to INSERT public.users row with role=''admin''!';
    END IF;

    IF v_exists THEN
        RAISE EXCEPTION '[FAIL] N6c - public.users row exists for unprivileged INSERT attempt';
    END IF;

    RAISE NOTICE '[PASS] N6c - authenticated user without profile blocked from direct INSERT into public.users (42501)';

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N6d: Authenticated patient attempting UPDATE verified=true and status='approved'
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid              UUID := gen_random_uuid();
    v_pat_id           TEXT := 'p_n6d_' || replace(gen_random_uuid()::TEXT, '-', '');
    v_blocked_verified BOOLEAN := FALSE;
    v_blocked_status   BOOLEAN := FALSE;
    v_verified         BOOLEAN;
    v_status           TEXT;
BEGIN
    INSERT INTO auth.users (id, aud, role, email)
    VALUES (v_uid, 'authenticated', 'authenticated', 'patient_n6d@test.com')
    ON CONFLICT (id) DO NOTHING;

    -- Setup patient with verified = FALSE and status = 'pending'
    INSERT INTO public.users (
        id, role, profile_id, display_name, email, mobile,
        profile_completed, verified, deactivated, status
    ) VALUES (
        v_uid, 'patient', v_pat_id, 'Patient N6d', 'patient_n6d@test.com', '9000000094',
        TRUE, FALSE, FALSE, 'pending'
    )
    ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, profile_id = EXCLUDED.profile_id;

    -- Switch to authenticated session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    -- 1. Attempt UPDATE verified = TRUE
    BEGIN
        UPDATE public.users SET verified = TRUE WHERE id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked_verified := TRUE;
        WHEN sqlstate '42501' THEN v_blocked_verified := TRUE;
    END;

    -- 2. Attempt UPDATE status = 'approved'
    BEGIN
        UPDATE public.users SET status = 'approved' WHERE id = v_uid;
    EXCEPTION
        WHEN insufficient_privilege THEN v_blocked_status := TRUE;
        WHEN sqlstate '42501' THEN v_blocked_status := TRUE;
    END;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    SELECT verified, status INTO v_verified, v_status FROM public.users WHERE id = v_uid;

    IF NOT v_blocked_verified AND v_verified = TRUE THEN
        RAISE EXCEPTION '[FAIL] N6d - authenticated patient was able to UPDATE verified=true!';
    END IF;

    IF NOT v_blocked_status AND v_status = 'approved' THEN
        RAISE EXCEPTION '[FAIL] N6d - authenticated patient was able to UPDATE status=''approved''!';
    END IF;

    IF v_verified IS DISTINCT FROM FALSE OR v_status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION '[FAIL] N6d - verified or status was altered (verified=%, status=%)', v_verified, v_status;
    END IF;

    RAISE NOTICE '[PASS] N6d - authenticated patient blocked from updating verified/status (verified=%, status=%)',
        v_verified, v_status;

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;


-- ----------------------------------------------------------------------------
-- N6e: Auth signup with raw_user_meta_data role='admin' (never trusted)
-- (Must NOT create admin in public.users; report observed behavior with [INFO])
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_uid         UUID := gen_random_uuid();
    v_actual_role TEXT;
    v_row_exists  BOOLEAN;
    v_is_admin    BOOLEAN;
BEGIN
    -- Insert auth.users row with role='admin' in raw_user_meta_data only
    INSERT INTO auth.users (
        id, aud, role, email,
        raw_app_meta_data,
        raw_user_meta_data,
        is_sso_user, is_anonymous, created_at, updated_at
    ) VALUES (
        v_uid, 'authenticated', 'authenticated', 'spoof_admin_n6e@test.com',
        '{}'::jsonb, -- raw_app_meta_data does NOT have role
        jsonb_build_object('role', 'admin', 'name', 'Attacker Admin'),
        FALSE, FALSE, NOW(), NOW()
    );

    SELECT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid) INTO v_row_exists;
    IF v_row_exists THEN
        SELECT role INTO v_actual_role FROM public.users WHERE id = v_uid;
    END IF;

    -- Check is_super_admin() under this user session
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;
    v_is_admin := public.is_super_admin();
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', TRUE);

    RAISE NOTICE '[INFO] N6e - auth signup with role=''admin'' in raw_user_meta_data: public.users row_exists=%, role=%, is_super_admin=%',
        v_row_exists, COALESCE(v_actual_role, '<none>'), v_is_admin;

    IF v_actual_role IN ('admin', 'super_admin', 'superAdmin') THEN
        RAISE EXCEPTION '[FAIL] N6e - unprivileged signup created public.users row with admin role (%)!', v_actual_role;
    END IF;

    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION '[FAIL] N6e - is_super_admin() is % for unprivileged signup with user_metadata role spoof!', v_is_admin;
    END IF;

    RAISE NOTICE '[PASS] N6e - raw_user_meta_data role=''admin'' ignored (row_exists=%, role=%, is_super_admin=FALSE)',
        v_row_exists, COALESCE(v_actual_role, '<none>');

    DELETE FROM public.users WHERE id = v_uid;
    DELETE FROM auth.users WHERE id = v_uid;
END $$;




-- ============================================================================
-- SECTION M: SECURITY AUDIT REPORT QUERIES (NO FIXES)
-- 1. Public tables with RLS disabled
-- 2. Views without security_invoker in public/private
-- 3. SECURITY DEFINER functions in public/private with EXECUTE for anon/authenticated
-- ============================================================================

-- M1: Public tables with RLS disabled
SELECT
    schemaname,
    tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = FALSE
ORDER BY tablename;

-- M2: Views without security_invoker in public/private
SELECT
    v.schemaname,
    v.viewname,
    COALESCE(array_to_string(c.reloptions, ', '), 'none') AS reloptions
FROM pg_views v
JOIN pg_class c ON c.relname = v.viewname
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = v.schemaname
WHERE v.schemaname IN ('public', 'private')
  AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
ORDER BY v.schemaname, v.viewname;

-- M3: SECURITY DEFINER functions in public/private with EXECUTE for anon or authenticated
SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    r.rolname AS granted_role
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS roles(rolname)
JOIN pg_roles r ON r.rolname = roles.rolname
WHERE n.nspname IN ('public', 'private')
  AND p.prosecdef = TRUE
  AND has_function_privilege(r.oid, p.oid, 'EXECUTE')
ORDER BY schema_name, function_name, granted_role;

DO $$ BEGIN RAISE NOTICE 'verification_script.sql finished; check [FAIL] lines above'; END $$;
