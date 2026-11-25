-- DoctorNect Migration: 20261125000001_promoted_ads_guard_amount_paid.sql
-- Description: Follow-up to 20261124000001. A client INSERT could still set amount_paid (the
-- column defaults to 300.00 and the INSERT branch of the guard did not reset it), so a draft
-- could claim an arbitrary "paid" amount in admin views. Client inserts now force amount_paid = 0;
-- the backend sets the real amount on payment activation (service_role).
-- Idempotent (CREATE OR REPLACE); PG17 (Supabase) and PG18 (RDS) compatible.

CREATE OR REPLACE FUNCTION private.trg_promoted_ads_client_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.status := 'draft';
        NEW.payment_status := 'pending';
        NEW.razorpay_order_id := NULL;
        NEW.razorpay_payment_id := NULL;
        NEW.amount_paid := 0;
        NEW.start_time := NULL;
        NEW.end_time := NULL;
        NEW.impressions := 0;
        NEW.clicks := 0;
        NEW.rejection_reason := NULL;
        RETURN NEW;
    END IF;

    IF OLD.status NOT IN ('draft', 'pending_payment', 'rejected') THEN
        RAISE EXCEPTION 'FORBIDDEN: promoted ad in status % cannot be modified by the client', OLD.status
            USING ERRCODE = '42501';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'draft' THEN
        RAISE EXCEPTION 'FORBIDDEN: client cannot set promoted ad status to %', NEW.status
            USING ERRCODE = '42501';
    END IF;
    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NEW.payment_status <> 'pending' THEN
        RAISE EXCEPTION 'FORBIDDEN: client cannot set payment_status to %', NEW.payment_status
            USING ERRCODE = '42501';
    END IF;

    NEW.provider_id := OLD.provider_id;
    NEW.provider_type := OLD.provider_type;
    NEW.razorpay_order_id := OLD.razorpay_order_id;
    NEW.razorpay_payment_id := OLD.razorpay_payment_id;
    NEW.amount_paid := OLD.amount_paid;
    NEW.start_time := OLD.start_time;
    NEW.end_time := OLD.end_time;
    NEW.impressions := OLD.impressions;
    NEW.clicks := OLD.clicks;
    NEW.rejection_reason := OLD.rejection_reason;
    IF OLD.status = 'pending_payment' THEN
        NEW.duration_hours := OLD.duration_hours;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.trg_promoted_ads_client_guard() FROM PUBLIC;

-- The promoted_ads policies from 20261124000001 called public.is_super_admin(text), which
-- authenticated cannot EXECUTE (revoked by 20261115000001), so every client INSERT/UPDATE/DELETE
-- on promoted_ads failed with "permission denied for function is_super_admin". Use the
-- private helper (EXECUTE granted to authenticated; derives the caller from the JWT itself).
DROP POLICY IF EXISTS "promoted_ads_insert" ON public.promoted_ads;
DROP POLICY IF EXISTS "promoted_ads_update" ON public.promoted_ads;
DROP POLICY IF EXISTS "promoted_ads_delete" ON public.promoted_ads;

CREATE POLICY "promoted_ads_insert" ON public.promoted_ads
    FOR INSERT TO authenticated
    WITH CHECK (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR private.is_super_admin()
    );

CREATE POLICY "promoted_ads_update" ON public.promoted_ads
    FOR UPDATE TO authenticated
    USING (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR private.is_super_admin()
    );

CREATE POLICY "promoted_ads_delete" ON public.promoted_ads
    FOR DELETE TO authenticated
    USING (
        private.is_super_admin()
        OR (
            status IN ('draft', 'rejected')
            AND payment_status <> 'verified'
            AND (
                provider_id = (auth.jwt() ->> 'sub')
                OR provider_id = private.current_profile_id()
            )
        )
    );
