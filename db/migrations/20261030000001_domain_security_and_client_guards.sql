-- DoctorNect Migration: 20261030000001_domain_security_and_client_guards.sql
-- Description: Privileged domain column protection, family patient_id namespacing, users verified upsert fix, ambulance contact masking & RPC revocation, anon column pruning.

-- ============================================================================
-- 1. IS_SUPER_ADMIN & REVOKE get_ambulance_trip_contact FROM AUTHENTICATED
-- ============================================================================
CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT (
        current_setting('role', true) = 'service_role'
        OR (auth.jwt() ->> 'role') = 'service_role'
        OR COALESCE(auth.jwt() ->> 'user_role', auth.jwt() ->> 'app_role', '') IN ('super_admin', 'superAdmin', 'admin')
        OR EXISTS (
            SELECT 1 FROM public.users 
            WHERE id = (auth.jwt() ->> 'sub') 
              AND role IN ('super_admin', 'superAdmin', 'admin')
        )
        OR EXISTS (
            SELECT 1 FROM private.admin_users 
            WHERE user_id = (auth.jwt() ->> 'sub')
        )
    );
$$;

REVOKE ALL ON FUNCTION public.get_ambulance_trip_contact(VARCHAR) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_contact(VARCHAR) TO service_role;

-- ============================================================================
-- 2. USERS GUARD: Allow verified=true on upsert if user already verified
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_users_guard_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
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

    -- Only patients may self-verify upon new registration;
    -- For domain roles, verified=true is only allowed if the user row ALREADY exists and is already verified
    IF NEW.role <> 'patient' AND NEW.verified IS TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = NEW.id
              AND u.verified IS TRUE
        ) THEN
            RAISE EXCEPTION 'FORBIDDEN: Domain role accounts cannot self-verify' USING ERRCODE = '42501';
        END IF;
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
$$;

-- ============================================================================
-- 3. DOMAIN INSERT GUARD: Family patient namespacing & privileged column lock
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_domain_profile_guard_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
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

    -- Table-specific INSERT validations
    IF TG_TABLE_NAME = 'patients' THEN
        -- Allowed: primary profile (v_pk_val = v_user_profile_id)
        -- OR secondary family profile owned by caller AND namespaced to the caller
        IF v_pk_val IS DISTINCT FROM v_user_profile_id THEN
            IF NOT (v_pk_val LIKE (v_caller_sub || '_%') OR v_pk_val LIKE (v_user_profile_id || '_%')) THEN
                RAISE EXCEPTION 'FORBIDDEN: Family patient_id must be namespaced to owner subject (e.g. %_<id>)',
                    v_caller_sub
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    ELSE
        -- Non-patient domain tables must strictly match the user's profile_id
        IF v_pk_val IS DISTINCT FROM v_user_profile_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Domain profile ID must match user profile_id in public.users'
                USING ERRCODE = '42501';
        END IF;

        -- Non-admin cannot self-set privileged fields on INSERT
        IF (v_data ->> 'verified')::boolean IS TRUE THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot self-set verified=true on registration'
                USING ERRCODE = '42501';
        END IF;

        IF (v_data ->> 'deactivated')::boolean IS TRUE THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot self-set deactivated=true on registration'
                USING ERRCODE = '42501';
        END IF;

        IF COALESCE((v_data ->> 'rating')::numeric, 0) > 0 
           OR COALESCE((v_data ->> 'total_rating')::numeric, 0) > 0
           OR COALESCE((v_data ->> 'rating_count')::int, 0) > 0
           OR COALESCE((v_data ->> 'review_count')::int, 0) > 0
           OR COALESCE((v_data ->> 'total_ratings')::int, 0) > 0 THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot self-set ratings or review counts on registration'
                USING ERRCODE = '42501';
        END IF;

        IF (v_data ->> 'rejection_reason') IS NOT NULL
           OR (v_data ->> 'rejection_timestamp') IS NOT NULL
           OR (v_data ->> 'verified_at') IS NOT NULL
           OR (v_data ->> 'deactivated_at') IS NOT NULL THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot set admin audit columns on registration'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 4. DOMAIN UPDATE GUARD: Privileged column lock on doctors, labs, stores, ambulances
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_domain_profile_guard_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_old JSONB := to_jsonb(OLD);
    v_new JSONB := to_jsonb(NEW);
    v_is_admin BOOLEAN;
    v_is_agg_sync BOOLEAN;
    v_privileged_cols TEXT[];
    v_col TEXT;
