-- ============================================================================
-- DoctorNect — super admin identity reads only private.admin_users
-- Migration: 20261008000002_super_admin_from_admin_users.sql
-- ============================================================================
-- private.is_super_admin() no longer trusts a role string or an email list
-- inside the function. A caller is a super admin only when auth.users has a
-- row in private.admin_users and the verified JWT email matches that row.
--
-- Seed: insert auth.users.id for admin@doctornect.com when that confirmed
-- user already exists. No other email is added. If the user does not exist
-- yet, the insert adds nothing and the function stays false.
--
-- These statements were NOT executed against a database. Super-admin
-- identity is NOT verified in production by this file.
-- ============================================================================

BEGIN;

DELETE FROM private.admin_users AS admin_row
USING auth.users AS auth_user
WHERE admin_row.user_id = auth_user.id
  AND lower(auth_user.email) IS DISTINCT FROM 'admin@doctornect.com';

INSERT INTO private.admin_users (user_id)
SELECT id
FROM auth.users
WHERE lower(email) = 'admin@doctornect.com'
  AND email_confirmed_at IS NOT NULL
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        EXISTS (
            SELECT 1
            FROM private.admin_users AS admin_row
            JOIN auth.users AS auth_user ON auth_user.id = admin_row.user_id
            WHERE auth.jwt() ->> 'email_verified' = 'true'
              AND lower(auth_user.email) = lower(auth.jwt() ->> 'email')
        ),
        FALSE
    );
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

COMMIT;
