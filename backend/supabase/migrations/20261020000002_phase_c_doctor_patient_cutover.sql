-- ============================================================================
-- Migration: 20261020000002_phase_c_doctor_patient_cutover.sql
-- Description: Phase C Doctor & Patient Cutover
--   1. Realtime publication registration (safe tables only, replica identity full)
--   2. Public doctor directory view (safe columns only) & directory update signal
--   3. Hardened column immutability locks with aggregate sync bypass
--   4. Atomic prescription creation RPC (create_prescription_atomic with ownership validation)
--   5. Hardened book_appointment_atomic (derives patient_id from auth.jwt()->>'sub',
--      slot advisory locking, idempotency check)
--   6. Native Postgres triggers for doctor review rating aggregation & review_public sync
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DIRECTORY CHANGE SIGNAL TABLE & REALTIME PUBLICATION REGISTRATION
-- ----------------------------------------------------------------------------
-- Base tables with sensitive data (phone, email, FCM token, license) like `doctors`
-- and `patients` are NEVER exposed directly in the Supabase Realtime publication.
-- Instead, safe tables and change signal tables are registered.

CREATE TABLE IF NOT EXISTS public.doctor_directory_updates (
    id TEXT PRIMARY KEY DEFAULT 'directory',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
DROP POLICY IF EXISTS "doctor_directory_updates_select" ON public.doctor_directory_updates;
CREATE POLICY "doctor_directory_updates_select" ON public.doctor_directory_updates FOR SELECT TO authenticated USING (TRUE);
REVOKE ALL ON public.doctor_directory_updates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.doctor_directory_updates TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_touch_doctor_directory()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Only touch directory updates if the doctor is (or was) verified and active, or transitioning verified/active state
    IF (TG_OP = 'DELETE' AND OLD.verified = TRUE AND OLD.deactivated = FALSE)
       OR (TG_OP = 'INSERT' AND NEW.verified = TRUE AND NEW.deactivated = FALSE)
       OR (TG_OP = 'UPDATE' AND (
           (NEW.verified = TRUE AND NEW.deactivated = FALSE)
           OR (OLD.verified = TRUE AND OLD.deactivated = FALSE)
       )) THEN
        INSERT INTO public.doctor_directory_updates (id, updated_at)
        VALUES ('directory', CURRENT_TIMESTAMP)
        ON CONFLICT (id) DO UPDATE SET updated_at = EXCLUDED.updated_at;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_doctor_directory ON public.doctors;
CREATE TRIGGER trg_touch_doctor_directory
    AFTER INSERT OR UPDATE OR DELETE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_touch_doctor_directory();

-- Register publication for safe realtime tables
DO $$
DECLARE
    t TEXT;
    target_tables TEXT[] := ARRAY[
        'appointments',
        'doctor_availability',
        'doctor_blocked_dates',
        'family_members',
        'health_records',
        'prescriptions',
        'prescription_medicines',
        'prescription_investigations',
        'prescription_referrals',
        'referrals',
        'reviews',
        'review_public',
        'doctor_directory_updates'
    ];
BEGIN
    FOREACH t IN ARRAY target_tables LOOP
        IF EXISTS (
            SELECT 1 FROM pg_tables
            WHERE schemaname = 'public' AND tablename = t
        ) THEN
            BEGIN
                EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
            EXCEPTION
                WHEN duplicate_object THEN
                    NULL;
            END;
        END IF;
    END LOOP;
END $$;

-- Enforce REPLICA IDENTITY FULL so DELETE CDC payloads carry previous row state
ALTER TABLE public.appointments REPLICA IDENTITY FULL;
ALTER TABLE public.prescriptions REPLICA IDENTITY FULL;
ALTER TABLE public.reviews REPLICA IDENTITY FULL;
ALTER TABLE public.referrals REPLICA IDENTITY FULL;
ALTER TABLE public.review_public REPLICA IDENTITY FULL;
ALTER TABLE public.doctor_directory_updates REPLICA IDENTITY FULL;

-- ----------------------------------------------------------------------------
-- 2. PUBLIC DOCTOR DIRECTORY (SAFE COLUMNS ONLY)
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- 2. DOCTOR DIRECTORY PROJECTION FIREWALL & DOCTORS TABLE RLS
-- ----------------------------------------------------------------------------
-- SECURITY ARCHITECTURE:
-- 1. Base table `public.doctors` contains sensitive PII & credentials:
--    mobile, email, state_council, council_number, fcm_token.
--    Direct SELECT on `public.doctors` is restricted to:
--    - Owner doctor (owner_uid = auth.jwt()->>'sub' OR doctor_id = private.current_profile_id())
--    - Platform Super Admin (private.is_super_admin())
--    - Patients who have a booked/confirmed appointment with this doctor
--    - Other doctors with an active clinical referral or care link
-- 2. `public.doctor_directory` is restored as a SECURITY DEFINER-style view
--    (security_invoker = false, owned by db owner) with strict column filtering.
--    It projects ONLY safe discovery columns (name, specialization, clinic, rating, etc.)
--    and hardcodes WHERE verified = TRUE AND deactivated = FALSE.
--    Authenticated users query this view for doctor directory discovery.
-- 3. Supabase Security Advisor Accepted Exception:
--    View public.doctor_directory intentionally runs with security_invoker = false (definer view)
--    so authenticated clients can search and read verified doctor profiles without requiring direct
--    SELECT privileges on sensitive clinical columns (mobile, email, state_council, council_number, fcm_token)
--    in the underlying public.doctors table. The view query strictly filters by verified=true AND deactivated=false.

ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_s3_key TEXT;
ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_s3_bucket TEXT;
ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_storage_provider VARCHAR(32) DEFAULT 's3';

DROP POLICY IF EXISTS doctors_select ON public.doctors;
CREATE POLICY doctors_select ON public.doctors
    FOR SELECT TO authenticated
    USING (
        -- 1. Doctor themselves (owner)
        (owner_uid = (auth.jwt() ->> 'sub'))
        OR (doctor_id = private.current_profile_id())
        -- 2. Platform Admin
        OR private.is_super_admin()
        -- 3. Patient with an appointment with this doctor
        OR EXISTS (
            SELECT 1 FROM public.appointments a
            WHERE a.doctor_id = doctors.doctor_id
              AND a.patient_id = private.current_profile_id()
        )
        -- 4. Another doctor with clinical care relationship (referral or shared link)
        OR EXISTS (
            SELECT 1 FROM public.patient_doctor_links pdl
            WHERE pdl.doctor_id = doctors.doctor_id
              AND pdl.patient_id = private.current_profile_id()
        )
        OR EXISTS (
            SELECT 1 FROM public.referrals dr
            WHERE (dr.from_doctor_id = private.current_profile_id() AND dr.to_doctor_id = doctors.doctor_id)
               OR (dr.to_doctor_id = private.current_profile_id() AND dr.from_doctor_id = doctors.doctor_id)
        )
    );

DROP POLICY IF EXISTS "doctors_update" ON public.doctors;
CREATE POLICY "doctors_update" ON public.doctors
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub') OR doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR doctor_id = private.current_profile_id() OR private.is_super_admin());

-- Restore doctor_directory as SECURITY DEFINER-style view (security_invoker = false)
DROP VIEW IF EXISTS public.doctor_directory;
CREATE VIEW public.doctor_directory 
WITH (security_invoker = false)
AS
SELECT
    doctor_id,
    name,
    specialization,
    super_specialization,
    qualification,
    experience_years,
    consultation_fee,
    clinic_name,
    area,
    city,
    state,
    country,
    pincode,
    address_line1,
    address_line2,
    about,
    languages,
    photo_url,
    photo_s3_key,
    rating,
    review_count,
    verified,
    profile_completed
FROM public.doctors
WHERE verified = TRUE AND deactivated = FALSE;

ALTER VIEW public.doctor_directory OWNER TO postgres;

REVOKE ALL ON public.doctor_directory FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.doctor_directory TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2b. STORAGE AUDIT LOGS (PostgreSQL table for server-side audit logs)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.storage_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    who TEXT NOT NULL,
    role TEXT NOT NULL,
    what TEXT NOT NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'success',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

ALTER TABLE public.storage_audit_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.storage_audit_logs FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.storage_audit_logs TO service_role;
GRANT SELECT ON public.storage_audit_logs TO authenticated;

DROP POLICY IF EXISTS "storage_audit_logs_admin_read" ON public.storage_audit_logs;
CREATE POLICY "storage_audit_logs_admin_read" ON public.storage_audit_logs
    FOR SELECT TO authenticated
    USING (private.is_super_admin());

ALTER TABLE IF EXISTS public.health_records ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT;
ALTER TABLE IF EXISTS public.health_records ADD COLUMN IF NOT EXISTS mime_type VARCHAR(128);
ALTER TABLE IF EXISTS public.health_records ADD COLUMN IF NOT EXISTS upload_confirmed_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS public.lab_bookings ADD COLUMN IF NOT EXISTS report_s3_key TEXT;
ALTER TABLE IF EXISTS public.lab_bookings ADD COLUMN IF NOT EXISTS report_s3_bucket TEXT;
ALTER TABLE IF EXISTS public.lab_bookings ADD COLUMN IF NOT EXISTS report_file_size_bytes BIGINT;
ALTER TABLE IF EXISTS public.lab_bookings ADD COLUMN IF NOT EXISTS report_mime_type VARCHAR(128);
ALTER TABLE IF EXISTS public.lab_bookings ADD COLUMN IF NOT EXISTS report_uploaded_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS public.patients ADD COLUMN IF NOT EXISTS photo_updated_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_updated_at TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- 3. COLUMN IMMUTABILITY LOCKS WITH AGGREGATE TRIGGER BYPASS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.lock_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_col TEXT;
    v_old_val TEXT;
    v_new_val TEXT;
    v_is_admin BOOLEAN := COALESCE(private.is_super_admin(), FALSE);
    v_is_aggregate_sync BOOLEAN := (current_setting('doctornect.internal_aggregate_sync', true) = 'on');
BEGIN
    IF v_is_admin OR private.current_firebase_uid() IS NULL THEN
        RETURN NEW;
    END IF;

    FOR i IN 0 .. (TG_NARGS - 1) LOOP
        v_col := TG_ARGV[i];

        -- Allow internal aggregate sync to update rating and review_count
        IF v_is_aggregate_sync AND v_col IN ('rating', 'review_count', 'total_rating', 'rating_count') THEN
            CONTINUE;
        END IF;

        v_old_val := to_jsonb(OLD) ->> v_col;
        v_new_val := to_jsonb(NEW) ->> v_col;

        IF v_new_val IS DISTINCT FROM v_old_val THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (Current: %, Requested: %)',
                v_col, TG_TABLE_NAME, v_old_val, v_new_val
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_lock_role ON public.users;
CREATE TRIGGER trg_users_lock_role
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('role');

DROP TRIGGER IF EXISTS trg_doctors_lock_verification ON public.doctors;
CREATE TRIGGER trg_doctors_lock_verification
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'owner_uid');