BEGIN
    -- Privileged session bypass: service_role, super_admin, or backend session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    v_is_agg_sync := (current_setting('doctornect.internal_aggregate_sync', true) = 'on');

    IF TG_TABLE_NAME = 'doctors' THEN
        v_privileged_cols := ARRAY['doctor_id', 'owner_uid', 'verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'labs' THEN
        v_privileged_cols := ARRAY['lab_id', 'owner_uid', 'verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'total_ratings', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'medical_stores' THEN
        v_privileged_cols := ARRAY['store_id', 'owner_uid', 'verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'total_ratings', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        v_privileged_cols := ARRAY['ambulance_id', 'auth_uid', 'verified', 'verified_at', 'total_rating', 'rating_count', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'patients' THEN
        v_privileged_cols := ARRAY['patient_id', 'owner_uid', 'verified', 'verified_at'];
    ELSE
        RETURN NEW;
    END IF;

    FOREACH v_col IN ARRAY v_privileged_cols LOOP
        -- Internal aggregate sync may update ratings and review counts
        IF v_is_agg_sync AND v_col IN ('rating', 'review_count', 'total_rating', 'rating_count', 'total_ratings') THEN
            CONTINUE;
        END IF;

        IF (v_new ->> v_col) IS DISTINCT FROM (v_old ->> v_col) THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying privileged column "%" on table "%" is not permitted',
                v_col, TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- Drop previous duplicate/legacy update lock triggers
DROP TRIGGER IF EXISTS trg_doctors_lock_columns ON public.doctors;
DROP TRIGGER IF EXISTS trg_doctors_lock_verification ON public.doctors;
DROP TRIGGER IF EXISTS trg_labs_lock_columns ON public.labs;
DROP TRIGGER IF EXISTS trg_medical_stores_lock_columns ON public.medical_stores;
DROP TRIGGER IF EXISTS trg_ambulances_lock_columns ON public.ambulances;
DROP TRIGGER IF EXISTS trg_patients_lock_columns ON public.patients;

-- Attach unified domain profile guard update triggers
DROP TRIGGER IF EXISTS trg_doctors_guard_update ON public.doctors;
CREATE TRIGGER trg_doctors_guard_update
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_domain_profile_guard_update();

DROP TRIGGER IF EXISTS trg_labs_guard_update ON public.labs;
CREATE TRIGGER trg_labs_guard_update
    BEFORE UPDATE ON public.labs
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_domain_profile_guard_update();

DROP TRIGGER IF EXISTS trg_medical_stores_guard_update ON public.medical_stores;
CREATE TRIGGER trg_medical_stores_guard_update
    BEFORE UPDATE ON public.medical_stores
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_domain_profile_guard_update();

DROP TRIGGER IF EXISTS trg_ambulances_guard_update ON public.ambulances;
CREATE TRIGGER trg_ambulances_guard_update
    BEFORE UPDATE ON public.ambulances
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_domain_profile_guard_update();

DROP TRIGGER IF EXISTS trg_patients_guard_update ON public.patients;
CREATE TRIGGER trg_patients_guard_update
    BEFORE UPDATE ON public.patients
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_domain_profile_guard_update();

-- ============================================================================
-- 5. AMBULANCE BROADCAST CONTACT PRIVACY: Mask patient phone while pending
-- ============================================================================
-- Make foreign key on ambulance_trip_contacts deferrable so BEFORE INSERT trigger can store phone
ALTER TABLE public.ambulance_trip_contacts
    DROP CONSTRAINT IF EXISTS ambulance_trip_contacts_broadcast_id_fkey,
    ADD CONSTRAINT ambulance_trip_contacts_broadcast_id_fkey
    FOREIGN KEY (broadcast_id)
    REFERENCES public.ambulance_broadcasts(broadcast_id)
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION private.trg_ambulance_broadcast_contact_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    -- On INSERT: If broadcast is pending, store the patient phone securely in
    -- ambulance_trip_contacts and mask it on public ambulance_broadcasts
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'pending' AND NEW.contact_phone IS NOT NULL AND NEW.contact_phone <> '' THEN
            INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, updated_at)
            VALUES (NEW.broadcast_id, NEW.contact_phone, CURRENT_TIMESTAMP)
            ON CONFLICT (broadcast_id) DO UPDATE SET
                patient_phone = EXCLUDED.patient_phone,
                updated_at = CURRENT_TIMESTAMP;
            NEW.contact_phone := NULL;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        -- If status is changing to accepted, unmask the patient contact from ambulance_trip_contacts
        IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
            SELECT patient_phone INTO NEW.contact_phone
            FROM public.ambulance_trip_contacts
            WHERE broadcast_id = NEW.broadcast_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ambulance_broadcast_contact_guard ON public.ambulance_broadcasts;
CREATE TRIGGER trg_ambulance_broadcast_contact_guard
    BEFORE INSERT OR UPDATE ON public.ambulance_broadcasts
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_ambulance_broadcast_contact_guard();

-- ============================================================================
-- 6. ANONYMOUS ACCESS PRUNING: medical_directory & promoted_ads
-- ============================================================================
-- Revoke medical_directory from anon (it is doctor-private)
REVOKE ALL ON public.medical_directory FROM anon;
DROP POLICY IF EXISTS "medical_directory_select" ON public.medical_directory;
CREATE POLICY "medical_directory_select" ON public.medical_directory
    FOR SELECT TO authenticated
    USING (TRUE);

-- Restrict promoted_ads columns for anon: exclude internal/financial fields
REVOKE ALL ON public.promoted_ads FROM anon;
GRANT SELECT (
    ad_id,
    provider_id,
    provider_type,
    title,
    description,
    image_url,
    image_s3_key,
    image_s3_bucket,
    image_storage_provider,
    cta_label,
    duration_hours,
    target_city,
    status,
    start_time,
    end_time,
    created_at,
    updated_at
) ON public.promoted_ads TO anon;
