-- Harden rating block (no auth.uid() NULL bypass); domain guard: no definer-session bypass with client JWT;
-- owner provider lifecycle may change deactivated (not verified).

CREATE OR REPLACE FUNCTION private.block_doctors_privileged_rating_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(private.is_super_admin(), FALSE)
       OR current_setting('role', true) = 'service_role'
       OR (auth.jwt() ->> 'role') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;
    IF NEW.rating IS DISTINCT FROM OLD.rating
       OR NEW.review_count IS DISTINCT FROM OLD.review_count THEN
        RAISE EXCEPTION 'FORBIDDEN: rating fields are server-maintained'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_verified_admin_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(private.is_super_admin(), FALSE)
       OR current_setting('role', true) = 'service_role'
       OR (auth.jwt() ->> 'role') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF current_setting('app.allow_provider_lifecycle_change', true) = 'true' THEN
        RETURN NEW;
    END IF;
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'doctors' OR TG_TABLE_NAME = 'labs' OR TG_TABLE_NAME = 'medical_stores' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'patients' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'users' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified
           OR NEW.role IS DISTINCT FROM OLD.role
           OR NEW.deactivated IS DISTINCT FROM OLD.deactivated THEN
            RAISE EXCEPTION 'FORBIDDEN: identity lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

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
    v_has_other_changes BOOLEAN := FALSE;
    v_jwt_sub TEXT;
    v_jwt_role TEXT;
BEGIN
    v_jwt_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    v_jwt_role := NULLIF(COALESCE(
        auth.jwt() ->> 'role',
        current_setting('request.jwt.claims', true)::jsonb ->> 'role'
    ), '');

    IF v_jwt_role = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE) THEN
        RETURN NEW;
    END IF;

    IF v_jwt_sub IS NULL
       AND current_setting('role', true) IS DISTINCT FROM 'authenticated'
       AND current_setting('role', true) IS DISTINCT FROM 'anon' THEN
        RETURN NEW;
    END IF;

    IF current_setting('app.allow_provider_lifecycle_change', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF current_setting('app.allow_ambulance_driver_link', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF pg_trigger_depth() > 1 THEN
        FOR v_key IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
            IF (to_jsonb(NEW) ->> v_key) IS DISTINCT FROM (v_old ->> v_key) THEN
                IF v_key IN ('rating', 'review_count', 'total_reviews', 'total_rating', 'rating_count', 'total_ratings', 'updated_at', 'deactivated', 'deactivated_at', 'reactivate_before', 'is_available') THEN
                    CONTINUE;
                ELSE
                    RAISE EXCEPTION 'FORBIDDEN: Internal trigger cannot modify column "%"', v_key
                        USING ERRCODE = '42501';
                END IF;
            END IF;
        END LOOP;
        RETURN NEW;
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(to_jsonb(NEW)) LOOP
        IF v_key NOT IN ('verified', 'is_verified', 'updated_at') THEN
            IF (to_jsonb(NEW) ->> v_key) IS DISTINCT FROM (v_old ->> v_key) THEN
                v_has_other_changes := TRUE;
                EXIT;
            END IF;
        END IF;
    END LOOP;

    IF TG_TABLE_NAME IN ('doctors', 'labs', 'medical_stores', 'ambulances') THEN
        IF (OLD.verified IS TRUE) AND (NEW.verified IS FALSE OR NEW.verified IS NULL) THEN
            IF v_has_other_changes THEN
                NEW.verified := OLD.verified;
            END IF;
        END IF;
    END IF;

    v_new := to_jsonb(NEW);

    v_caller_sub := v_jwt_sub;

    IF TG_TABLE_NAME = 'ambulances' THEN
        v_owner_val := v_old ->> 'auth_uid';
    ELSE
        v_owner_val := v_old ->> 'owner_uid';
    END IF;

    IF v_owner_val IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller is not the owner of this domain profile'
            USING ERRCODE = '42501';
    END IF;

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

    FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
        IF (v_new ->> v_key) IS NOT DISTINCT FROM (v_old ->> v_key) THEN
            CONTINUE;
        END IF;

        IF v_key = 'updated_at' THEN
            CONTINUE;
        END IF;
            IF v_is_verified AND (v_key = ANY(v_kyc_cols)) THEN
                RAISE EXCEPTION 'FORBIDDEN: KYC column "%" on table "%" is immutable once verified',
                    v_key, TG_TABLE_NAME
                    USING ERRCODE = '42501';
            END IF;
        IF NOT (v_key = ANY(v_allowed_cols)) THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (not client-editable)',
                v_key, TG_TABLE_NAME
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;