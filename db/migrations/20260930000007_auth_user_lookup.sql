-- ============================================================================
-- DoctorNect Platform — Secure Auth User Lookup for Edge Functions
-- File: supabase/migrations/20260930000007_auth_user_lookup.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.find_auth_user(
    p_phone TEXT
)
RETURNS TABLE (
    id UUID,
    email TEXT,
    phone TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, pg_temp
AS $$
    -- Phone comparison normalises to right 10 digits only.
    -- Strict phone-only matching prevents email-based account hijack.
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

REVOKE ALL ON FUNCTION public.find_auth_user(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_auth_user(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_auth_user(TEXT) TO service_role;