DROP TRIGGER IF EXISTS trg_patients_lock_verification ON public.patients;
CREATE TRIGGER trg_patients_lock_verification
    BEFORE UPDATE ON public.patients
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('owner_uid', 'verified');

-- ----------------------------------------------------------------------------
-- 4. ATOMIC PRESCRIPTION CREATION RPC (create_prescription_atomic)
-- ----------------------------------------------------------------------------
-- Enforces:
-- 1. Caller must be an authenticated doctor.
-- 2. Prescription ownership: Doctor A cannot overwrite Doctor B's prescription.
-- 3. Appointment ownership: Referenced appointment must belong to this doctor and patient.
-- 4. SET search_path = '' for security definer hardening.

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
    v_doctor_id TEXT;
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
        current_setting('request.jwt.claims', true)::jsonb->>'sub'
    ), '');

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to create prescription.'
            USING ERRCODE = '42501';
    END IF;

    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- Resolve doctor_id for caller
    SELECT doctor_id INTO v_doctor_id 
    FROM public.doctors 
    WHERE owner_uid = v_caller_uid OR doctor_id = v_caller_uid
    LIMIT 1;

    IF v_doctor_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller "%" is not a registered doctor.', v_caller_uid
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

    -- 2. Verify prescription ownership if prescription already exists
    SELECT doctor_id INTO v_existing_doc_id 
    FROM public.prescriptions 
    WHERE prescription_id = v_prescription_id;

    IF v_existing_doc_id IS NOT NULL AND NOT v_is_admin AND v_existing_doc_id != v_doctor_id THEN
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

        IF NOT v_is_admin AND v_appt_doctor_id != v_doctor_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Doctor "%" does not own appointment "%".', v_doctor_id, v_appointment_id
                USING ERRCODE = '42501';
        END IF;

        IF NOT v_is_admin AND v_appt_patient_id != v_patient_id THEN
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
                to_doctor_name,
                specialty,
                notes
            ) VALUES (
                v_prescription_id,
                v_ref->>'to_doctor_id',
                v_ref->>'to_doctor_name',
                v_ref->>'specialty',
                v_ref->>'notes'
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
GRANT EXECUTE ON FUNCTION public.create_prescription_atomic(JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. ATOMIC APPOINTMENT BOOKING (book_appointment_atomic)
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR);
DROP FUNCTION IF EXISTS public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR);
DROP FUNCTION IF EXISTS public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_doctor_name VARCHAR(255),
    p_specialization VARCHAR(128),
    p_patient_name VARCHAR(255),
    p_patient_age INTEGER,
    p_patient_gender VARCHAR(16),
    p_date_time TIMESTAMPTZ,
    p_slot_label VARCHAR(64),
    p_visit_type VARCHAR(32) DEFAULT 'newVisit',
    p_token_number INTEGER DEFAULT NULL,
    p_clinic_name VARCHAR(255) DEFAULT NULL,
    p_clinic_address TEXT DEFAULT NULL,
    p_sync_origin VARCHAR(32) DEFAULT 'patient_supabase',
    p_patient_id VARCHAR(64) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_caller_patient_id TEXT;
    v_patient_id TEXT;
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Strictly derive caller UID from auth.jwt()->>'sub'
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt()->>'sub',
        current_setting('request.jwt.claims', true)::jsonb->>'sub'
    ), '');

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to book an appointment.'
            USING ERRCODE = '42501';
    END IF;

    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- Resolve caller's own patient profile_id
    SELECT profile_id INTO v_caller_patient_id
    FROM public.users
    WHERE id = v_caller_uid
    LIMIT 1;

    IF v_caller_patient_id IS NULL THEN
        v_caller_patient_id := v_caller_uid;
    END IF;

    -- Verify patient ownership: caller can only book for themselves or their owned family members
    IF p_patient_id IS NOT NULL AND trim(p_patient_id) != '' THEN
        v_patient_id := trim(p_patient_id);
        IF NOT v_is_admin AND v_patient_id != v_caller_patient_id THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.patients WHERE patient_id = v_patient_id AND owner_uid = v_caller_uid
            ) AND NOT EXISTS (
                SELECT 1 FROM public.family_members WHERE member_id = v_patient_id AND patient_id = v_caller_patient_id
            ) THEN
                RAISE EXCEPTION 'FORBIDDEN: Callers may only book appointments for their own patient profile.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    ELSE
        v_patient_id := v_caller_patient_id;
    END IF;

    -- Validate required parameters
    IF p_appointment_id IS NULL OR p_doctor_id IS NULL OR p_date_time IS NULL THEN
        RAISE EXCEPTION 'BAD_REQUEST: appointment_id, doctor_id, and date_time cannot be null.'
            USING ERRCODE = '22004';
    END IF;

    -- 1. Idempotency Check: If appointment_id already booked, return it directly
    SELECT * INTO v_appointment FROM public.appointments WHERE appointment_id = p_appointment_id;
    IF FOUND THEN
        RETURN to_jsonb(v_appointment);
    END IF;

    -- 2. Transaction Advisory Lock on doctor slot to serialize concurrent bookings
    v_lock_key1 := pg_catalog.hashtext(p_doctor_id);
    v_lock_key2 := pg_catalog.hashtext(EXTRACT(epoch FROM p_date_time)::text);
    PERFORM pg_catalog.pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

    -- 3. Duplicate Active Booking check by same patient for this slot
    IF EXISTS (
        SELECT 1 FROM public.appointments
        WHERE patient_id = v_patient_id
          AND doctor_id = p_doctor_id
          AND date_time = p_date_time
          AND patient_status != 'cancelled'
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_PATIENT_BOOKING: You already have an active appointment for this slot.'
            USING ERRCODE = '23505';
    END IF;

    -- 4. Enforce Slot Capacity (Max 3 active bookings per slot)
    SELECT COUNT(*) INTO v_active_count
    FROM public.appointments
    WHERE doctor_id = p_doctor_id
      AND date_time = p_date_time
      AND patient_status != 'cancelled';

    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED: Slot "%" already reached its maximum capacity of 3 patients.',
            p_slot_label
            USING ERRCODE = 'P0001';
    END IF;

    -- 5. Calculate Sequential Daily Token Number
    IF p_token_number IS NULL THEN
        SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token_number
        FROM public.appointments
        WHERE doctor_id = p_doctor_id
          AND date_time::date = p_date_time::date;
    ELSE
        v_token_number := p_token_number;
    END IF;

    -- 6. Insert Appointment Record
    INSERT INTO public.appointments (
        appointment_id,
        doctor_id,
        patient_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        visit_type,
        token_number,
        clinic_name,
        clinic_address,
        doctor_status,
        patient_status,
        payment_status,
        consultation_fee,
        sync_origin,
        booked_by_uid,
        created_at,
        updated_at
    ) VALUES (
        p_appointment_id,
        p_doctor_id,
        v_patient_id,
        p_doctor_name,
        p_specialization,
        p_patient_name,
        p_patient_age,
        p_patient_gender,
        p_date_time,
        p_slot_label,
        COALESCE(p_visit_type, 'newVisit'),
        v_token_number,
        p_clinic_name,
        p_clinic_address,
        'pendingRequest',
        'pending',
        'pending',
        0.00,
        COALESCE(p_sync_origin, 'patient_supabase'),
        v_caller_uid,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    RETURNING * INTO v_appointment;

    RETURN to_jsonb(v_appointment);
END;
$$;

REVOKE ALL ON FUNCTION public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR, VARCHAR) TO authenticated;

-- Ensure remaining helper functions have search_path = '' and strict grants
CREATE OR REPLACE FUNCTION private.doctor_has_relationship(p_patient_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT (
        private.is_verified_doctor()
        AND (
            EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.patient_id = p_patient_id
                  AND a.doctor_id = private.current_profile_id()
                  AND a.doctor_status IS DISTINCT FROM 'cancelled'
                  AND a.doctor_status IS DISTINCT FROM 'noShow'
                  AND a.patient_status IS DISTINCT FROM 'cancelled'
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.patient_id = p_patient_id
                  AND pdl.doctor_id = private.current_profile_id()
            )
            OR EXISTS (
                SELECT 1 FROM public.patients p
                WHERE p.patient_id = p_patient_id
                  AND (
                      p.primary_doctor_id = private.current_profile_id()
                      OR p.invited_doctor_id = private.current_profile_id()
                      OR private.current_profile_id() = ANY(p.care_team_doctor_ids)
                  )
            )
        )
    );
$$;
REVOKE ALL ON FUNCTION private.doctor_has_relationship(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.doctor_has_relationship(TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.is_walkin_stub(p_patient_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.patients p
        WHERE p.patient_id = p_patient_id
          AND p.owner_uid IS NULL
          AND (
            p.primary_doctor_id = private.current_profile_id()
            OR EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.patient_id = p_patient_id
                  AND a.doctor_id = private.current_profile_id()
                  AND a.doctor_status IS DISTINCT FROM 'cancelled'
                  AND a.doctor_status IS DISTINCT FROM 'noShow'
                  AND a.patient_status IS DISTINCT FROM 'cancelled'
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.patient_id = p_patient_id
                  AND pdl.doctor_id = private.current_profile_id()
            )
          )
    );
$$;
REVOKE ALL ON FUNCTION private.is_walkin_stub(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_walkin_stub(TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.consume_otp_attempt(p_challenge_id TEXT)
RETURNS TABLE(attempts INT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    UPDATE public.otp_challenges
    SET attempts = attempts + 1
    WHERE challenge_id = p_challenge_id
      AND attempts < 5
    RETURNING attempts;
$$;
REVOKE ALL ON FUNCTION public.consume_otp_attempt(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_attempt(TEXT) TO service_role;

DROP FUNCTION IF EXISTS public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT);
CREATE OR REPLACE FUNCTION public.check_and_increment_rate_limit(
    p_bucket TEXT,
    p_max_count INT,
    p_window_seconds INT,
    p_category TEXT DEFAULT 'auth'
)
RETURNS TABLE(allowed BOOLEAN, current_count INT, reset_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_current_count INT;
    v_reset_at TIMESTAMPTZ;
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    SELECT window_start, count INTO v_window_start, v_current_count
    FROM public.rate_limits
    WHERE bucket = p_bucket AND category = p_category
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.rate_limits (bucket, category, count, window_start)
        VALUES (p_bucket, p_category, 1, v_now)
        ON CONFLICT (bucket, category) DO UPDATE
        SET count = public.rate_limits.count + 1
        RETURNING count, window_start INTO v_current_count, v_window_start;
        v_reset_at := v_window_start + (p_window_seconds || ' seconds')::INTERVAL;
        RETURN QUERY SELECT TRUE, v_current_count, v_reset_at;
        RETURN;
    END IF;

    IF v_now > v_window_start + (p_window_seconds || ' seconds')::INTERVAL THEN
        UPDATE public.rate_limits
        SET count = 1, window_start = v_now
        WHERE bucket = p_bucket AND category = p_category;
        v_reset_at := v_now + (p_window_seconds || ' seconds')::INTERVAL;
        RETURN QUERY SELECT TRUE, 1, v_reset_at;
        RETURN;
    END IF;

    IF v_current_count >= p_max_count THEN
        v_reset_at := v_window_start + (p_window_seconds || ' seconds')::INTERVAL;
        RETURN QUERY SELECT FALSE, v_current_count, v_reset_at;
        RETURN;
    END IF;

    UPDATE public.rate_limits
    SET count = count + 1
    WHERE bucket = p_bucket AND category = p_category
    RETURNING count, window_start INTO v_current_count, v_window_start;
    v_reset_at := v_window_start + (p_window_seconds || ' seconds')::INTERVAL;
    RETURN QUERY SELECT TRUE, v_current_count, v_reset_at;
END;
$$;
REVOKE ALL ON FUNCTION public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- 6. NATIVE POSTGRES TRIGGERS FOR DOCTOR RATINGS & REVIEW_PUBLIC SYNC
-- ----------------------------------------------------------------------------
-- Automatically updates review_public and recalculates doctor rating & review_count.
-- Uses internal_aggregate_sync config flag to bypass column lock during aggregate sync.

CREATE OR REPLACE FUNCTION public.fn_sync_review_aggregates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_doctor_id VARCHAR(64);
    v_avg NUMERIC(3, 2);
    v_count INT;
    v_masked_name VARCHAR(64);
BEGIN
    -- Bypass column immutability locks on doctors.rating and review_count during aggregate recalculation
    PERFORM pg_catalog.set_config('doctornect.internal_aggregate_sync', 'on', true);

    v_doctor_id := COALESCE(NEW.doctor_id, OLD.doctor_id);

    -- 1. Maintain review_public table
    IF TG_OP = 'DELETE' THEN
        DELETE FROM public.review_public WHERE review_id = OLD.review_id;
    ELSE
        -- Mask patient name (e.g., "Rahul Sharma" -> "Rahul S.")
        IF NEW.patient_name IS NOT NULL AND length(trim(NEW.patient_name)) > 0 THEN
            v_masked_name := split_part(trim(NEW.patient_name), ' ', 1) || 
                CASE WHEN position(' ' in trim(NEW.patient_name)) > 0 
                     THEN ' ' || substring(split_part(trim(NEW.patient_name), ' ', 2) from 1 for 1) || '.'
                     ELSE '' 
                END;
        ELSE
            v_masked_name := 'Patient';
        END IF;

        INSERT INTO public.review_public (
            review_id,
            doctor_id,
            rating,
            comment,
            masked_name,
            helpful_count,
            doctor_reply,
            created_at,
            updated_at
        ) VALUES (
            NEW.review_id,
            NEW.doctor_id,
            NEW.rating,
            NEW.comment,
            v_masked_name,
            COALESCE(NEW.helpful_count, 0),
            NEW.doctor_reply,
            COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
            CURRENT_TIMESTAMP
        )
        ON CONFLICT (review_id) DO UPDATE SET
            rating = EXCLUDED.rating,
            comment = EXCLUDED.comment,
            masked_name = EXCLUDED.masked_name,
            helpful_count = EXCLUDED.helpful_count,
            doctor_reply = EXCLUDED.doctor_reply,
            updated_at = CURRENT_TIMESTAMP;
    END IF;

    -- 2. Recalculate doctor rating & count
    SELECT
        COALESCE(ROUND(AVG(rating)::numeric, 2), 0.00),
        COUNT(*)
    INTO
        v_avg,
        v_count
    FROM public.reviews
    WHERE doctor_id = v_doctor_id;

    UPDATE public.doctors
    SET
        rating = v_avg,
        review_count = v_count,
        updated_at = CURRENT_TIMESTAMP
    WHERE doctor_id = v_doctor_id;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sync_review_aggregates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_sync_review_aggregates() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_reviews_aggregate_and_sync ON public.reviews;
CREATE TRIGGER trg_reviews_aggregate_and_sync
    AFTER INSERT OR UPDATE OR DELETE ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_review_aggregates();

-- Helpful votes synchronization
CREATE OR REPLACE FUNCTION public.fn_sync_review_helpful_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_review_id VARCHAR(128);
    v_count INT;
BEGIN
    v_review_id := COALESCE(NEW.review_id, OLD.review_id);
    SELECT COUNT(*) INTO v_count FROM public.review_votes WHERE review_id = v_review_id;
    UPDATE public.reviews SET helpful_count = v_count WHERE review_id = v_review_id;
    UPDATE public.review_public SET helpful_count = v_count WHERE review_id = v_review_id;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sync_review_helpful_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_sync_review_helpful_count() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_review_votes_helpful_count ON public.review_votes;
CREATE TRIGGER trg_review_votes_helpful_count
    AFTER INSERT OR DELETE ON public.review_votes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_review_helpful_count();
