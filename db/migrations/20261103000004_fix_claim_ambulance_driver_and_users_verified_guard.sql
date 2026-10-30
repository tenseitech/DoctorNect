-- Migration: 20261103000004_fix_claim_ambulance_driver_and_users_verified_guard.sql
-- Description: Enforce verified immutability on users update and harden claim_ambulance_driver ownership verification

-- 1. Lock 'verified' on public.users against non-admin UPDATE
DROP TRIGGER IF EXISTS trg_users_lock_role ON public.users;
CREATE TRIGGER trg_users_lock_role
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('role', 'profile_id', 'firebase_uid', 'email', 'mobile', 'verified');

-- 2. Refine claim_ambulance_driver with phone match, role check, and ownership proof
CREATE OR REPLACE FUNCTION public.claim_ambulance_driver(p_ambulance_id TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_caller_sub TEXT;
    v_profile_id TEXT;
    v_user_role TEXT;
    v_user_mobile TEXT;
    v_existing_auth TEXT;
    v_target_phone TEXT;
BEGIN
    v_caller_sub := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');

    IF v_caller_sub IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN: Authentication required' USING ERRCODE = '42501';
    END IF;

    -- Verify caller exists in public.users and is registered as an ambulance driver
    SELECT role, profile_id, mobile INTO v_user_role, v_profile_id, v_user_mobile
    FROM public.users
    WHERE id = v_caller_sub;

    IF v_user_role IS NULL OR v_user_role <> 'ambulance' THEN
        RAISE EXCEPTION 'FORBIDDEN: Only registered ambulance drivers can claim an ambulance profile'
            USING ERRCODE = '42501';
    END IF;

    IF v_profile_id IS NULL OR v_profile_id IS DISTINCT FROM p_ambulance_id THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller is not registered as owner of ambulance %', p_ambulance_id
            USING ERRCODE = '42501';
    END IF;

    -- Fetch target ambulance details
    SELECT auth_uid, phone INTO v_existing_auth, v_target_phone
    FROM public.ambulances
    WHERE ambulance_id = p_ambulance_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ambulance % not found', p_ambulance_id USING ERRCODE = 'P0002';
    END IF;

    -- If already claimed by another driver, reject
    IF v_existing_auth IS NOT NULL AND v_existing_auth IS DISTINCT FROM v_caller_sub THEN
        RAISE EXCEPTION 'FORBIDDEN: Ambulance % is already claimed by another driver', p_ambulance_id
            USING ERRCODE = '42501';
    END IF;

    -- Verify mobile phone matches ambulance registered phone
    IF regexp_replace(COALESCE(v_user_mobile, ''), '\D', '', 'g') IS DISTINCT FROM 
       regexp_replace(COALESCE(v_target_phone, ''), '\D', '', 'g') THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller registered mobile does not match ambulance contact phone'
            USING ERRCODE = '42501';
    END IF;

    -- Set trusted RPC bypass flag for this transaction
    PERFORM set_config('app.allow_ambulance_driver_link', 'true', true);

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

-- 3. Allow table owner / service_role / security definer to maintain doctor_directory_updates under FORCE ROW LEVEL SECURITY
DROP POLICY IF EXISTS "doctor_directory_updates_admin_write" ON public.doctor_directory_updates;
CREATE POLICY "doctor_directory_updates_admin_write" ON public.doctor_directory_updates
FOR ALL TO PUBLIC
USING (current_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role') OR session_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role'))
WITH CHECK (current_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role') OR session_user IN ('rds_master', 'app_migrator', 'postgres', 'service_role'));

