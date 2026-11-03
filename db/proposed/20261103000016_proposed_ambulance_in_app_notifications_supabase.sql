-- PROPOSED (do not apply): replace client Firestore for ambulance + in-app notifications.
-- Repository targets: ambulance_repository.dart, in_app_notification_service.dart

-- ---------------------------------------------------------------------------
-- In-app notifications (Firestore: in_app_notifications)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.in_app_notifications (
    notification_id TEXT PRIMARY KEY,
    owner_uid TEXT NOT NULL REFERENCES public.users(uid) ON DELETE CASCADE,
    owner_profile_id TEXT,
    role TEXT NOT NULL CHECK (role IN ('patient', 'doctor', 'lab', 'medicalStore', 'ambulance')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    category TEXT,
    deep_link TEXT,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_in_app_notifications_owner_uid_created
    ON public.in_app_notifications (owner_uid, created_at DESC);

ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS in_app_notifications_select ON public.in_app_notifications;
CREATE POLICY in_app_notifications_select ON public.in_app_notifications
    FOR SELECT TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS in_app_notifications_update ON public.in_app_notifications;
CREATE POLICY in_app_notifications_update ON public.in_app_notifications
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub'))
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub'));

-- Inserts server-only (notification_outbox / triggers) — no client INSERT policy.

-- ---------------------------------------------------------------------------
-- Ambulance broadcasts / requests (Firestore: ambulance_broadcasts, ambulance_requests)
-- Extend existing public.ambulance_* tables if present; add missing columns only.
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

-- RLS: patient creates request; assigned ambulance updates; verified not required for self ambulance profile row
DROP POLICY IF EXISTS ambulance_requests_patient_insert ON public.ambulance_requests;
CREATE POLICY ambulance_requests_patient_insert ON public.ambulance_requests
    FOR INSERT TO authenticated
    WITH CHECK (patient_id = private.current_profile_id());

DROP POLICY IF EXISTS ambulance_requests_select ON public.ambulance_requests;
CREATE POLICY ambulance_requests_select ON public.ambulance_requests
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS ambulance_requests_update ON public.ambulance_requests;
CREATE POLICY ambulance_requests_update ON public.ambulance_requests
    FOR UPDATE TO authenticated
    USING (
        ambulance_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
    )
    WITH CHECK (
        ambulance_id = private.current_profile_id()
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
    );

-- Flutter: AmbulanceRepository → SupabaseAmbulanceRepository (PostgREST on ambulance_requests/broadcasts/ambulances)
-- Flutter: InAppNotificationService → poll/stream in_app_notifications WHERE owner_uid = jwt.sub
