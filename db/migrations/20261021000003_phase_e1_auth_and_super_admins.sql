-- Migration: 20261021000003_phase_e1_auth_and_super_admins.sql
-- Description: Phase E.1 Auth-Critical: public.super_admins, is_super_admin using (auth.jwt()->>'sub')

-- 1. Create public.super_admins table
CREATE TABLE IF NOT EXISTS public.super_admins (
    user_uid TEXT PRIMARY KEY, -- Firebase Auth UID
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT
);

-- Force RLS on super_admins
ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admins FORCE ROW LEVEL SECURITY;

-- 2. Create is_super_admin helper function checking user_uid against (auth.jwt()->>'sub')
CREATE OR REPLACE FUNCTION public.is_super_admin(check_uid TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF check_uid IS NULL OR check_uid = '' THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM public.super_admins WHERE user_uid = check_uid
    );
END;
$$;

-- Revoke all default permissions and grant execute to authenticated and service_role
REVOKE ALL ON FUNCTION public.is_super_admin(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin(TEXT) TO authenticated, service_role;

-- 3. Super Admins RLS Policy: Only existing super admins can read or manage super admins
CREATE POLICY super_admins_select ON public.super_admins
    FOR SELECT TO authenticated
    USING (public.is_super_admin(auth.jwt()->>'sub'));

CREATE POLICY super_admins_modify ON public.super_admins
    FOR ALL TO authenticated
    USING (public.is_super_admin(auth.jwt()->>'sub'))
    WITH CHECK (public.is_super_admin(auth.jwt()->>'sub'));

-- 4. Audit signal: record migration applied
COMMENT ON TABLE public.super_admins IS 'Authoritative super admin allowlist verified against Firebase UID (auth.jwt()->>sub)';
