-- ============================================================================
-- Migration: 20261020000002_phase_c_doctor_patient_cutover.sql
-- Description: Phase C Doctor & Patient Cutover
--   1. Realtime publication registration for all Doctor & Patient tables
--   2. Public doctor directory view (safe columns only)
--   3. Atomic prescription creation RPC (create_prescription_atomic)
--   4. Hardened column immutability locks on users.role, doctors.verified/rating
--   5. Hardened book_appointment_atomic (derives patient_id from auth.jwt()->>'sub',
--      slot advisory locking, idempotency check)
--   6. Native Postgres triggers for doctor review rating aggregation & review_public sync
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. REALTIME PUBLICATION REGISTRATION
-- ----------------------------------------------------------------------------
-- Ensures CDC logical replication is active for all Doctor & Patient tables.
-- Supabase Realtime only works on concrete base tables, not views.
DO $$
DECLARE
    t TEXT;
    target_tables TEXT[] := ARRAY[
        'appointments',
        'doctors',
        'doctor_availability',
        'doctor_blocked_dates',
        'patients',
        'family_members',
        'health_records',
        'prescriptions',
        'prescription_medicines',
        'prescription_investigations',
        'prescription_referrals',
        'referrals',
        'reviews',
        'review_public'
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
                    -- Table already in publication, ignore
                    NULL;
            END;
        END IF;
    END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. PUBLIC DOCTOR DIRECTORY (SAFE COLUMNS ONLY)
-- ----------------------------------------------------------------------------
-- Strips sensitive data: phone, email, state council number, owner_uid, fcm_token.
-- Exposes only verified, non-deactivated doctors.
CREATE OR REPLACE VIEW public.doctor_directory AS
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

GRANT SELECT ON public.doctor_directory TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 3. COLUMN IMMUTABILITY LOCKS (users.role, doctors.verified, ratings, counters)
-- ----------------------------------------------------------------------------
-- Ensures client JWT cannot alter critical columns directly.
-- Only service_role or database triggers may alter them.

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
-- Persists prescription header, medicines, investigations, and referrals
-- in a single atomic database transaction.
-- Derives doctor_id directly from auth.jwt()->>'sub'.
CREATE OR REPLACE FUNCTION public.create_prescription_atomic(
    payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_doctor_id TEXT;
    v_prescription_id TEXT;
    v_patient_id TEXT;
    v_med JSONB;
    v_inv JSONB;
    v_ref JSONB;
    v_existing_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- 1. Derive & verify caller
    v_doctor_id := COALESCE(auth.jwt()->>'sub', current_setting('request.jwt.claims', true)::jsonb->>'sub');
    IF v_doctor_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to create prescription.'
            USING ERRCODE = '42501';
    END IF;

    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    v_prescription_id := trim(payload->>'prescription_id');
    v_patient_id := trim(payload->>'patient_id');

    IF v_prescription_id IS NULL OR v_prescription_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: prescription_id is required.'
            USING ERRCODE = '22004';
    END IF;

    IF v_patient_id IS NULL OR v_patient_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: patient_id is required.'
            USING ERRCODE = '22004';
    END IF;

    -- If prescription already exists, verify doctor ownership
    SELECT doctor_id INTO v_existing_id FROM public.prescriptions WHERE prescription_id = v_prescription_id;
    IF v_existing_id IS NOT NULL AND NOT v_is_admin AND v_existing_id != v_doctor_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Cannot overwrite prescription belonging to another doctor.'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Upsert prescription header
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
        payload->>'appointment_id',
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

    -- 3. Replace medicines atomically
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

    -- 4. Replace investigations atomically
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

    -- 5. Replace referral links atomically
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

REVOKE ALL ON FUNCTION public.create_prescription_atomic(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_prescription_atomic(JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. ATOMIC APPOINTMENT BOOKING (book_appointment_atomic)
-- ----------------------------------------------------------------------------
-- Strictly derives patient_id from auth.jwt()->>'sub'. Never trusts client parameter.
-- Idempotency: Returns existing appointment record if already booked.
-- Slot conflict: Transaction-level advisory lock prevents race conditions.
CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_patient_id VARCHAR(64), -- Kept for backward compatibility, overridden by auth.jwt()->>'sub'
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
    p_sync_origin VARCHAR(32) DEFAULT 'patient_supabase'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_patient_id TEXT;
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Strictly derive patient_id from auth.jwt()->>'sub'
    v_patient_id := COALESCE(auth.jwt()->>'sub', current_setting('request.jwt.claims', true)::jsonb->>'sub');
    IF v_patient_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to book an appointment.'
            USING ERRCODE = '42501';
    END IF;

    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

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
    v_lock_key1 := hashtext(p_doctor_id);
    v_lock_key2 := hashtext(extract(epoch from p_date_time)::text);
    PERFORM pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

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
        patient_status,
        doctor_status,
        token_number,
        clinic_name,
        clinic_address,
        sync_origin,
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
        'confirmed',
        'pendingRequest',
        v_token_number,
        p_clinic_name,
        p_clinic_address,
        COALESCE(p_sync_origin, 'patient_supabase'),
        NOW(),
        NOW()
    )
    RETURNING * INTO v_appointment;

    RETURN to_jsonb(v_appointment);
END;
$$;

REVOKE ALL ON FUNCTION public.book_appointment_atomic FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. NATIVE POSTGRES TRIGGERS FOR DOCTOR RATINGS & REVIEW_PUBLIC SYNC
-- ----------------------------------------------------------------------------
-- Automatically updates review_public and recalculates doctor rating & review_count.
CREATE OR REPLACE FUNCTION public.fn_sync_review_aggregates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_doctor_id VARCHAR(64);
    v_avg NUMERIC(3, 2);
    v_count INT;
    v_masked_name VARCHAR(64);
BEGIN
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
SET search_path = public, pg_temp
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

DROP TRIGGER IF EXISTS trg_review_votes_helpful_count ON public.review_votes;
CREATE TRIGGER trg_review_votes_helpful_count
    AFTER INSERT OR DELETE ON public.review_votes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_review_helpful_count();
