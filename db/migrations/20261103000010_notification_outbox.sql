-- Transactional outbox for FCM notification dispatch (RDS + Supabase Postgres — same triggers).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.notification_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dedupe_key TEXT NOT NULL UNIQUE,
    table_name TEXT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'dead')),
    attempts INT NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS notification_outbox_pending_idx
    ON public.notification_outbox (status, created_at)
    WHERE status IN ('pending', 'processing');

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notification_outbox_service_all" ON public.notification_outbox;
CREATE POLICY "notification_outbox_service_all"
    ON public.notification_outbox
    FOR ALL
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

REVOKE ALL ON public.notification_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_outbox TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_entity_id TEXT;
    v_event_time TEXT;
    v_dedupe_key TEXT;
    v_payload JSONB;
BEGIN
    v_entity_id := COALESCE(
        to_jsonb(NEW)->>'appointment_id',
        to_jsonb(NEW)->>'referral_id',
        to_jsonb(NEW)->>'delivery_id',
        to_jsonb(NEW)->>'booking_id',
        to_jsonb(NEW)->>'broadcast_id',
        to_jsonb(NEW)->>'id',
        'event'
    );
    v_event_time := COALESCE(to_jsonb(NEW)->>'updated_at', to_jsonb(NEW)->>'created_at', NOW()::TEXT);
    v_dedupe_key := encode(digest(TG_TABLE_NAME || ':' || TG_OP || ':' || v_entity_id || ':' || v_event_time, 'sha256'), 'hex');
    v_payload := jsonb_build_object(
        'type', TG_OP,
        'table', TG_TABLE_NAME,
        'record', to_jsonb(NEW),
        'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
    );

    INSERT INTO public.notification_outbox (dedupe_key, table_name, event_type, payload)
    VALUES (v_dedupe_key, TG_TABLE_NAME, TG_OP, v_payload)
    ON CONFLICT (dedupe_key) DO NOTHING;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_notification_outbox() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notification_outbox_appointments ON public.appointments;
CREATE TRIGGER trg_notification_outbox_appointments
    AFTER INSERT OR UPDATE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_notification_outbox();

DROP TRIGGER IF EXISTS trg_notification_outbox_referrals ON public.referrals;
CREATE TRIGGER trg_notification_outbox_referrals
    AFTER INSERT ON public.referrals
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_notification_outbox();

DROP TRIGGER IF EXISTS trg_notification_outbox_pharmacy ON public.pharmacy_deliveries;
CREATE TRIGGER trg_notification_outbox_pharmacy
    AFTER INSERT OR UPDATE ON public.pharmacy_deliveries
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_notification_outbox();

DROP TRIGGER IF EXISTS trg_notification_outbox_lab ON public.lab_bookings;
CREATE TRIGGER trg_notification_outbox_lab
    AFTER INSERT OR UPDATE ON public.lab_bookings
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_notification_outbox();

DROP TRIGGER IF EXISTS trg_notification_outbox_ambulance ON public.ambulance_broadcasts;
CREATE TRIGGER trg_notification_outbox_ambulance
    AFTER UPDATE ON public.ambulance_broadcasts
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_notification_outbox();
