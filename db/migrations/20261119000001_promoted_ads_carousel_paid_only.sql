-- Carousel: non-owners must not SELECT unpaid ads marketed as active (payment_status still pending).
-- Owners and super-admins keep full visibility per promoted_ads_select intent.

DROP POLICY IF EXISTS "promoted_ads_select" ON public.promoted_ads;
CREATE POLICY "promoted_ads_select" ON public.promoted_ads
    FOR SELECT TO authenticated
    USING (
        provider_id = (auth.jwt()->>'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt()->>'sub')
        OR (status = 'active' AND payment_status IS DISTINCT FROM 'pending')
    );