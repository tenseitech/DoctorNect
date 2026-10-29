-- DoctorNect Migration: 20261029000001_guard_and_drift_fixes.sql
-- Description: Guard bypass fixes, multi-table trigger JSONB safety, doctor verification check in prescription RPC, promoted_ads drift fix, anon catalog grants, and ambulance contact authenticated grant.

-- ============================================================================
-- 1. DRIFT FIX: promoted_ads image_storage_provider column & backfill
-- ============================================================================
ALTER TABLE public.promoted_ads ADD COLUMN IF NOT EXISTS image_storage_provider VARCHAR(32) DEFAULT 's3';
UPDATE public.promoted_ads
SET image_storage_provider = COALESCE(image_storage, 's3')
WHERE image_storage_provider IS NULL;

-- ============================================================================
-- 2. ANONYMOUS ACCESS: lab_catalog_tests grant & policy
-- ============================================================================
GRANT SELECT ON public.lab_catalog_tests TO anon;
DROP POLICY IF EXISTS "lab_catalog_tests_select" ON public.lab_catalog_tests;
CREATE POLICY "lab_catalog_tests_select" ON public.lab_catalog_tests
    FOR SELECT TO anon, authenticated
    USING (TRUE);

-- ============================================================================
-- 3. AMBULANCE TRIP CONTACT: Grant authenticated caller access
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_contact(VARCHAR) TO authenticated, service_role;

