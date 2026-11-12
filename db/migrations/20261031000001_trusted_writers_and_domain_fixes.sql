-- DoctorNect Migration: 20261031000001_trusted_writers_and_domain_fixes.sql
-- Description: Trusted internal writer bypass via pg_trigger_depth() > 1, domain guard alignment for ambulances is_verified, and execute grants for review sync triggers.

-- ============================================================================
-- 1. EXECUTE GRANTS FOR REVIEW AGGREGATE SYNC TRIGGERS
-- ============================================================================
-- Triggers on public.reviews and public.review_votes fire during patient review submissions.
-- Authenticated role must have EXECUTE permission on these trigger functions to allow review submission.
GRANT EXECUTE ON FUNCTION public.fn_sync_review_aggregates() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_sync_review_helpful_count() TO authenticated, service_role;

-- ============================================================================
-- 2. DOMAIN PROFILE GUARD INSERT: Check verified and is_verified
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
-- 3. DOMAIN PROFILE GUARD UPDATE: Tamper-proof pg_trigger_depth() > 1 for review sync
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
    v_privileged_cols TEXT[];
    v_col TEXT;
BEGIN
    -- Privileged session bypass: service_role, super_admin, or direct backend/migration session
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'doctors' THEN
        v_privileged_cols := ARRAY['doctor_id', 'owner_uid', 'verified', 'is_verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'total_reviews', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'labs' THEN
        v_privileged_cols := ARRAY['lab_id', 'owner_uid', 'verified', 'is_verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'total_ratings', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'medical_stores' THEN
        v_privileged_cols := ARRAY['store_id', 'owner_uid', 'verified', 'is_verified', 'verified_at', 'deactivated', 'deactivated_at', 'rating', 'review_count', 'total_ratings', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        v_privileged_cols := ARRAY['ambulance_id', 'auth_uid', 'verified', 'is_verified', 'verified_at', 'total_rating', 'rating_count', 'rejection_reason', 'rejection_timestamp'];
    ELSIF TG_TABLE_NAME = 'patients' THEN
        v_privileged_cols := ARRAY['patient_id', 'owner_uid', 'verified', 'is_verified', 'verified_at'];
    ELSE
        RETURN NEW;
    END IF;

    FOREACH v_col IN ARRAY v_privileged_cols LOOP
        -- Internal aggregate sync may update ratings and review counts ONLY when executed from within an internal trigger
        -- Direct client REST calls have pg_trigger_depth() = 1 and are strictly blocked.
        IF pg_trigger_depth() > 1 AND v_col IN ('rating', 'review_count', 'total_reviews', 'total_rating', 'rating_count', 'total_ratings') THEN
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
