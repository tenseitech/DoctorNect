-- PROPOSED (do not apply): Supabase RLS + schema hooks for in-app inbox and ambulance data
-- (replaces client Firestore where still referenced).
-- Base in_app_notifications + policies: db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql,
--   enhanced policies: db/migrations/20261021000004_phase_e2_support_and_notifications.sql
-- Base ambulance_requests RLS: db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql (amb_requests_*)

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

-- Inserts remain server-only (FCN/outbox/triggers); no client INSERT policy added here.

-- ---------------------------------------------------------------------------
-- Ambulance: optional legacy / app columns; RLS uses driver_id (FK to ambulances), not ambulance_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.ambulance_requests
    ADD COLUMN IF NOT EXISTS firestore_legacy_id TEXT,
    ADD COLUMN IF NOT EXISTS broadcast_id TEXT,
    ADD COLUMN IF NOT EXISTS patient_location JSONB,
    ADD COLUMN IF NOT EXISTS status TEXT;

ALTER TABLE public.ambulance_broadcasts
    ADD COLUMN IF NOT EXISTS firestore_legacy_id TEXT,
    ADD COLUMN IF NOT EXISTS payload JSONB,
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Deployed names: amb_requests_select, amb_requests_update (see consolidated migration)
DROP POLICY IF EXISTS "amb_requests_select" ON public.ambulance_requests;
CREATE POLICY "amb_requests_select" ON public.ambulance_requests
    FOR SELECT TO authenticated
    USING (
        driver_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_requests_update" ON public.ambulance_requests;
CREATE POLICY "amb_requests_update" ON public.ambulance_requests
    FOR UPDATE TO authenticated
    USING (driver_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (driver_id = private.current_profile_id() OR private.is_super_admin());

-- Flutter: AmbulanceRepository → PostgREST on ambulance_requests / ambulance_broadcasts / ambulances
-- Flutter: InAppNotificationService → Supabase select/update on in_app_notifications WHERE recipient_uid = jwt.sub
