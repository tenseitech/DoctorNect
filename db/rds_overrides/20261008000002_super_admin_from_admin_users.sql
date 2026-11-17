-- RDS replay: super-admin via private.admin_users + JWT email (public.users, not auth.users).
BEGIN;

DELETE FROM private.admin_users AS admin_row
USING public.users AS u
WHERE admin_row.user_id = u.firebase_uid
  AND lower(u.email) IS DISTINCT FROM 'admin@doctornect.com';

INSERT INTO private.admin_users (user_id)
SELECT u.firebase_uid
FROM public.users u
WHERE lower(u.email) = 'admin@doctornect.com'
  AND u.verified IS TRUE
  AND u.firebase_uid IS NOT NULL
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
            JOIN public.users AS u ON u.firebase_uid = admin_row.user_id
            WHERE auth.jwt() ->> 'email_verified' = 'true'
              AND lower(u.email) = lower(auth.jwt() ->> 'email')
        ),
        FALSE
    );
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

COMMIT;