-- Remove JWT email-only super_admin bypass; require private.admin_users + users email match + sub.
BEGIN;

CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(
        (
            current_setting('role', true) = 'service_role'
            OR (auth.jwt() ->> 'role') = 'service_role'
        )
        OR EXISTS (
            SELECT 1
            FROM private.admin_users AS admin_row
            JOIN public.users AS u ON u.firebase_uid = admin_row.user_id
            WHERE admin_row.user_id = (auth.jwt() ->> 'sub')
              AND COALESCE(auth.jwt() ->> 'email_verified', 'false') IN ('true', '1')
              AND lower(trim(COALESCE(auth.jwt() ->> 'email', ''))) = lower(u.email)
        ),
        FALSE
    );
$$;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

COMMIT;