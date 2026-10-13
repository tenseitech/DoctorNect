-- ============================================================================
-- DoctorNect — Firebase Third-Party Identity Migration
-- Migration: 20261008000001_firebase_uid_identity.sql
-- ============================================================================
-- Firebase third-party identity:
-- auth.uid() is null or throws 22P02 for Firebase UIDs (they are alphanumeric strings, not UUIDs).
-- Identity is public.users.firebase_uid = auth.jwt() ->> 'sub'.
-- Internal foreign keys referencing public.users(id) use private.current_user_id() (UUID).
-- Text profile foreign keys use private.current_profile_id() (TEXT).
-- ============================================================================

-- 1. Helper Functions
CREATE OR REPLACE FUNCTION private.current_firebase_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NULLIF(auth.jwt() ->> 'sub', '');
$$;

REVOKE ALL ON FUNCTION private.current_firebase_uid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_firebase_uid() TO authenticated, service_role;


CREATE OR REPLACE FUNCTION private.current_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM public.users WHERE firebase_uid = private.current_firebase_uid() LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.current_user_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_id() TO authenticated, service_role;


CREATE OR REPLACE FUNCTION private.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT role FROM public.users WHERE firebase_uid = private.current_firebase_uid() LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.current_user_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_role() TO authenticated, service_role;


CREATE OR REPLACE FUNCTION private.current_profile_id()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT profile_id FROM public.users WHERE firebase_uid = private.current_firebase_uid() LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.current_profile_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_profile_id() TO authenticated, service_role;


CREATE OR REPLACE FUNCTION private.is_profile_completed()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(profile_completed, FALSE)
  FROM public.users
  WHERE firebase_uid = private.current_firebase_uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.is_profile_completed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_profile_completed() TO authenticated, service_role;


-- Redirect legacy/public helper functions to the Firebase-aware private implementations
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.current_user_role();
$$;

CREATE OR REPLACE FUNCTION public.current_profile_id()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.current_profile_id();
$$;

CREATE OR REPLACE FUNCTION public.is_profile_completed()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_profile_completed();
$$;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_profile_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_profile_completed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.current_profile_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_profile_completed() TO authenticated, service_role;


-- Drop DEFAULT auth.uid() from patients.owner_uid so inserts without owner_uid do not throw 22P02
ALTER TABLE public.patients ALTER COLUMN owner_uid DROP DEFAULT;


