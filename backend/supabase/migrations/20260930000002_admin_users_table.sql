-- ============================================================================
-- DoctorNect Platform — Dedicated Admin Users Table & Decoupled Admin Auth
-- File: 20260930000002_admin_users_table.sql
-- ============================================================================
-- Purpose:
-- 1. Eliminates hardcoded admin emails and insecure JWT email lookups from SQL.
-- 2. Establishes private.admin_users table referenced by private.is_super_admin().
-- 3. Safely seeds existing confirmed admin users from the allowlist.
-- 4. Aborts migration if zero confirmed admins exist to prevent lockout.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CREATE TABLE: private.admin_users
-- ============================================================================
CREATE TABLE IF NOT EXISTS private.admin_users (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    granted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS with zero public/authenticated policies (locked to database owner / service_role)
ALTER TABLE private.admin_users ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.admin_users FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE private.admin_users TO service_role;

-- ============================================================================
-- 2. SEED ADMIN USERS (CONFIRMED EMAILS ONLY) WITH LOCKOUT GUARD
-- ============================================================================
DO $$
DECLARE
    v_inserted INTEGER;
    v_total_admins INTEGER;
    v_auth_users_count INTEGER;
    v_whitelisted_exist INTEGER;
    v_whitelisted_confirmed INTEGER;
BEGIN
    WITH inserted AS (
        INSERT INTO private.admin_users (user_id)
        SELECT id FROM auth.users
        WHERE lower(email) IN (
            'admin@doctornect.com'
        )
        AND email_confirmed_at IS NOT NULL
        ON CONFLICT (user_id) DO NOTHING
        RETURNING user_id
    )
    SELECT COUNT(*) INTO v_inserted FROM inserted;

    SELECT COUNT(*) INTO v_total_admins FROM private.admin_users;

    RAISE NOTICE 'Admin users seed: % row(s) newly inserted. Total admin(s) in private.admin_users: %', 
        v_inserted, v_total_admins;

    -- Safety Guard: Abort only if private.admin_users is empty AND auth.users is populated AND no admin in public.users
    IF NOT EXISTS (SELECT 1 FROM auth.users) THEN
        RAISE NOTICE 'Fresh database detected (auth.users is empty). Lockout guard skipped.';
    ELSIF v_total_admins = 0
        AND EXISTS (SELECT 1 FROM auth.users)
        AND NOT EXISTS (
            SELECT 1 FROM public.users WHERE role IN ('super_admin', 'superAdmin', 'admin')
        )
    THEN
        SELECT COUNT(*) INTO v_auth_users_count FROM auth.users;

        SELECT
            COUNT(*),
            COUNT(*) FILTER (WHERE email_confirmed_at IS NOT NULL)
        INTO v_whitelisted_exist, v_whitelisted_confirmed
        FROM auth.users
        WHERE lower(email) IN (
            'sharmasd2@gmail.com',
            'tenseitechpvtltd@gmail.com',
            'admin@doctornect.com',
            'superadmin@doctornect.com',
            'support@doctornect.com'
        );

        RAISE EXCEPTION '%', format(
            'MIGRATION ABORTED: No confirmed admin users exist in private.admin_users and no admin roles found in public.users. Cannot proceed without at least one admin to prevent lockout. [database: %s, auth.users total: %s, whitelisted emails in auth.users: %s exist (%s confirmed)]. Hint: Create a confirmed user for a whitelisted email in THIS project (Auto Confirm User), then re-run db push.',
            current_database(),
            v_auth_users_count,
            v_whitelisted_exist,
            v_whitelisted_confirmed
        )
            USING ERRCODE = 'P0001';
    END IF;
END $$;

-- ============================================================================
-- 3. REDEFINE private.is_super_admin() (DATABASE-DRIVEN, NO HARDCODED EMAILS)
-- ============================================================================
CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT (
        private.current_user_role() IN ('super_admin', 'superAdmin', 'admin')
        OR EXISTS (SELECT 1 FROM private.admin_users WHERE user_id = auth.uid())
    );
$$ LANGUAGE sql;

-- Lockdown execution permissions
REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

-- Ensure public wrapper delegates cleanly
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.is_super_admin();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

COMMIT;

-- ============================================================================
-- ADMIN MANAGEMENT CHEATSHEET
-- ============================================================================
-- To grant Super Admin privileges to a user:
-- INSERT INTO private.admin_users (user_id, granted_by) VALUES ('<AUTH_USER_UUID>', auth.uid());
--
-- To revoke Super Admin privileges from a user:
-- DELETE FROM private.admin_users WHERE user_id = '<AUTH_USER_UUID>';
--
-- To list all current Super Admins:
-- SELECT u.id, u.email, a.granted_at 
-- FROM private.admin_users a 
-- JOIN auth.users u ON a.user_id = u.id;
