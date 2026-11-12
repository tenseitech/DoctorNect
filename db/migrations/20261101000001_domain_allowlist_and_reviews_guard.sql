-- DoctorNect Migration: 20261101000001_domain_allowlist_and_reviews_guard.sql
-- Description: Domain profile UPDATE guard allowlist, starts_with family patient_id guard, and reviews completed appointment RLS policy.

-- ============================================================================
-- 1. REVIEWS INSERT RLS: Require completed appointment & deny self-review
-- ============================================================================
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert" ON public.reviews
FOR INSERT TO authenticated
WITH CHECK (
    -- Super admin / service_role bypass
    private.is_super_admin()
    OR (
        -- Reviewer must be current authenticated profile
        patient_id = private.current_profile_id()
        -- Cannot self-review: reviewer cannot be the doctor being reviewed
        AND patient_id IS DISTINCT FROM doctor_id
        AND NOT EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = reviews.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
        -- Must have a completed appointment between reviewer and target doctor
        AND EXISTS (
            SELECT 1 FROM public.appointments a
            WHERE a.doctor_id = reviews.doctor_id
              AND a.patient_id = reviews.patient_id
              AND (a.patient_status = 'completed' OR a.doctor_status = 'completed')
        )
    )
);

-- ============================================================================
-- 2. DOMAIN PROFILE INSERT GUARD: starts_with namespacing for family patient_id
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
        -- OR secondary family profile owned by caller AND namespaced to the caller via starts_with
        IF v_pk_val IS DISTINCT FROM v_user_profile_id THEN
            IF NOT (starts_with(v_pk_val, v_caller_sub || '_') OR starts_with(v_pk_val, v_user_profile_id || '_')) THEN
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
        IF (v_data ->> 'verified')::boolean IS TRUE OR (v_data ->> 'is_verified')::boolean IS TRUE THEN
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
-- 3. DOMAIN PROFILE UPDATE GUARD: Column Allowlist (Strict Whitelist)
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
    v_allowed_cols TEXT[];
    v_key TEXT;
BEGIN
    -- Privileged session bypass: service_role, super_admin, or direct backend/migration session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'doctors' THEN
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
        v_allowed_cols := ARRAY[
            'lab_name', 'license_number', 'phone', 'email', 'gst_number',
            'area', 'city', 'state', 'country', 'pincode', 'address_line1',
            'address_line2', 'profile_completed'
        ];
    ELSIF TG_TABLE_NAME = 'medical_stores' THEN
        v_allowed_cols := ARRAY[
            'store_name', 'owner_name', 'drug_license_number', 'phone', 'email',
            'gst_number', 'address_line1', 'address_line2', 'city', 'state',
            'country', 'pincode', 'profile_completed'
        ];
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        v_allowed_cols := ARRAY[
            'service_name', 'owner_name', 'driver_name', 'phone', 'vehicle_number',
            'ambulance_type', 'username', 'city', 'base_address', 'license_number',
            'insurance_number', 'has_oxygen', 'has_ventilator', 'has_stretcher',
            'is_24x7', 'rate_per_km', 'is_available', 'profile_completed',
            'address_line1', 'address_line2', 'state', 'country', 'pincode',
            'service_areas'
        ];
    ELSIF TG_TABLE_NAME = 'patients' THEN
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

    -- Iterate over all keys present in the updated row
    FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
        -- Ignore unchanged columns
        IF (v_new ->> v_key) IS NOT DISTINCT FROM (v_old ->> v_key) THEN
            CONTINUE;
        END IF;

        -- System timestamp updated_at is always allowed
        IF v_key = 'updated_at' THEN
            CONTINUE;
        END IF;

        -- Internal trigger aggregate recalculation (pg_trigger_depth() > 1)
        IF pg_trigger_depth() > 1 AND v_key IN ('rating', 'review_count', 'total_reviews', 'total_rating', 'rating_count', 'total_ratings') THEN
            CONTINUE;
        END IF;

        -- If changed column is not in the client allowlist, reject with 42501
        IF NOT (v_key = ANY(v_allowed_cols)) THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (not client-editable)',
                v_key, TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;
