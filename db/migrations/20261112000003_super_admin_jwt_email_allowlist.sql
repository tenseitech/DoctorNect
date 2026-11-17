-- Ensure Firebase-backed Supabase JWTs for admin@doctornect.com pass is_super_admin() for RLS (audit logs, etc.).

CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT (
        current_setting('role', true) = 'service_role'
        OR (auth.jwt() ->> 'role') = 'service_role'
        OR COALESCE(auth.jwt() ->> 'user_role', auth.jwt() ->> 'app_role', '') IN ('super_admin', 'superAdmin', 'admin')
        OR (
            lower(trim(COALESCE(auth.jwt() ->> 'email', ''))) = 'admin@doctornect.com'
            AND COALESCE(auth.jwt() ->> 'email_verified', 'true') IN ('true', '1')
        )
        OR EXISTS (
            SELECT 1 FROM public.users
            WHERE id = (auth.jwt() ->> 'sub')
              AND role IN ('super_admin', 'superAdmin', 'admin')
        )
        OR EXISTS (
            SELECT 1 FROM private.admin_users
            WHERE user_id = (auth.jwt() ->> 'sub')
        )
    );
$$;
