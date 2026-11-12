-- ============================================================================
-- DoctorNect Platform — NULL-Safe is_super_admin() Function
-- Migration: 20261002000001_is_super_admin_null_safe.sql
-- ============================================================================
-- Purpose:
-- Wrap is_super_admin() evaluations in COALESCE(..., FALSE) so that queries
-- executed under authenticated sessions without a public.users row return
-- strictly FALSE instead of NULL (safe boolean guarantee).
-- ============================================================================

BEGIN;

-- 1. REDEFINE private.is_super_admin() WITH COALESCE
CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT COALESCE(
        (
            private.current_user_role() IN ('super_admin', 'superAdmin', 'admin')
            OR EXISTS (SELECT 1 FROM private.admin_users WHERE user_id = auth.uid())
        ),
        FALSE
    );
$$ LANGUAGE sql;

-- Lockdown execution permissions
REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

-- 2. REDEFINE public.is_super_admin() WRAPPER WITH COALESCE
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT COALESCE(private.is_super_admin(), FALSE);
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

COMMIT;
