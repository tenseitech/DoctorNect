-- PROPOSED (do not apply): Supabase RLS + schema hooks for in-app inbox only.
-- Base in_app_notifications + policies: db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql,
--   enhanced policies: db/migrations/20261021000004_phase_e2_support_and_notifications.sql
-- Ambulance-related RLS and table changes moved to db/proposed/later/20261103000016_later_ambulance_notifications_policies.sql
--   (not needed while AMBULANCE_ENABLED is off; policies there are incomplete: drivers cannot see unassigned
--   requests; patients cannot cancel).

-- ---------------------------------------------------------------------------
-- In-app notifications: extend EXISTING public.in_app_notifications (recipient_uid, is_read, type, …)
-- Client maps AppNotification to these columns; do not introduce a second table.
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_app_notifications
    ADD COLUMN IF NOT EXISTS category TEXT,
    ADD COLUMN IF NOT EXISTS deep_link TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_in_app_notifications_recipient_created
    ON public.in_app_notifications (recipient_uid, created_at DESC);

DROP POLICY IF EXISTS "notifications_select" ON public.in_app_notifications;
CREATE POLICY "notifications_select" ON public.in_app_notifications
    FOR SELECT TO authenticated
    USING (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    );

-- Recipients may only mark notifications read/unread (not arbitrary column rewrites).
DROP POLICY IF EXISTS "notifications_update" ON public.in_app_notifications;
CREATE POLICY "notifications_update" ON public.in_app_notifications
    FOR UPDATE TO authenticated
    USING (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    )
    WITH CHECK (
        (recipient_uid = (auth.jwt() ->> 'sub'))
        OR (recipient_uid = (
            SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub')
        ))
        OR private.is_super_admin()
    );

DROP TRIGGER IF EXISTS trg_in_app_notifications_recipient_read_only ON public.in_app_notifications;

CREATE OR REPLACE FUNCTION private.in_app_notifications_enforce_recipient_read_only()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sub TEXT;
BEGIN
  IF COALESCE(private.is_super_admin(), FALSE) THEN
    RETURN NEW;
  END IF;

  -- SECURITY DEFINER: session JWT may still show role=authenticated; trust function owner.
  IF current_user IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  v_sub := NULLIF(auth.jwt() ->> 'sub', '');
  IF v_sub IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT (
      OLD.recipient_uid = v_sub
      OR OLD.recipient_uid = (SELECT u.id::text FROM public.users u WHERE u.firebase_uid = v_sub LIMIT 1)
  ) THEN
    RETURN NEW;
  END IF;

  IF (to_jsonb(NEW) - 'is_read' - 'read_at' - 'updated_at')
     IS DISTINCT FROM (to_jsonb(OLD) - 'is_read' - 'read_at' - 'updated_at') THEN
    RAISE EXCEPTION 'FORBIDDEN: recipient may only change is_read, read_at, updated_at'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_in_app_notifications_recipient_read_only
  BEFORE UPDATE ON public.in_app_notifications
  FOR EACH ROW
  EXECUTE FUNCTION private.in_app_notifications_enforce_recipient_read_only();

-- Alternative hardening: column-level GRANT (revoke broad UPDATE, grant only read columns).
-- Uncomment after confirming no client path needs to patch title/body as the recipient.
-- REVOKE UPDATE ON public.in_app_notifications FROM authenticated;
-- GRANT UPDATE (is_read, read_at, updated_at) ON public.in_app_notifications TO authenticated;

-- Inserts remain server-only (FCN/outbox/triggers); no client INSERT policy added here.
