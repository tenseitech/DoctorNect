-- Migration: 20261103000008_staging_anon_security_cleanup.sql
-- Description: Harden anonymous (PostgREST `anon`) surface for Supabase staging; idempotent and safe on
--              plain AWS RDS where roles `anon`/`authenticated` and extension `plpgsql_check` may be absent.
--
-- review_public: Flutter reads via Supabase PostgREST (SupabaseReviewRepository), not a separate gateway-only
--               API. Staging uses Firebase third-party accessToken; production uses the API gateway with minted
--               PostgREST JWTs. Anonymous discovery keeps GRANT SELECT + explicit RLS for verified doctors only.
--
-- doctor_directory: security_invoker=false is intentional (definer view owned by postgres). The WHERE clause
--                   is the authorization boundary for unauthenticated discovery; RLS on public.doctors does not
--                   apply inside this view. Do not flip to security_invoker without re-auditing anon exposure.
--
-- RDS authorization model (no Supabase Auth for clients): see docs/db/RDS_AUTHORIZATION.md

-- ============================================================================
-- 1. Remove staging-only static analysis extension
-- ============================================================================
DROP EXTENSION IF EXISTS plpgsql_check;

-- ============================================================================
-- 2. Document doctor_directory definer semantics
-- ============================================================================
COMMENT ON VIEW public.doctor_directory IS
'Public doctor discovery projection (SECURITY DEFINER / security_invoker=false, owner postgres). '
'Rows are limited to verified=true AND deactivated=false so suspended or unverified doctors never appear '
'to anonymous or authenticated directory readers. PII (mobile, email, council numbers, owner_uid) is omitted '
'from the SELECT list by design; base-table RLS is not evaluated under this view definition.';

-- ============================================================================
-- 3. review_public: split anon vs authenticated SELECT policies
-- ============================================================================
DROP POLICY IF EXISTS "review_public_select" ON public.review_public;

CREATE POLICY "review_public_select_authenticated"
    ON public.review_public
    FOR SELECT
    TO authenticated
    USING (TRUE);

-- Anon may only read reviews for doctors who are visible in the public directory (verified, not deactivated).
CREATE POLICY "review_public_anon_select"
    ON public.review_public
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1
            FROM public.doctors d
            WHERE d.doctor_id = review_public.doctor_id
              AND d.verified IS TRUE
              AND d.deactivated IS FALSE
        )
    );

-- Writes remain trigger/server maintained (existing deny policy retained if present).
DROP POLICY IF EXISTS "review_public_deny_client_write" ON public.review_public;
CREATE POLICY "review_public_deny_client_write"
    ON public.review_public
    FOR ALL
    TO authenticated
    USING (FALSE)
    WITH CHECK (FALSE);

-- ============================================================================
-- 4. Anonymous grants: least privilege (Supabase roles only)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        RAISE NOTICE 'Role anon not present — skipping anon grant hardening (expected on plain RDS apply).';
        RETURN;
    END IF;

    -- Full revoke on promoted_ads (replaces prior column-level anon SELECT from 20261030000001).
    REVOKE ALL ON TABLE public.promoted_ads FROM anon;

    -- Idempotent allowlist (tables only; RLS enforces row/key rules).
    GRANT USAGE ON SCHEMA public TO anon;
    GRANT SELECT ON public.doctor_directory TO anon;
    GRANT SELECT ON public.lab_catalog_tests TO anon;
    GRANT SELECT ON public.system_config TO anon;
    GRANT SELECT ON public.review_public TO anon;

    -- No RPC surface for anonymous callers.
    REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon;
END
$$;
