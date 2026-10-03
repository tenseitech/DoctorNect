-- ============================================================================
-- DoctorNect Platform — Security Hardening Migration
-- Migration: 20260930000003_users_integrity.sql
-- Description: Enforce strict identity & role integrity on public.users.
-- Prevents self-escalation (role mutation), profile impersonation (profile_id),
-- and unverified status tampering via column-level grants, RLS, and triggers.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. HARDEN RLS & TABLE PRIVILEGES ON public.users
-- ============================================================================

-- 1A. Drop the overly permissive insert policy
DROP POLICY IF EXISTS "users_insert_self_or_admin" ON public.users;

-- 1B. Restrict INSERT to super admins only (Defense-in-Depth)
-- NOTE: Table-level INSERT is revoked from 'authenticated' below.
-- This policy ensures that even if INSERT privilege is ever re-granted to authenticated in the future,
-- non-admin clients remain strictly blocked by RLS.
CREATE POLICY "users_insert_admin_only" ON public.users
    FOR INSERT TO authenticated
    WITH CHECK (private.is_super_admin());

-- 1C. Revoke table-level INSERT from authenticated role (service_role retains privileges)
REVOKE INSERT ON public.users FROM authenticated;

-- 1D. Replace broad UPDATE grant with strict column-level grants:
-- Revoke all update permissions, then re-grant ONLY legitimate client onboarding fields:
-- display_name, photo_url, photo_key, photo_storage, profile_completed.
-- Sensitive columns (id, firebase_uid, role, profile_id, email, mobile, verified, verified_at,
-- deactivated, status, created_at, updated_at) are completely unmodifiable by authenticated users.
REVOKE UPDATE ON public.users FROM authenticated;
GRANT UPDATE (display_name, photo_url, photo_key, photo_storage, profile_completed) 
ON public.users TO authenticated;

-- 1E. Redefine UPDATE policy with defense-in-depth WITH CHECK
DROP POLICY IF EXISTS "users_update_owner_or_admin" ON public.users;
CREATE POLICY "users_update_owner_or_admin" ON public.users
    FOR UPDATE TO authenticated
    USING (id = auth.uid() OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin() 
        OR (
            id = auth.uid() 
            AND role = (SELECT role FROM public.users WHERE id = auth.uid())
            AND profile_id = (SELECT profile_id FROM public.users WHERE id = auth.uid())
            AND verified = (SELECT verified FROM public.users WHERE id = auth.uid())
        )
    );

-- ============================================================================
-- 2. CREATE INTEGRITY TRIGGER IN private SCHEMA
-- ============================================================================
-- Trigger runs in schema private, SECURITY INVOKER, with search_path pinned.
-- Revoked from PUBLIC, anon, and authenticated (triggers execute without client EXECUTE).

CREATE OR REPLACE FUNCTION private.enforce_users_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_is_admin BOOLEAN := COALESCE(private.is_super_admin(), FALSE);
BEGIN
    -- Bypass for super admins or internal service_role / postgres callers (auth.uid() IS NULL)
    IF v_caller_is_admin OR auth.uid() IS NULL THEN
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

        -- Allowed fields (display_name, photo_url, photo_key, photo_storage, profile_completed)
        -- proceed smoothly and are protected by column-level grants.
    END IF;

    RETURN NEW;
END;
$$;

-- Revoke execute from all standard roles (Postgres triggers execute without requiring client EXECUTE)
REVOKE ALL ON FUNCTION private.enforce_users_integrity() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 3. BIND TRIGGER TO public.users
-- ============================================================================
DROP TRIGGER IF EXISTS trg_users_enforce_integrity ON public.users;
CREATE TRIGGER trg_users_enforce_integrity
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION private.enforce_users_integrity();

COMMIT;
