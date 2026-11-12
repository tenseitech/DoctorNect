-- 20261021000006_db_hardening.sql
-- Database hardening:
-- 1. Harden public.is_super_admin(text) to have search_path = '' and fully qualified public.super_admins
-- 2. Revoke execute on trigger-only functions from authenticated and anon
-- 3. Restrict expire_stale_ambulance_broadcasts to service_role only
-- 4. Harden find_auth_user search_path to '' and preserve service_role execution only
-- 5. Allow razorpay_orders.user_uid to be NULL for PII minimization on account deletion

-- 1. Harden public.is_super_admin(text)
CREATE OR REPLACE FUNCTION public.is_super_admin(check_uid text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

REVOKE ALL ON FUNCTION public.is_super_admin(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin(text) TO authenticated, service_role;

-- 2. Revoke execute on trigger functions from authenticated and anon
REVOKE EXECUTE ON FUNCTION public.fn_sync_review_aggregates() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_sync_review_helpful_count() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_touch_doctor_directory() FROM authenticated, anon, PUBLIC;

-- 3. Restrict expire_stale_ambulance_broadcasts to service_role only
REVOKE EXECUTE ON FUNCTION public.expire_stale_ambulance_broadcasts() FROM authenticated, anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_stale_ambulance_broadcasts() TO service_role;

-- 4. Harden find_auth_user search_path to ''
CREATE OR REPLACE FUNCTION public.find_auth_user(p_phone text)
RETURNS TABLE(id uuid, email text, phone text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        u.id,
        u.email::TEXT,
        u.phone::TEXT
    FROM auth.users u
    WHERE
        p_phone IS NOT NULL
        AND p_phone <> ''
        AND right(regexp_replace(COALESCE(u.phone, ''), '\D', '', 'g'), 10)
            = right(regexp_replace(p_phone, '\D', '', 'g'), 10)
        AND length(right(regexp_replace(COALESCE(u.phone, ''), '\D', '', 'g'), 10)) = 10
    ORDER BY u.created_at
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_auth_user(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_auth_user(text) TO service_role;

-- 5. Anonymization support on account deletion
ALTER TABLE public.razorpay_orders ALTER COLUMN user_uid DROP NOT NULL;