-- 2. Atomic Appointment Booking Function
CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_patient_id VARCHAR(64),
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
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
    v_caller_profile_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Strictly require authenticated session via private.current_firebase_uid()
    IF private.current_firebase_uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to book an appointment.'
            USING ERRCODE = '42501';
    END IF;

    -- Validate critical non-nullable parameters
    IF p_appointment_id IS NULL OR p_doctor_id IS NULL OR p_patient_id IS NULL OR p_date_time IS NULL THEN
        RAISE EXCEPTION 'BAD_REQUEST: Required booking parameters (appointment_id, doctor_id, patient_id, date_time) cannot be null.'
            USING ERRCODE = '22004';
    END IF;

    -- 1. Caller Authorization Check
    v_caller_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- If caller is not admin, they MUST have a valid profile_id in public.users
    IF NOT v_is_admin AND v_caller_profile_id IS NULL THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: Authenticated user % has no active profile in public.users.', private.current_firebase_uid()
            USING ERRCODE = '42501';
    END IF;

    -- Strict authorization: Super admin OR booking for caller's own profile
    IF NOT v_is_admin THEN
        IF p_patient_id IS DISTINCT FROM v_caller_profile_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot book appointment for another patient profile (Caller: %, Requested: %).',
                v_caller_profile_id, p_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Acquire Transaction-Level Advisory Lock on (doctor_id, epoch seconds)
    v_lock_key1 := hashtext(p_doctor_id);
    v_lock_key2 := hashtext(extract(epoch from p_date_time)::text);
    PERFORM pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

    -- 3. Check for Duplicate Active Booking by the Same Patient
    IF EXISTS (
        SELECT 1 FROM public.appointments
        WHERE patient_id = p_patient_id
          AND doctor_id = p_doctor_id
          AND date_time = p_date_time
          AND patient_status != 'cancelled'
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_PATIENT_BOOKING: Patient % already has an active booking for this slot.', p_patient_id
            USING ERRCODE = '23505';
    END IF;

    -- 4. Enforce Hard Slot Capacity (Max 3 Patients per Doctor Slot)
    SELECT COUNT(*) INTO v_active_count
    FROM public.appointments
    WHERE doctor_id = p_doctor_id
      AND date_time = p_date_time
      AND patient_status != 'cancelled';

    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED: Slot "%" for doctor "%" already has % active bookings (maximum capacity is 3).',
            p_slot_label, p_doctor_name, v_active_count
            USING ERRCODE = 'P0001';
    END IF;

    -- 5. Calculate Sequential Daily Token Number (if not supplied)
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
        p_patient_id,
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

REVOKE ALL ON FUNCTION public.book_appointment_atomic(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
    INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER,
    VARCHAR, TEXT, VARCHAR
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
    INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER,
    VARCHAR, TEXT, VARCHAR
) TO authenticated, service_role;


-- 3. Trigger Functions (Lock Columns & Users Integrity)
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
BEGIN
    IF v_is_admin OR private.current_firebase_uid() IS NULL THEN
        RETURN NEW;
    END IF;

    FOR i IN 0 .. (TG_NARGS - 1) LOOP
        v_col := TG_ARGV[i];
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


CREATE OR REPLACE FUNCTION private.enforce_users_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_is_admin BOOLEAN := COALESCE(private.is_super_admin(), FALSE);
BEGIN
    -- Bypass for super admins or internal service_role / postgres callers
    IF v_caller_is_admin OR private.current_firebase_uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Enforce on UPDATE for non-admin callers
    IF TG_OP = 'UPDATE' THEN
        -- Non-admins cannot alter their role
        IF NEW.role IS DISTINCT FROM OLD.role THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying user role is not permitted (Current: %, Requested: %)', 
                OLD.role, NEW.role
                USING ERRCODE = '42501';
        END IF;

        -- Non-admins cannot alter their verified status
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying verified status is not permitted'
                USING ERRCODE = '42501';
        END IF;

        -- Non-admins cannot alter profile_id
        IF NEW.profile_id IS DISTINCT FROM OLD.profile_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying profile_id is not permitted (Current: %, Requested: %)',
                OLD.profile_id, NEW.profile_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


-- 4. Row Level Security Policies
-- Users
DROP POLICY IF EXISTS "users_select_owner_or_admin" ON public.users;
CREATE POLICY "users_select_owner_or_admin" ON public.users
    FOR SELECT TO authenticated
    USING (firebase_uid = private.current_firebase_uid() OR is_super_admin());

DROP POLICY IF EXISTS "users_insert_self_or_admin" ON public.users;
CREATE POLICY "users_insert_self_or_admin" ON public.users
    FOR INSERT TO authenticated
    WITH CHECK (firebase_uid = private.current_firebase_uid() OR is_super_admin());

DROP POLICY IF EXISTS "users_update_owner_or_admin" ON public.users;
CREATE POLICY "users_update_owner_or_admin" ON public.users
    FOR UPDATE TO authenticated
    USING (firebase_uid = private.current_firebase_uid() OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin() 
        OR (
            firebase_uid = private.current_firebase_uid() 
            AND role = (SELECT role FROM public.users WHERE firebase_uid = private.current_firebase_uid())
            AND profile_id = (SELECT profile_id FROM public.users WHERE firebase_uid = private.current_firebase_uid())
            AND verified = (SELECT verified FROM public.users WHERE firebase_uid = private.current_firebase_uid())
        )
    );

-- Doctors (owner_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "doctors_select" ON public.doctors;
CREATE POLICY "doctors_select" ON public.doctors
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = private.current_user_id() OR is_super_admin());

DROP POLICY IF EXISTS "doctors_insert" ON public.doctors;
CREATE POLICY "doctors_insert" ON public.doctors
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = private.current_user_id()
            AND doctor_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND rating = 0.00
            AND review_count = 0
            AND deactivated = FALSE
            AND deactivated_at IS NULL
        )
    );

