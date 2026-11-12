-- PROPOSED LATER (do not apply): Ambulance requests/broadcasts columns + RLS from the former 000016 combined migration.
-- NOT NEEDED while app AMBULANCE_ENABLED is false: Flutter ambulance flows are compile-time gated.
-- Known gaps if applied as-is: drivers cannot SELECT unassigned pending requests; patients cannot cancel via RLS.
-- Reconcile with db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql (amb_requests_*) before deploy.

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
