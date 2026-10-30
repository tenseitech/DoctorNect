-- DoctorNect Migration: 20261102000001_round6_guards_and_kyc.sql
-- Description: Round 6 security updates:
-- 1. Reviews INSERT policy: Family patient support + completed appointment enforcement + self-review prevention.
-- 2. Domain UPDATE trigger guard: Strict ownership check, KYC column immutability once verified, trusted trigger bypass for review sync, and column allowlists.
-- 3. Domain RLS policies: doctors_select and domain UPDATE policies enabling trigger evaluation on non-owner attempts.
-- 4. Provider Lifecycle RPCs: Owner-bound deactivate_provider_profile() and reactivate_provider_profile().

-- ============================================================================
-- 1. REVIEWS INSERT RLS: Family patient review support + completed appointment
-- ============================================================================
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert" ON public.reviews
FOR INSERT TO authenticated
WITH CHECK (
    -- Super admin / service_role bypass
    private.is_super_admin()
    OR (
        -- Reviewer must be current authenticated profile OR a family patient owned by caller
        (
            patient_id = private.current_profile_id()
            OR EXISTS (
                SELECT 1 FROM public.patients p
                WHERE p.patient_id = reviews.patient_id
                  AND p.owner_uid = (auth.jwt() ->> 'sub')
            )
        )
        -- Cannot self-review: reviewer cannot be the doctor being reviewed
        AND patient_id IS DISTINCT FROM doctor_id
        AND NOT EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = reviews.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
        -- Must have a completed appointment between reviewer (or family member) and target doctor
        AND EXISTS (
            SELECT 1 FROM public.appointments a
            WHERE a.doctor_id = reviews.doctor_id
              AND a.patient_id = reviews.patient_id
              AND (a.patient_status = 'completed' OR a.doctor_status = 'completed')
        )
    )
);