-- ============================================================================
-- 4. GUARD BYPASS FIX: private.trg_users_guard_insert()
-- Note: NEVER use current_user inside a SECURITY DEFINER function because it
-- evaluates to 'postgres' (function owner), bypassing checks for authenticated callers.
-- No bypass on current_firebase_uid() IS NULL.
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_users_guard_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_caller_sub TEXT;
BEGIN
    -- Privileged session bypass: only service_role, super_admin, or direct backend/migration session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    -- Non-admin inserting self cannot claim administrative roles
    IF NEW.role IN ('super_admin', 'superAdmin', 'admin', 'hospital_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN: Cannot register with administrative role' USING ERRCODE = '42501';
    END IF;

    -- Only allowed client roles permitted for self-registration
    IF NEW.role NOT IN ('patient', 'doctor', 'medicalStore', 'lab', 'ambulance') THEN
        RAISE EXCEPTION 'FORBIDDEN: Invalid registration role "%"', NEW.role USING ERRCODE = '42501';
    END IF;

    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    -- Ensure ID matches caller token
    IF NEW.id IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: User ID must match authenticated token subject' USING ERRCODE = '42501';
    END IF;

    -- Ensure firebase_uid matches caller token if provided
    IF NEW.firebase_uid IS NOT NULL AND NEW.firebase_uid IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: firebase_uid must match authenticated token subject' USING ERRCODE = '42501';
    END IF;

    -- Only patients may self-verify upon registration; domain roles require admin verification
    IF NEW.role <> 'patient' AND NEW.verified IS TRUE THEN
        RAISE EXCEPTION 'FORBIDDEN: Domain role accounts cannot self-verify' USING ERRCODE = '42501';
    END IF;

    -- Default profile_id to user id if omitted
    IF NEW.profile_id IS NULL OR trim(NEW.profile_id) = '' THEN
        NEW.profile_id := NEW.id;
    END IF;

    -- Cannot claim a profile_id already claimed by another user
    IF EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.profile_id = NEW.profile_id
          AND u.id <> NEW.id
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN: Profile ID is already in use by another user' USING ERRCODE = '42501';
    END IF;

    -- Cannot claim a profile_id that exists as primary key in domain tables owned by someone else
    IF EXISTS (
        SELECT 1 FROM (
            SELECT patient_id AS pid, owner_uid AS owner FROM public.patients
            UNION ALL
            SELECT doctor_id AS pid, owner_uid AS owner FROM public.doctors
            UNION ALL
            SELECT store_id AS pid, owner_uid AS owner FROM public.medical_stores
            UNION ALL
            SELECT lab_id AS pid, owner_uid AS owner FROM public.labs
            UNION ALL
            SELECT ambulance_id AS pid, auth_uid AS owner FROM public.ambulances
        ) domain_pks
        WHERE domain_pks.pid = NEW.profile_id
          AND domain_pks.owner IS DISTINCT FROM v_caller_sub
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN: Profile ID is already claimed by another entity' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_users_guard_insert ON public.users;
CREATE TRIGGER trg_users_guard_insert
    BEFORE INSERT ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_users_guard_insert();

REVOKE ALL ON FUNCTION private.trg_users_guard_insert() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.trg_users_guard_insert() TO service_role;

-- ============================================================================
-- 5. GUARD BYPASS & PLPGSQL_CHECK FIX: private.trg_domain_profile_guard_insert()
-- Uses to_jsonb(NEW) to avoid static table-specific record field dependencies,
-- allowing plpgsql_check to cleanly validate against all 5 domain tables.
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_domain_profile_guard_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_data JSONB := to_jsonb(NEW);
    v_caller_sub TEXT;
    v_user_profile_id TEXT;
    v_pk_val TEXT;
    v_owner_val TEXT;
BEGIN
    -- Privileged session bypass: only service_role, super_admin, or direct backend/migration session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    IF TG_TABLE_NAME = 'patients' THEN
        v_pk_val := v_data ->> 'patient_id';
        v_owner_val := v_data ->> 'owner_uid';
    ELSIF TG_TABLE_NAME = 'doctors' THEN
        v_pk_val := v_data ->> 'doctor_id';
        v_owner_val := v_data ->> 'owner_uid';
    ELSIF TG_TABLE_NAME = 'medical_stores' THEN
        v_pk_val := v_data ->> 'store_id';
        v_owner_val := v_data ->> 'owner_uid';
    ELSIF TG_TABLE_NAME = 'labs' THEN
        v_pk_val := v_data ->> 'lab_id';
        v_owner_val := v_data ->> 'owner_uid';
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        v_pk_val := v_data ->> 'ambulance_id';
        v_owner_val := v_data ->> 'auth_uid';
    ELSE
        RETURN NEW;
    END IF;

    -- Owner must match caller token subject
    IF v_owner_val IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: Domain profile owner must match authenticated token subject'
            USING ERRCODE = '42501';
    END IF;

    -- Caller must have an existing users row
    SELECT u.profile_id INTO v_user_profile_id
    FROM public.users u
    WHERE u.id = v_caller_sub;

    IF v_user_profile_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN: User record must exist before inserting domain profile'
            USING ERRCODE = '42501';
    END IF;

    IF TG_TABLE_NAME = 'patients' THEN
        -- Allowed: either primary profile (v_pk_val = v_user_profile_id)
        -- or secondary family member profile owned by the caller (v_owner_val = v_caller_sub, verified above)
        NULL;
    ELSE
        IF v_pk_val IS DISTINCT FROM v_user_profile_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Domain profile ID must match user profile_id in public.users'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_patients_guard_insert ON public.patients;
CREATE TRIGGER trg_patients_guard_insert
    BEFORE INSERT ON public.patients
    FOR EACH ROW EXECUTE FUNCTION private.trg_domain_profile_guard_insert();

DROP TRIGGER IF EXISTS trg_doctors_guard_insert ON public.doctors;
CREATE TRIGGER trg_doctors_guard_insert
    BEFORE INSERT ON public.doctors
    FOR EACH ROW EXECUTE FUNCTION private.trg_domain_profile_guard_insert();

DROP TRIGGER IF EXISTS trg_medical_stores_guard_insert ON public.medical_stores;
CREATE TRIGGER trg_medical_stores_guard_insert
    BEFORE INSERT ON public.medical_stores
    FOR EACH ROW EXECUTE FUNCTION private.trg_domain_profile_guard_insert();

DROP TRIGGER IF EXISTS trg_labs_guard_insert ON public.labs;
CREATE TRIGGER trg_labs_guard_insert
    BEFORE INSERT ON public.labs
    FOR EACH ROW EXECUTE FUNCTION private.trg_domain_profile_guard_insert();

DROP TRIGGER IF EXISTS trg_ambulances_guard_insert ON public.ambulances;
CREATE TRIGGER trg_ambulances_guard_insert
    BEFORE INSERT ON public.ambulances
    FOR EACH ROW EXECUTE FUNCTION private.trg_domain_profile_guard_insert();

REVOKE ALL ON FUNCTION private.trg_domain_profile_guard_insert() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.trg_domain_profile_guard_insert() TO service_role;

-- ============================================================================
-- 6. DOCTOR VERIFICATION ENFORCEMENT: public.create_prescription_atomic(JSONB)
-- Enforces doctors.verified IS TRUE for non-admin callers.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_prescription_atomic(
    payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_doctor_id TEXT;
    v_doc_verified BOOLEAN;
    v_prescription_id TEXT;
    v_patient_id TEXT;
    v_appointment_id TEXT;
    v_appt_doctor_id TEXT;
    v_appt_patient_id TEXT;
    v_existing_doc_id TEXT;
    v_is_admin BOOLEAN;
    v_med JSONB;
    v_inv JSONB;
    v_ref JSONB;
BEGIN
    -- 1. Derive & verify caller
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt()->>'sub',
        auth.jwt()->>'uid',
        current_setting('request.jwt.claims', true)::jsonb->>'sub'
    ), '');

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to create prescription.'
            USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.'
            USING ERRCODE = '42501';
    END IF;

    -- Resolve doctor_id and verification status for caller
    SELECT doctor_id, verified INTO v_doctor_id, v_doc_verified 
    FROM public.doctors 
    WHERE owner_uid = v_caller_uid OR (v_profile_id IS NOT NULL AND doctor_id = v_profile_id);

    IF v_doctor_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller "%" is not a registered doctor.', v_caller_uid
            USING ERRCODE = '42501';
    END IF;

    -- Enforce doctor verification for non-admin
    IF NOT v_is_admin AND v_doc_verified IS NOT TRUE THEN
        RAISE EXCEPTION 'FORBIDDEN: Doctor "%" is not verified to create prescriptions.', v_doctor_id
            USING ERRCODE = '42501';
    END IF;

    IF v_is_admin AND v_doctor_id IS NULL THEN
        v_doctor_id := trim(payload->>'doctor_id');
    END IF;

    v_prescription_id := trim(payload->>'prescription_id');
    v_patient_id := trim(payload->>'patient_id');
    v_appointment_id := trim(payload->>'appointment_id');

    IF v_prescription_id IS NULL OR v_prescription_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: prescription_id is required.'
            USING ERRCODE = '22004';
    END IF;

    IF v_patient_id IS NULL OR v_patient_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: patient_id is required.'
            USING ERRCODE = '22004';
    END IF;

    -- Require relationship: for non-admin require an appointment or an active patient_doctor_links row for patient_id
    IF NOT v_is_admin THEN
        IF NOT (
            EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.doctor_id = v_doctor_id
                  AND a.patient_id = v_patient_id
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.doctor_id = v_doctor_id
                  AND pdl.patient_id = v_patient_id
            )
        ) THEN
            RAISE EXCEPTION 'FORBIDDEN: Doctor "%" does not have an active appointment or link for patient "%".', v_doctor_id, v_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Verify prescription ownership if prescription already exists
    SELECT doctor_id INTO v_existing_doc_id 
    FROM public.prescriptions 
    WHERE prescription_id = v_prescription_id;

    IF v_existing_doc_id IS NOT NULL AND NOT v_is_admin AND (v_existing_doc_id IS DISTINCT FROM v_doctor_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Cannot overwrite prescription belonging to another doctor.'
            USING ERRCODE = '42501';
    END IF;

    -- 3. Verify appointment ownership and patient consistency if appointment_id is provided
    IF v_appointment_id IS NOT NULL AND v_appointment_id != '' THEN
        SELECT doctor_id, patient_id INTO v_appt_doctor_id, v_appt_patient_id
        FROM public.appointments
        WHERE appointment_id = v_appointment_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'NOT_FOUND: Referenced appointment "%" does not exist.', v_appointment_id
                USING ERRCODE = '23503';
        END IF;

        IF NOT v_is_admin AND (v_appt_doctor_id IS DISTINCT FROM v_doctor_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Doctor "%" does not own appointment "%".', v_doctor_id, v_appointment_id
                USING ERRCODE = '42501';
        END IF;

        IF NOT v_is_admin AND (v_appt_patient_id IS DISTINCT FROM v_patient_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Appointment "%" is for patient "%", not "%".', v_appointment_id, v_appt_patient_id, v_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 4. Upsert prescription header
    INSERT INTO public.prescriptions (
        prescription_id,
        doctor_id,
        patient_id,
        appointment_id,
        doctor_name,
        doctor_specialization,
        doctor_qualifications,
        doctor_reg_number,
        clinic_name,
        clinic_address,
        doctor_phone,
        patient_name,
        patient_age,
        patient_gender,
        prescription_date,
        diagnosis_type,
        primary_diagnosis,
        secondary_diagnosis,
        chief_complaint,
        symptoms,
        symptom_duration,
        past_history,
        allergies,
        general_examination,
        blood_pressure,
        temperature,
        pulse,
        spo2,
        weight_kg,
        height_cm,
        respiratory_rate,
        diet_advice,
        activity_restrictions,
        lifestyle_advice,
        general_advice,
        follow_up_note,
        next_visit,
        created_at,
        updated_at
    ) VALUES (
        v_prescription_id,
        v_doctor_id,
        v_patient_id,
        v_appointment_id,
        COALESCE(payload->>'doctor_name', 'Doctor'),
        payload->>'doctor_specialization',
        payload->>'doctor_qualifications',
        payload->>'doctor_reg_number',
        payload->>'clinic_name',
        payload->>'clinic_address',
        payload->>'doctor_phone',
        COALESCE(payload->>'patient_name', 'Patient'),
        (payload->>'patient_age')::INT,
        payload->>'patient_gender',
        COALESCE((payload->>'prescription_date')::TIMESTAMPTZ, CURRENT_TIMESTAMP),
        COALESCE(payload->>'diagnosis_type', 'Provisional'),
        COALESCE(payload->>'primary_diagnosis', ''),
        payload->>'secondary_diagnosis',
        payload->>'chief_complaint',
        COALESCE(payload->>'symptoms', ''),
        payload->>'symptom_duration',
        payload->>'past_history',
        payload->>'allergies',
        payload->>'general_examination',
        payload->>'blood_pressure',
        payload->>'temperature',
        payload->>'pulse',
        payload->>'spo2',
        payload->>'weight_kg',
        payload->>'height_cm',
        payload->>'respiratory_rate',
        payload->>'diet_advice',
        payload->>'activity_restrictions',
        payload->>'lifestyle_advice',
        payload->>'general_advice',
        payload->>'follow_up_note',
        (payload->>'next_visit')::TIMESTAMPTZ,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (prescription_id) DO UPDATE SET
        appointment_id = EXCLUDED.appointment_id,
        doctor_name = EXCLUDED.doctor_name,
        doctor_specialization = EXCLUDED.doctor_specialization,
        doctor_qualifications = EXCLUDED.doctor_qualifications,
        doctor_reg_number = EXCLUDED.doctor_reg_number,
        clinic_name = EXCLUDED.clinic_name,
        clinic_address = EXCLUDED.clinic_address,
        doctor_phone = EXCLUDED.doctor_phone,
        patient_name = EXCLUDED.patient_name,
        patient_age = EXCLUDED.patient_age,
        patient_gender = EXCLUDED.patient_gender,
        prescription_date = EXCLUDED.prescription_date,
        diagnosis_type = EXCLUDED.diagnosis_type,
        primary_diagnosis = EXCLUDED.primary_diagnosis,
        secondary_diagnosis = EXCLUDED.secondary_diagnosis,
        chief_complaint = EXCLUDED.chief_complaint,
        symptoms = EXCLUDED.symptoms,
        symptom_duration = EXCLUDED.symptom_duration,
        past_history = EXCLUDED.past_history,
        allergies = EXCLUDED.allergies,
        general_examination = EXCLUDED.general_examination,
        blood_pressure = EXCLUDED.blood_pressure,
        temperature = EXCLUDED.temperature,
        pulse = EXCLUDED.pulse,
        spo2 = EXCLUDED.spo2,
        weight_kg = EXCLUDED.weight_kg,
        height_cm = EXCLUDED.height_cm,
        respiratory_rate = EXCLUDED.respiratory_rate,
        diet_advice = EXCLUDED.diet_advice,
        activity_restrictions = EXCLUDED.activity_restrictions,
        lifestyle_advice = EXCLUDED.lifestyle_advice,
        general_advice = EXCLUDED.general_advice,
        follow_up_note = EXCLUDED.follow_up_note,
        next_visit = EXCLUDED.next_visit,
        updated_at = CURRENT_TIMESTAMP;

    -- 5. Replace medicines atomically
    DELETE FROM public.prescription_medicines WHERE prescription_id = v_prescription_id;
    IF payload ? 'medicines' AND jsonb_array_length(payload->'medicines') > 0 THEN
        FOR v_med IN SELECT * FROM jsonb_array_elements(payload->'medicines') LOOP
            INSERT INTO public.prescription_medicines (
                prescription_id,
                medicine_entry_id,
                name,
                dosage,
                form,
                frequency,
                quantity,
                duration,
                instructions,
                special_instructions,
                is_sos,
                substitute_allowed
            ) VALUES (
                v_prescription_id,
                COALESCE(v_med->>'medicine_entry_id', v_prescription_id || '_' || md5(v_med->>'name')),
                COALESCE(v_med->>'name', ''),
                v_med->>'dosage',
                v_med->>'form',
                v_med->>'frequency',
                (v_med->>'quantity')::INT,
                v_med->>'duration',
                v_med->>'instructions',
                v_med->>'special_instructions',
                COALESCE((v_med->>'is_sos')::BOOLEAN, FALSE),
                COALESCE((v_med->>'substitute_allowed')::BOOLEAN, FALSE)
            );
        END LOOP;
    END IF;

    -- 6. Replace investigations atomically
    DELETE FROM public.prescription_investigations WHERE prescription_id = v_prescription_id;
    IF payload ? 'investigations' AND jsonb_array_length(payload->'investigations') > 0 THEN
        FOR v_inv IN SELECT * FROM jsonb_array_elements(payload->'investigations') LOOP
            INSERT INTO public.prescription_investigations (
                prescription_id,
                name,
                type,
                group_name,
                notes
            ) VALUES (
                v_prescription_id,
                COALESCE(v_inv->>'name', ''),
                COALESCE(v_inv->>'type', 'radiology'),
                v_inv->>'group_name',
                v_inv->>'notes'
            );
        END LOOP;
    END IF;

    -- 7. Replace referral links atomically
    DELETE FROM public.prescription_referrals WHERE prescription_id = v_prescription_id;
    IF payload ? 'referrals' AND jsonb_array_length(payload->'referrals') > 0 THEN
        FOR v_ref IN SELECT * FROM jsonb_array_elements(payload->'referrals') LOOP
            INSERT INTO public.prescription_referrals (
                prescription_id,
                to_doctor_id,
                doctor_name,
                specialization,
                reason
            ) VALUES (
                v_prescription_id,
                v_ref->>'to_doctor_id',
                COALESCE(v_ref->>'doctor_name', v_ref->>'to_doctor_name', ''),
                COALESCE(v_ref->>'specialization', v_ref->>'specialty', ''),
                COALESCE(v_ref->>'reason', v_ref->>'notes')
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'prescription_id', v_prescription_id,
        'doctor_id', v_doctor_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_prescription_atomic(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_prescription_atomic(JSONB) TO authenticated, service_role;
