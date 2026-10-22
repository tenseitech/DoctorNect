-- ============================================================================
-- Test Suite: phase_f_test.sql
-- Description: Verifies Phase F cutover database additions and hardening
-- ============================================================================

CREATE TEMP TABLE phase_f_results (
    test_id INT,
    description TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);

DO $$
DECLARE
    v_uid TEXT := 'fb_uid_phase_f_001';
    v_doc_uid TEXT := 'fb_uid_phase_f_doc_001';
    v_store_uid TEXT := 'fb_uid_phase_f_store_001';
    v_appt_res JSONB;
    v_token INT;
    v_fn_count INT;
BEGIN
    -- 1. Setup seed user rows
    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
    VALUES (v_uid, v_uid, 'patient', 'pat_f_01', 'Patient F', 'pf@test.invalid', '9811122233')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
    VALUES (v_doc_uid, v_doc_uid, 'doctor', 'doc_f_01', 'Doctor F', 'df@test.invalid', '9811122244')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile)
    VALUES (v_store_uid, v_store_uid, 'medicalStore', 'store_f_01', 'Store Owner F', 'sf@test.invalid', '9811122255')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.doctors (doctor_id, owner_uid, name, specialization, mobile, email, qualification)
    VALUES ('doc_f_01', v_doc_uid, 'Doctor F', 'General Medicine', '9811122244', 'df@test.invalid', 'MBBS')
    ON CONFLICT (doctor_id) DO NOTHING;

    INSERT INTO public.patients (patient_id, owner_uid, name, mobile)
    VALUES ('pat_f_01', v_uid, 'Patient F', '9811122233')
    ON CONFLICT (patient_id) DO NOTHING;

    INSERT INTO public.medical_stores (store_id, owner_uid, store_name, owner_name, drug_license_number, phone, email)
    VALUES ('store_f_01', v_store_uid, 'Store F', 'Store Owner', 'DL-F-12345', '9811122255', 'sf@test.invalid')
    ON CONFLICT (store_id) DO NOTHING;

    INSERT INTO public.appointments (
        appointment_id, patient_id, doctor_id, booked_by_uid, doctor_name, specialization,
        patient_name, patient_age, patient_gender, date_time, slot_label, visit_type,
        patient_status, doctor_status, token_number
    ) VALUES (
        'appt_f_01', 'pat_f_01', 'doc_f_01', v_uid, 'Doctor F', 'General Medicine',
        'Patient F', 32, 'male', '2026-11-01 10:00:00+05:30', '10:00 AM', 'newVisit',
        'confirmed', 'pendingRequest', 1
    ) ON CONFLICT (appointment_id) DO NOTHING;

    -- TEST 1: register_device_token RPC
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    PERFORM public.register_device_token('android', 'fcm_test_token_f_01');

    IF EXISTS (SELECT 1 FROM public.user_devices WHERE user_id = v_uid AND fcm_token = 'fcm_test_token_f_01') THEN
        INSERT INTO phase_f_results VALUES (1, 'register_device_token RPC inserts device', 'EXISTS', 'EXISTS', 'PASS');
    ELSE
        INSERT INTO phase_f_results VALUES (1, 'register_device_token RPC inserts device', 'EXISTS', 'NOT FOUND', 'FAIL');
    END IF;

    -- TEST 2: user_devices RLS owner delete
    DELETE FROM public.user_devices WHERE user_id = v_uid AND platform = 'android';
    IF NOT EXISTS (SELECT 1 FROM public.user_devices WHERE user_id = v_uid) THEN
        INSERT INTO phase_f_results VALUES (2, 'user_devices owner delete permitted by RLS', '0', '0', 'PASS');
    ELSE
        INSERT INTO phase_f_results VALUES (2, 'user_devices owner delete permitted by RLS', '0', 'ROWS REMAIN', 'FAIL');
    END IF;

    -- TEST 3: system_config public read
    IF EXISTS (SELECT 1 FROM public.system_config WHERE config_key = 'promoted_ads') THEN
        INSERT INTO phase_f_results VALUES (3, 'system_config promoted_ads exists and readable', 'EXISTS', 'EXISTS', 'PASS');
    ELSE
        INSERT INTO phase_f_results VALUES (3, 'system_config promoted_ads exists and readable', 'EXISTS', 'NOT FOUND', 'FAIL');
    END IF;

    -- TEST 4: reschedule_appointment_atomic RPC succeeds and updates token/slot
    v_appt_res := public.reschedule_appointment_atomic(
        'appt_f_01',
        'doc_f_01',
        '2026-11-02'::date,
        '11:00 AM',
        'patient',
        'Patient requested time change'
    );

    IF (v_appt_res ->> 'ok')::boolean = TRUE AND (v_appt_res ->> 'slot_label') = '11:00 AM' THEN
        INSERT INTO phase_f_results VALUES (4, 'reschedule_appointment_atomic updates appointment', '11:00 AM', v_appt_res ->> 'slot_label', 'PASS');
    ELSE
        INSERT INTO phase_f_results VALUES (4, 'reschedule_appointment_atomic updates appointment', '11:00 AM', v_appt_res::text, 'FAIL');
    END IF;

    -- TEST 5: Verify dropped functions do not exist in pg_proc
    SELECT COUNT(*) INTO v_fn_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE proname IN ('on_auth_user_created', 'find_auth_user', 'consume_otp_attempt', 'check_and_increment_rate_limit');

    IF v_fn_count = 0 THEN
        INSERT INTO phase_f_results VALUES (5, 'Dropped functions absent from pg_proc', '0', '0', 'PASS');
    ELSE
        INSERT INTO phase_f_results VALUES (5, 'Dropped functions absent from pg_proc', '0', v_fn_count::text, 'FAIL');
    END IF;
END $$;

SELECT test_id, description, expected, actual, status FROM phase_f_results ORDER BY test_id;
