-- Ensure pgcrypto is available for notification_outbox digest() on RDS and Supabase (extensions schema).
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
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

COMMIT;