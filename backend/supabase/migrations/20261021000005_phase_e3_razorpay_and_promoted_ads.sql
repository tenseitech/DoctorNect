-- Migration: 20261021000005_phase_e3_razorpay_and_promoted_ads.sql
-- Description: Phase E.3 schema for Razorpay Monetization & Promoted Ads
-- Enforces 100% RLS, tenant isolation, and idempotent webhook tracking.

-- 1. Upgrade public.promoted_ads with Phase E fields and constraints
ALTER TABLE public.promoted_ads
    ADD COLUMN IF NOT EXISTS impressions INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS clicks INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS image_s3_key TEXT,
    ADD COLUMN IF NOT EXISTS image_s3_bucket TEXT;

-- Update status check constraint to support 'pending_approval' and 'paused'
ALTER TABLE public.promoted_ads DROP CONSTRAINT IF EXISTS promoted_ads_status_check;
ALTER TABLE public.promoted_ads ADD CONSTRAINT promoted_ads_status_check
    CHECK (status IN ('draft', 'pending_payment', 'pending_approval', 'active', 'expired', 'rejected', 'paused'));

-- Refresh RLS policies on promoted_ads
DROP POLICY IF EXISTS "promoted_ads_select" ON public.promoted_ads;
CREATE POLICY "promoted_ads_select" ON public.promoted_ads
    FOR SELECT TO authenticated
    USING (
        status = 'active'
        OR provider_id = (auth.jwt()->>'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt()->>'sub')
    );

DROP POLICY IF EXISTS "promoted_ads_write" ON public.promoted_ads;
CREATE POLICY "promoted_ads_write" ON public.promoted_ads
    FOR ALL TO authenticated
    USING (
        provider_id = (auth.jwt()->>'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt()->>'sub')
    )
    WITH CHECK (
        provider_id = (auth.jwt()->>'sub')
        OR provider_id = private.current_profile_id()
        OR public.is_super_admin(auth.jwt()->>'sub')
    );

-- 2. Table: public.razorpay_orders
CREATE TABLE IF NOT EXISTS public.razorpay_orders (
    order_id VARCHAR(128) PRIMARY KEY, -- e.g. order_EKfWjp82aTFCbA
    user_uid TEXT NOT NULL,
    ad_id VARCHAR(64) REFERENCES public.promoted_ads(ad_id) ON DELETE SET NULL,
    amount_paise BIGINT NOT NULL CHECK (amount_paise > 0),
    currency VARCHAR(16) NOT NULL DEFAULT 'INR',
    receipt VARCHAR(128) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'created',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_razorpay_orders_user ON public.razorpay_orders(user_uid);
CREATE INDEX IF NOT EXISTS idx_razorpay_orders_ad ON public.razorpay_orders(ad_id);

ALTER TABLE public.razorpay_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.razorpay_orders FORCE ROW LEVEL SECURITY;

CREATE POLICY razorpay_orders_select ON public.razorpay_orders
    FOR SELECT TO authenticated
    USING (
        user_uid = (auth.jwt()->>'sub')
        OR public.is_super_admin(auth.jwt()->>'sub')
    );

CREATE POLICY razorpay_orders_insert ON public.razorpay_orders
    FOR INSERT TO authenticated
    WITH CHECK (
        user_uid = (auth.jwt()->>'sub')
        OR public.is_super_admin(auth.jwt()->>'sub')
    );

CREATE POLICY razorpay_orders_update ON public.razorpay_orders
    FOR UPDATE TO authenticated
    USING (public.is_super_admin(auth.jwt()->>'sub'))
    WITH CHECK (public.is_super_admin(auth.jwt()->>'sub'));

-- 3. Table: public.razorpay_payments
CREATE TABLE IF NOT EXISTS public.razorpay_payments (
    payment_id VARCHAR(128) PRIMARY KEY, -- e.g. pay_29QQoUBcxNqdf0
    order_id VARCHAR(128) NOT NULL REFERENCES public.razorpay_orders(order_id) ON DELETE CASCADE,
    signature TEXT,
    amount_paise BIGINT NOT NULL,
    currency VARCHAR(16) NOT NULL DEFAULT 'INR',
    status VARCHAR(32) NOT NULL,
    method VARCHAR(32),
    error_code TEXT,
    error_description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_razorpay_payments_order ON public.razorpay_payments(order_id);

ALTER TABLE public.razorpay_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.razorpay_payments FORCE ROW LEVEL SECURITY;

CREATE POLICY razorpay_payments_select ON public.razorpay_payments
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.razorpay_orders o
            WHERE o.order_id = razorpay_payments.order_id
            AND (o.user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub'))
        )
    );

-- Note: No client insert/update/delete policy on razorpay_payments. Only service_role can write.

-- 4. Table: public.razorpay_webhook_events (idempotency ledger)
CREATE TABLE IF NOT EXISTS public.razorpay_webhook_events (
    event_id VARCHAR(128) PRIMARY KEY, -- Unique Razorpay webhook delivery ID
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_razorpay_webhook_events_processed ON public.razorpay_webhook_events(processed_at DESC);

ALTER TABLE public.razorpay_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.razorpay_webhook_events FORCE ROW LEVEL SECURITY;

CREATE POLICY razorpay_webhook_events_admin_select ON public.razorpay_webhook_events
    FOR SELECT TO authenticated
    USING (public.is_super_admin(auth.jwt()->>'sub'));

-- Note: No client insert/update/delete policy on razorpay_webhook_events. Only service_role can write.