DROP POLICY IF EXISTS "doctors_update" ON public.doctors;
CREATE POLICY "doctors_update" ON public.doctors
    FOR UPDATE TO authenticated
    USING (
        owner_uid = private.current_user_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = private.current_user_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Patients (owner_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "patients_select" ON public.patients;
CREATE POLICY "patients_select" ON public.patients
    FOR SELECT TO authenticated
    USING (
        owner_uid = private.current_user_id() 
        OR patient_id = private.current_profile_id() 
        OR doctor_can_access_patient(patient_id::text) 
        OR is_super_admin()
    );

DROP POLICY IF EXISTS "patients_insert" ON public.patients;
CREATE POLICY "patients_insert" ON public.patients
    FOR INSERT TO authenticated
    WITH CHECK (
        (owner_uid = private.current_user_id() AND patient_id = private.current_profile_id())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "patients_update" ON public.patients;
CREATE POLICY "patients_update" ON public.patients
    FOR UPDATE TO authenticated
    USING (
        owner_uid = private.current_user_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = private.current_user_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Medical Stores (owner_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "medical_stores_select" ON public.medical_stores;
CREATE POLICY "medical_stores_select" ON public.medical_stores
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = private.current_user_id() OR is_super_admin());

DROP POLICY IF EXISTS "medical_stores_insert" ON public.medical_stores;
CREATE POLICY "medical_stores_insert" ON public.medical_stores
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = private.current_user_id()
            AND store_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND deactivated = FALSE
        )
    );

DROP POLICY IF EXISTS "medical_stores_update" ON public.medical_stores;
CREATE POLICY "medical_stores_update" ON public.medical_stores
    FOR UPDATE TO authenticated
    USING (
        owner_uid = private.current_user_id()
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = private.current_user_id()
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Labs (owner_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "labs_select" ON public.labs;
CREATE POLICY "labs_select" ON public.labs
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = private.current_user_id() OR is_super_admin());

DROP POLICY IF EXISTS "labs_insert" ON public.labs;
CREATE POLICY "labs_insert" ON public.labs
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = private.current_user_id()
            AND lab_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND rating = 0.00
            AND deactivated = FALSE
        )
    );

DROP POLICY IF EXISTS "labs_update" ON public.labs;
CREATE POLICY "labs_update" ON public.labs
    FOR UPDATE TO authenticated
    USING (
        owner_uid = private.current_user_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = private.current_user_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Ambulances (auth_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "ambulances_select" ON public.ambulances;
CREATE POLICY "ambulances_select" ON public.ambulances
    FOR SELECT TO authenticated
    USING (
        auth_uid = private.current_user_id() 
        OR (is_available = TRUE AND verified = TRUE)
        OR is_super_admin()
    );

DROP POLICY IF EXISTS "ambulances_insert" ON public.ambulances;
CREATE POLICY "ambulances_insert" ON public.ambulances
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            auth_uid = private.current_user_id()
            AND verified = FALSE
            AND total_rating = 0.00
            AND rating_count = 0
        )
    );

DROP POLICY IF EXISTS "ambulances_update" ON public.ambulances;
CREATE POLICY "ambulances_update" ON public.ambulances
    FOR UPDATE TO authenticated
    USING (
        auth_uid = private.current_user_id()
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        auth_uid = private.current_user_id()
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Promoted Ads (provider_id is VARCHAR(64) -> compare with private.current_profile_id())
DROP POLICY IF EXISTS "promoted_ads_insert" ON public.promoted_ads;
CREATE POLICY "promoted_ads_insert" ON public.promoted_ads
    FOR INSERT TO authenticated
    WITH CHECK (
        provider_id = private.current_profile_id()
        AND status IN ('draft', 'pending_payment')
        AND payment_status = 'pending'
    );

DROP POLICY IF EXISTS "promoted_ads_update" ON public.promoted_ads;
CREATE POLICY "promoted_ads_update" ON public.promoted_ads
    FOR UPDATE TO authenticated
    USING (
        (provider_id = private.current_profile_id() AND status IN ('draft', 'pending_payment'))
        OR is_super_admin()
    );

DROP POLICY IF EXISTS "promoted_ads_delete" ON public.promoted_ads;
CREATE POLICY "promoted_ads_delete" ON public.promoted_ads
    FOR DELETE TO authenticated
    USING (
        provider_id = private.current_profile_id()
        OR is_super_admin()
    );

-- In-App Notifications (recipient_uid is UUID -> compare with private.current_user_id())
DROP POLICY IF EXISTS "notifications_select" ON public.in_app_notifications;
CREATE POLICY "notifications_select" ON public.in_app_notifications
    FOR SELECT TO authenticated
    USING (recipient_uid = private.current_user_id());

DROP POLICY IF EXISTS "notifications_update" ON public.in_app_notifications;
CREATE POLICY "notifications_update" ON public.in_app_notifications
    FOR UPDATE TO authenticated
    USING (recipient_uid = private.current_user_id())
    WITH CHECK (recipient_uid = private.current_user_id());

-- Appointments & Clinical Links (re-pointed to private.current_profile_id())
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        is_super_admin()
        OR (
            private.is_profile_completed()
            AND (
                patient_id = private.current_profile_id()
                OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
            )
        )
    );

DROP POLICY IF EXISTS "doc_links_insert" ON public.patient_doctor_links;
CREATE POLICY "doc_links_insert" ON public.patient_doctor_links
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR (private.is_verified_doctor() AND source = 'referral' AND from_doctor_id = private.current_profile_id())
    );

DROP POLICY IF EXISTS "family_members_owner_only" ON public.family_members;
CREATE POLICY "family_members_owner_only" ON public.family_members
    FOR ALL TO authenticated
    USING (patient_id = private.current_profile_id())
    WITH CHECK (patient_id = private.current_profile_id());
