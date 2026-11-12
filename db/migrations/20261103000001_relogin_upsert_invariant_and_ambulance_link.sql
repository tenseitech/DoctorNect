-- =============================================================================
-- Migration: 20261103000001_relogin_upsert_invariant_and_ambulance_link.sql
-- Description:
--   1. Update private.trg_domain_profile_guard_update to enforce the provider
--      re-login upsert invariant (preserving verified=true when an already-verified
--      provider logs in and sends client upsert payload with verified=false).
--   2. Add public.claim_ambulance_driver(p_ambulance_id TEXT) SECURITY DEFINER RPC
--      allowing an authenticated ambulance driver to link their auth_uid to their
--      registered ambulance profile safely.
-- =============================================================================

-- 1. Update domain profile UPDATE guard with re-login upsert invariant
CREATE OR REPLACE FUNCTION private.trg_domain_profile_guard_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_old JSONB := to_jsonb(OLD);
    v_new JSONB;
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
    IF pg_trigger_depth() > 1 THEN
        FOR v_key IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
            IF (to_jsonb(NEW) ->> v_key) IS DISTINCT FROM (v_old ->> v_key) THEN
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

    -- Provider re-login upsert invariant:
    -- If provider is already verified, preserve verified=true on client updates sending verified=false or NULL
    IF TG_TABLE_NAME IN ('doctors', 'labs', 'medical_stores', 'ambulances') THEN
        IF (OLD.verified IS TRUE) AND (NEW.verified IS FALSE OR NEW.verified IS NULL) THEN
            NEW.verified := OLD.verified;
        END IF;
    END IF;

    v_new := to_jsonb(NEW);

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
    v_is_verified := COALESCE((v_old ->> 'verified')::boolean, FALSE);

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

-- 2. Ambulance driver linking RPC
CREATE OR REPLACE FUNCTION public.claim_ambulance_driver(p_ambulance_id TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_caller_sub TEXT;
    v_profile_id TEXT;
    v_existing_auth TEXT;
BEGIN
    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    IF v_caller_sub IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN: Authentication required' USING ERRCODE = '42501';
    END IF;

    -- Verify caller owns this ambulance profile via public.users
    SELECT profile_id INTO v_profile_id
    FROM public.users
    WHERE id = v_caller_sub AND role = 'ambulance';

    IF v_profile_id IS NULL OR v_profile_id IS DISTINCT FROM p_ambulance_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller is not registered as owner of ambulance %', p_ambulance_id
            USING ERRCODE = '42501';
    END IF;

    -- Fetch existing ambulance auth_uid
    SELECT auth_uid INTO v_existing_auth
    FROM public.ambulances
    WHERE ambulance_id = p_ambulance_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ambulance % not found', p_ambulance_id USING ERRCODE = 'P0002';
    END IF;

    IF v_existing_auth IS NOT NULL AND v_existing_auth IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: Ambulance % is already claimed by another driver', p_ambulance_id
            USING ERRCODE = '42501';
    END IF;

    -- Set auth_uid
    UPDATE public.ambulances
    SET auth_uid = v_caller_sub,
        updated_at = now()
    WHERE ambulance_id = p_ambulance_id;

    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_ambulance_driver(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_ambulance_driver(TEXT) TO authenticated, service_role;
