-- Migration: 20261103000005_remove_scratch_bypass_policies.sql
-- Description: Remove scratch bypass policies, harden users guard for unclaimed ambulance linking, and switch claim_ambulance_driver to verified JWT phone_number claim

-- 1. Drop temporary scratch bypass policies from domain tables
DROP POLICY IF EXISTS "doctor_directory_updates_admin_write" ON public.doctor_directory_updates;
DROP POLICY IF EXISTS "system_config_migrator_bypass" ON public.system_config;

-- 2. Relax FORCE ROW LEVEL SECURITY on doctor_directory_updates so table owner & internal SECURITY DEFINER triggers can update it cleanly without bypass policies.
-- (RLS remains ENABLED, preventing unauthenticated and unauthorized client access)
ALTER TABLE public.doctor_directory_updates NO FORCE ROW LEVEL SECURITY;

-- 3. Production-safe seeding function for system_config (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION private.upsert_system_config(p_config_key VARCHAR, p_config_value JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    -- Only service_role, super_admin, or backend session (non-authenticated/anon) can seed system config
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        EXECUTE 'ALTER TABLE public.system_config NO FORCE ROW LEVEL SECURITY';
        INSERT INTO public.system_config (config_key, config_value, updated_at)
        VALUES (p_config_key, p_config_value, CURRENT_TIMESTAMP)
        ON CONFLICT (config_key) DO UPDATE
        SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP;
        EXECUTE 'ALTER TABLE public.system_config FORCE ROW LEVEL SECURITY';
    ELSE
        RAISE EXCEPTION 'FORBIDDEN: Administrative privileges required to update system_config' USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION private.upsert_system_config(VARCHAR, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.upsert_system_config(VARCHAR, JSONB) TO postgres, service_role;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
        GRANT EXECUTE ON FUNCTION private.upsert_system_config(VARCHAR, JSONB) TO rds_master;
    END IF;
END $$;

-- 4. Harden trg_users_guard_insert to allow registering with unclaimed domain profile IDs (e.g. admin-created ambulances with auth_uid IS NULL)
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
          AND domain_pks.owner IS NOT NULL
          AND domain_pks.owner IS DISTINCT FROM v_caller_sub
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN: Profile ID is already claimed by another entity' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_guard_insert ON public.users;
CREATE TRIGGER trg_users_guard_insert
    BEFORE INSERT ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_users_guard_insert();

REVOKE ALL ON FUNCTION private.trg_users_guard_insert() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.trg_users_guard_insert() TO service_role;

-- 5. Hardened claim_ambulance_driver: verify caller phone against cryptographically verified JWT phone_number claim
CREATE OR REPLACE FUNCTION public.claim_ambulance_driver(p_ambulance_id TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_caller_sub TEXT;
    v_caller_phone TEXT;
    v_profile_id TEXT;
    v_user_role TEXT;
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

    -- Extract verified phone number from JWT claims (cryptographically signed by Firebase Auth)
    v_caller_phone := NULLIF(COALESCE(
        auth.jwt() ->> 'phone_number',
        current_setting('request.jwt.claims', true)::jsonb ->> 'phone_number'
    ), '');

    IF v_caller_phone IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller token does not contain a verified phone number'
            USING ERRCODE = '42501';
    END IF;

    -- Verify caller exists in public.users and is registered as an ambulance driver
    SELECT role, profile_id INTO v_user_role, v_profile_id
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

    -- Verify caller verified phone matches ambulance registered phone
    IF regexp_replace(COALESCE(v_caller_phone, ''), '\D', '', 'g') IS DISTINCT FROM 
       regexp_replace(COALESCE(v_target_phone, ''), '\D', '', 'g') THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller verified phone does not match ambulance contact phone'
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
