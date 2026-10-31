-- Idempotent re-apply of review_public RLS policies (fixes dry-run 42710 when 000008 partially applied).

DROP POLICY IF EXISTS "review_public_select" ON public.review_public;
DROP POLICY IF EXISTS "review_public_select_authenticated" ON public.review_public;
DROP POLICY IF EXISTS "review_public_anon_select" ON public.review_public;

CREATE POLICY "review_public_select_authenticated"
    ON public.review_public
    FOR SELECT
    TO authenticated
    USING (true);

-- Anon cannot SELECT public.doctors; doctor_directory is the public discovery surface (verified, non-deactivated).
CREATE POLICY "review_public_anon_select"
    ON public.review_public
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1
            FROM public.doctor_directory dd
            WHERE dd.doctor_id = review_public.doctor_id
        )
    );

DROP POLICY IF EXISTS "review_public_deny_client_write" ON public.review_public;
CREATE POLICY "review_public_deny_client_write"
    ON public.review_public
    FOR ALL
    TO authenticated
    USING (FALSE)
    WITH CHECK (FALSE);