-- Appointments SELECT policy: Allow selecting own and family member appointments
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = appointments.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR EXISTS (
            SELECT 1 FROM public.family_members fm
            WHERE fm.member_id = appointments.patient_id
              AND fm.patient_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

-- Reviews SELECT policy: Allow selecting own and family member reviews
DROP POLICY IF EXISTS "reviews_select" ON public.reviews;
CREATE POLICY "reviews_select" ON public.reviews
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = reviews.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

-- ============================================================================
-- 2. DOMAIN PROFILE UPDATE GUARD: Ownership, KYC immutability, and Allowlist
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
    v_caller_sub TEXT;
    v_owner_val TEXT;
    v_allowed_cols TEXT[];
    v_kyc_cols TEXT[];
    v_key TEXT;
    v_is_verified BOOLEAN;
BEGIN
    -- Privileged session bypass: service_role, super_admin, or direct backend/migration session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    -- Trusted RPC bypass for provider lifecycle management (deactivate/reactivate)
    IF current_setting('app.allow_provider_lifecycle_change', true) = 'true' THEN
        RETURN NEW;
    END IF;

    -- Internal trigger aggregate recalculation bypass (pg_trigger_depth() > 1)
    -- When a patient submits a review, fn_sync_review_aggregates updates doctor rating.
    -- In that context, the caller is the reviewing patient (not doctor owner), but pg_trigger_depth > 1.
    IF pg_trigger_depth() > 1 THEN
        -- Only allow aggregate columns or updated_at to change
        FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
            IF (v_new ->> v_key) IS DISTINCT FROM (v_old ->> v_key) THEN
                IF v_key IN ('rating', 'review_count', 'total_reviews', 'total_rating', 'rating_count', 'total_ratings', 'updated_at') THEN
                    CONTINUE;
                ELSE
                    RAISE EXCEPTION 'FORBIDDEN: Internal trigger cannot modify column "%"', v_key
                        USING ERRCODE = '42501';
                END IF;
            END IF;
        END LOOP;
        RETURN NEW;
    END IF;

    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    -- Determine owner UID of the existing row
    IF TG_TABLE_NAME = 'ambulances' THEN
        v_owner_val := v_old ->> 'auth_uid';
    ELSE
        v_owner_val := v_old ->> 'owner_uid';
    END IF;

    -- Strict ownership enforcement: Caller must be the owner of the profile
    IF v_owner_val IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller is not the owner of this domain profile'
            USING ERRCODE = '42501';
    END IF;

    -- Prevent modifying ownership columns
    IF TG_TABLE_NAME = 'ambulances' THEN
        IF (v_new ->> 'auth_uid') IS DISTINCT FROM (v_old ->> 'auth_uid') THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "auth_uid" on table "ambulances" is not permitted (not client-editable)'
                USING ERRCODE = '42501';
        END IF;
    ELSE
        IF (v_new ->> 'owner_uid') IS DISTINCT FROM (v_old ->> 'owner_uid') THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "owner_uid" on table "%" is not permitted (not client-editable)',
                TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- KYC Field Immutability Check:
    -- Once verified=true, critical credentials/registration numbers cannot be changed by non-admins
    v_is_verified := COALESCE((v_old ->> 'verified')::boolean, (v_old ->> 'is_verified')::boolean, FALSE);

    IF TG_TABLE_NAME = 'doctors' THEN
        v_kyc_cols := ARRAY['council_number', 'state_council', 'certifications'];
        v_allowed_cols := ARRAY[
            'name', 'email', 'mobile', 'specialization', 'super_specialization',
            'qualification', 'experience_years', 'consultation_fee', 'clinic_name',
            'primary_facility_id', 'area', 'city', 'state', 'country', 'pincode',
            'address_line1', 'address_line2', 'state_council', 'council_number',
            'certifications', 'past_workplaces', 'memberships', 'awards',
            'publications', 'about', 'languages', 'photo_url', 'maps_link',
            'landmark', 'profile_completed', 'fcm_token', 'fcm_token_updated_at',
            'photo_key', 'photo_storage', 'photo_s3_key', 'photo_s3_bucket',
            'photo_storage_provider', 'photo_updated_at'
        ];
    ELSIF TG_TABLE_NAME = 'labs' THEN
        v_kyc_cols := ARRAY['license_number', 'gst_number'];
        v_allowed_cols := ARRAY[
            'lab_name', 'license_number', 'phone', 'email', 'gst_number',
            'area', 'city', 'state', 'country', 'pincode', 'address_line1',
            'address_line2', 'profile_completed'
        ];
    ELSIF TG_TABLE_NAME = 'medical_stores' THEN
        v_kyc_cols := ARRAY['drug_license_number', 'gst_number'];
        v_allowed_cols := ARRAY[
            'store_name', 'owner_name', 'drug_license_number', 'phone', 'email',
            'gst_number', 'address_line1', 'address_line2', 'city', 'state',
            'country', 'pincode', 'profile_completed'
        ];
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        v_kyc_cols := ARRAY['vehicle_number', 'license_number', 'insurance_number'];
        v_allowed_cols := ARRAY[
            'service_name', 'owner_name', 'driver_name', 'phone', 'vehicle_number',
            'ambulance_type', 'username', 'city', 'base_address', 'license_number',
            'insurance_number', 'has_oxygen', 'has_ventilator', 'has_stretcher',
            'is_24x7', 'rate_per_km', 'is_available', 'profile_completed',
            'address_line1', 'address_line2', 'state', 'country', 'pincode',
            'service_areas'
        ];
    ELSIF TG_TABLE_NAME = 'patients' THEN
        v_kyc_cols := ARRAY[]::TEXT[];
        v_allowed_cols := ARRAY[
            'name', 'email', 'mobile', 'age', 'gender', 'blood_group', 'height',
            'weight', 'address', 'photo_url', 'share_records_with_doctors',
            'primary_doctor_id', 'invited_doctor_id', 'care_team_doctor_ids',
            'profile_completed', 'fcm_token', 'fcm_token_updated_at', 'city',
            'state', 'pincode', 'country', 'conditions', 'allergies', 'metadata',
            'photo_key', 'photo_storage', 'photo_s3_key', 'photo_s3_bucket',
            'photo_storage_provider', 'photo_updated_at'
        ];
    ELSE
        RETURN NEW;
    END IF;

    -- Iterate over updated columns
    FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
        -- Ignore unchanged columns
        IF (v_new ->> v_key) IS NOT DISTINCT FROM (v_old ->> v_key) THEN
            CONTINUE;
        END IF;

        -- System timestamp updated_at is always allowed
        IF v_key = 'updated_at' THEN
            CONTINUE;
        END IF;

        -- KYC immutability check
        IF v_is_verified AND (v_key = ANY(v_kyc_cols)) THEN
            RAISE EXCEPTION 'FORBIDDEN: KYC column "%" on table "%" is immutable once verified',
                v_key, TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;

        -- Allowlist check
        IF NOT (v_key = ANY(v_allowed_cols)) THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (not client-editable)',
                v_key, TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. DOMAIN POLICIES: Enable trigger evaluation on update attempts
-- ============================================================================
DROP POLICY IF EXISTS doctors_select ON public.doctors;
CREATE POLICY doctors_select ON public.doctors
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS "doctors_update" ON public.doctors;
CREATE POLICY "doctors_update" ON public.doctors
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "labs_update" ON public.labs;
CREATE POLICY "labs_update" ON public.labs
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "medical_stores_update" ON public.medical_stores;
CREATE POLICY "medical_stores_update" ON public.medical_stores
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "ambulances_update" ON public.ambulances;
CREATE POLICY "ambulances_update" ON public.ambulances
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (auth_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "patients_update" ON public.patients;
CREATE POLICY "patients_update" ON public.patients
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

-- ============================================================================
-- 4. OWNER-BOUND RPCs: Provider Account Deactivation & Reactivation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deactivate_provider_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_caller_sub TEXT;
    v_profile_id TEXT;
    v_role TEXT;
BEGIN
    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    IF v_caller_sub IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
    END IF;

    SELECT profile_id, role INTO v_profile_id, v_role
    FROM public.users
    WHERE id = v_caller_sub;

    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'User profile not found' USING ERRCODE = '42501';
    END IF;

    -- Enable trusted lifecycle bypass for this transaction
    PERFORM set_config('app.allow_provider_lifecycle_change', 'true', true);

    -- Update users record
    UPDATE public.users
    SET deactivated = true, updated_at = NOW()
    WHERE id = v_caller_sub;

    -- Update corresponding domain table
    IF v_role = 'doctor' THEN
        UPDATE public.doctors
        SET deactivated = true,
            deactivated_at = NOW(),
            reactivate_before = NOW() + INTERVAL '30 days',
            updated_at = NOW()
        WHERE doctor_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role = 'lab' THEN
        UPDATE public.labs
        SET deactivated = true, updated_at = NOW()
        WHERE lab_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role IN ('medicalStore', 'medical') THEN
        UPDATE public.medical_stores
        SET deactivated = true, updated_at = NOW()
        WHERE store_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role = 'ambulance' THEN
        UPDATE public.ambulances
        SET is_available = false, updated_at = NOW()
        WHERE ambulance_id = v_profile_id AND auth_uid = v_caller_sub;
    END IF;

    RETURN jsonb_build_object('ok', true, 'deactivated', true, 'profile_id', v_profile_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.reactivate_provider_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_caller_sub TEXT;
    v_profile_id TEXT;
    v_role TEXT;
    v_reactivate_before TIMESTAMPTZ;
BEGIN
    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    IF v_caller_sub IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE = '42501';
    END IF;

    SELECT profile_id, role INTO v_profile_id, v_role
    FROM public.users
    WHERE id = v_caller_sub;

    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'User profile not found' USING ERRCODE = '42501';
    END IF;

    -- Enable trusted lifecycle bypass for this transaction
    PERFORM set_config('app.allow_provider_lifecycle_change', 'true', true);

    IF v_role = 'doctor' THEN
        SELECT reactivate_before INTO v_reactivate_before
        FROM public.doctors
        WHERE doctor_id = v_profile_id AND owner_uid = v_caller_sub;

        IF v_reactivate_before IS NOT NULL AND NOW() > v_reactivate_before THEN
            RAISE EXCEPTION 'Reactivation window has expired' USING ERRCODE = '42501';
        END IF;

        UPDATE public.doctors
        SET deactivated = false,
            reactivated_at = NOW(),
            verified = false,
            updated_at = NOW()
        WHERE doctor_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role = 'lab' THEN
        UPDATE public.labs
        SET deactivated = false, verified = false, updated_at = NOW()
        WHERE lab_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role IN ('medicalStore', 'medical') THEN
        UPDATE public.medical_stores
        SET deactivated = false, verified = false, updated_at = NOW()
        WHERE store_id = v_profile_id AND owner_uid = v_caller_sub;
    ELSIF v_role = 'ambulance' THEN
        UPDATE public.ambulances
        SET is_available = true, verified = false, updated_at = NOW()
        WHERE ambulance_id = v_profile_id AND auth_uid = v_caller_sub;
    END IF;

    UPDATE public.users
    SET deactivated = false, updated_at = NOW()
    WHERE id = v_caller_sub;

    RETURN jsonb_build_object('ok', true, 'deactivated', false, 'profile_id', v_profile_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_provider_profile() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reactivate_provider_profile() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.deactivate_provider_profile() FROM anon, PUBLIC;
REVOKE ALL ON FUNCTION public.reactivate_provider_profile() FROM anon, PUBLIC;
