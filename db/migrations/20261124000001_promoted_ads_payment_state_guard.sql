-- DoctorNect Migration: 20261124000001_promoted_ads_payment_state_guard.sql
-- Description: SECURITY FIX (payment bypass). The "promoted_ads_write" policy is FOR ALL with an
-- owner-only predicate, so an ad owner could PATCH status='active' / payment_status='verified'
-- via PostgREST and get a banner shown to every user without paying or admin approval.
-- This trigger makes payment/approval/lifecycle columns server-owned: only service_role,
-- super-admin, or a backend/migration session (pg_cron, SECURITY DEFINER owner) may change them.
-- Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS. Safe on Supabase (PG17) and RDS (PG18).

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.trg_promoted_ads_client_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    -- Trusted writers: backend service role, super admin, or non-PostgREST session (cron / migrations).
    IF (auth.jwt() ->> 'role') = 'service_role'
       OR COALESCE(private.is_super_admin(), FALSE)
       OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
           AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- Clients may only create unpaid drafts; every server-owned column is reset.
        NEW.status := 'draft';
        NEW.payment_status := 'pending';
        NEW.razorpay_order_id := NULL;
        NEW.razorpay_payment_id := NULL;
        NEW.start_time := NULL;
        NEW.end_time := NULL;
        NEW.impressions := 0;
        NEW.clicks := 0;
        NEW.rejection_reason := NULL;
        RETURN NEW;
    END IF;

    -- UPDATE: once paid / under review / live, the owner can no longer edit the ad
    -- (prevents swapping approved creative and extending duration after payment).
    IF OLD.status NOT IN ('draft', 'pending_payment', 'rejected') THEN
        RAISE EXCEPTION 'FORBIDDEN: promoted ad in status % cannot be modified by the client', OLD.status
            USING ERRCODE = '42501';
    END IF;

    -- Owner may only reset a draft/pending/rejected ad back to an unpaid draft.
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'draft' THEN
        RAISE EXCEPTION 'FORBIDDEN: client cannot set promoted ad status to %', NEW.status
            USING ERRCODE = '42501';
    END IF;
    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NEW.payment_status <> 'pending' THEN
        RAISE EXCEPTION 'FORBIDDEN: client cannot set payment_status to %', NEW.payment_status
            USING ERRCODE = '42501';
    END IF;

    -- Server-owned columns are pinned to their previous values.
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
        -- Duration is bound to the Razorpay order; changing it requires a new order.
        NEW.duration_hours := OLD.duration_hours;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.trg_promoted_ads_client_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_promoted_ads_client_guard ON public.promoted_ads;
CREATE TRIGGER trg_promoted_ads_client_guard
    BEFORE INSERT OR UPDATE ON public.promoted_ads
    FOR EACH ROW EXECUTE FUNCTION private.trg_promoted_ads_client_guard();

-- Clients must never delete paid/live ads (refund/audit trail). Drafts may still be deleted.
DROP POLICY IF EXISTS "promoted_ads_write" ON public.promoted_ads;
DROP POLICY IF EXISTS "promoted_ads_insert" ON public.promoted_ads;
DROP POLICY IF EXISTS "promoted_ads_update" ON public.promoted_ads;
DROP POLICY IF EXISTS "promoted_ads_delete" ON public.promoted_ads;

CREATE POLICY "promoted_ads_insert" ON public.promoted_ads
    FOR INSERT TO authenticated
    WITH CHECK (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt() ->> 'sub')
    );

CREATE POLICY "promoted_ads_update" ON public.promoted_ads
    FOR UPDATE TO authenticated
    USING (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt() ->> 'sub')
    )
    WITH CHECK (
        provider_id = (auth.jwt() ->> 'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt() ->> 'sub')
    );

CREATE POLICY "promoted_ads_delete" ON public.promoted_ads
    FOR DELETE TO authenticated
    USING (
        public.is_super_admin(auth.jwt() ->> 'sub')
        OR (
            status IN ('draft', 'rejected')
            AND payment_status <> 'verified'
            AND (
                provider_id = (auth.jwt() ->> 'sub')
                OR provider_id = private.current_profile_id()
            )
        )
    );

-- Payment ledgers are server-written only (clients could previously INSERT razorpay_orders rows
-- with arbitrary order_id/amount via razorpay_orders_insert).
DO $$
BEGIN
    IF to_regclass('public.razorpay_orders') IS NOT NULL THEN
        DROP POLICY IF EXISTS razorpay_orders_insert ON public.razorpay_orders;
        DROP POLICY IF EXISTS razorpay_orders_update ON public.razorpay_orders;
        REVOKE INSERT, UPDATE, DELETE ON TABLE public.razorpay_orders FROM anon, authenticated;
    END IF;
    IF to_regclass('public.razorpay_payments') IS NOT NULL THEN
        REVOKE INSERT, UPDATE, DELETE ON TABLE public.razorpay_payments FROM anon, authenticated;
    END IF;
    IF to_regclass('public.razorpay_webhook_events') IS NOT NULL THEN
        REVOKE INSERT, UPDATE, DELETE ON TABLE public.razorpay_webhook_events FROM anon, authenticated;
    END IF;
END $$;
