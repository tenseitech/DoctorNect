-- Migration: 20261103000006_harden_users_guard_orphan_and_unclaimed.sql
-- Description: Refine trg_users_guard_insert to strictly distinguish orphan domain entities (blocked) from unclaimed ambulances (claimable by ambulance drivers)

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

    -- Cannot claim a profile_id that exists as primary key in domain tables:
    -- 1. For ambulances: allow unclaimed profile (auth_uid IS NULL) only if caller registers with role='ambulance'.
    -- 2. For all other domain tables (or non-ambulance callers): block if owner IS DISTINCT FROM caller (including orphan/NULL).
    IF EXISTS (
        SELECT 1 FROM (
            SELECT patient_id AS pid, owner_uid AS owner, 'patient' AS domain_role FROM public.patients
            UNION ALL
            SELECT doctor_id AS pid, owner_uid AS owner, 'doctor' AS domain_role FROM public.doctors
            UNION ALL
            SELECT store_id AS pid, owner_uid AS owner, 'medicalStore' AS domain_role FROM public.medical_stores
            UNION ALL
            SELECT lab_id AS pid, owner_uid AS owner, 'lab' AS domain_role FROM public.labs
            UNION ALL
            SELECT ambulance_id AS pid, auth_uid AS owner, 'ambulance' AS domain_role FROM public.ambulances
        ) domain_pks
        WHERE domain_pks.pid = NEW.profile_id
          AND (
            (domain_pks.domain_role = 'ambulance' AND NEW.role = 'ambulance' AND domain_pks.owner IS NOT NULL AND domain_pks.owner IS DISTINCT FROM v_caller_sub)
            OR
            ((domain_pks.domain_role <> 'ambulance' OR NEW.role <> 'ambulance') AND domain_pks.owner IS DISTINCT FROM v_caller_sub)
          )
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
