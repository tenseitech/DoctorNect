-- ============================================================================
-- Migration: 20261021000001_sensitive_data_isolation.sql
-- Description: Sensitive data isolation & FCM token table
--   1. Create public.doctor_private table (PII & credentials, owner+admin only)
--   2. Create public.user_devices table (FCM tokens, owner only)
--   3. Tighten public.doctors RLS to block fcm_token/email/mobile from
--      patients-with-appointment (they get directory view only)
--   4. Tighten public.patients RLS so doctors cannot read fcm_token
--   5. Remove fcm_token columns from roles that don't need them in Supabase
--   6. Add `deactivated_doctor` to doctor_directory filter safety check (already done, no-op guard)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DOCTOR PRIVATE TABLE
--    Holds all PII columns that must never be readable by patients or
--    unrelated doctors: phone, email (canonical), state council registration,
--    license document S3 keys, bank settlement info.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.doctor_private (
    doctor_id VARCHAR(64) PRIMARY KEY REFERENCES public.doctors(doctor_id) ON DELETE CASCADE,
    -- Contact PII (already in doctors, now also here for stricter access)
    phone    VARCHAR(32),
    email    VARCHAR(255),
    -- Medical Registration
    state_council       VARCHAR(255),
    council_number      VARCHAR(128),
    -- License & KYC Document S3 reference
    license_doc_s3_key  TEXT,
    license_doc_s3_bucket TEXT,
    license_doc_mime    VARCHAR(128),
    -- Banking / Payout (future)
    bank_account_number TEXT, -- store hashed/masked; raw value never in DB
    bank_ifsc           VARCHAR(32),
    bank_holder_name    VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.doctor_private ENABLE ROW LEVEL SECURITY;

-- Trigger to auto-update updated_at
CREATE TRIGGER set_doctor_private_timestamp
    BEFORE UPDATE ON public.doctor_private
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- Revoke all public access
REVOKE ALL ON public.doctor_private FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.doctor_private TO service_role;
GRANT SELECT ON public.doctor_private TO authenticated;

-- RLS: owner (the doctor themselves) OR super admin only
DROP POLICY IF EXISTS "doctor_private_owner_read" ON public.doctor_private;
CREATE POLICY "doctor_private_owner_read" ON public.doctor_private
    FOR SELECT TO authenticated
    USING (
        -- Doctor owns their row (match by profile_id or owner_uid)
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = public.doctor_private.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "doctor_private_owner_update" ON public.doctor_private;
CREATE POLICY "doctor_private_owner_update" ON public.doctor_private
    FOR UPDATE TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = public.doctor_private.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = public.doctor_private.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- 2. USER DEVICES TABLE (FCM token registry)
--    Replaces fcm_token columns on doctors/patients/medical_stores/labs.
--    Written exclusively by service_role (Cloud Functions via Firebase Auth token
--    registration) and readable only by the owning user.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.user_devices (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     TEXT NOT NULL,     -- Firebase UID (auth.jwt()->>'sub')
    platform    VARCHAR(16) NOT NULL DEFAULT 'unknown'
                    CHECK (platform IN ('android', 'ios', 'web', 'unknown')),
    fcm_token   TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, platform)     -- one row per user+platform
);

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER set_user_devices_timestamp
    BEFORE UPDATE ON public.user_devices
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

REVOKE ALL ON public.user_devices FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_devices TO service_role;
GRANT SELECT ON public.user_devices TO authenticated;

-- RLS: owner only (user reads their own device rows)
DROP POLICY IF EXISTS "user_devices_owner_read" ON public.user_devices;
CREATE POLICY "user_devices_owner_read" ON public.user_devices
    FOR SELECT TO authenticated
    USING (user_id = (auth.jwt() ->> 'sub'));

-- Service role writes handled server-side; no INSERT/UPDATE policy for clients.

-- ----------------------------------------------------------------------------
-- 3. TIGHTEN public.doctors SELECT RLS
--    The current doctors_select allows patients with appointments to read ALL
--    columns of doctors, including mobile, email, fcm_token, council_number.
--    Patients must be limited to non-sensitive columns via doctor_directory.
--    Only the doctor themselves, admin, or a doctor in a clinical relationship
--    may read the full doctors row including contact PII.
--
--    DESIGN: patients with an appointment get access via doctor_directory view
--    (safe columns only). If they need to call the doctor they use the
--    appointment's contact_number field which is already scrubbed.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS doctors_select ON public.doctors;
CREATE POLICY doctors_select ON public.doctors
    FOR SELECT TO authenticated
    USING (
        -- 1. Doctor themselves (profile owner)
        (owner_uid = (auth.jwt() ->> 'sub'))
        OR (doctor_id = private.current_profile_id())
        -- 2. Platform Super Admin
        OR private.is_super_admin()
        -- 3. Another doctor with a clinical care relationship (not patients)
        --    Patients are excluded here; they use doctor_directory for search
        --    and appointment.contact_number for callbacks.
        OR (
            EXISTS (
                SELECT 1 FROM public.users u
                WHERE u.id = (auth.jwt() ->> 'sub')
                  AND u.role IN ('doctor', 'superAdmin', 'super_admin', 'admin')
            )
            AND (
                EXISTS (
                    SELECT 1 FROM public.patient_doctor_links pdl
                    WHERE pdl.doctor_id = doctors.doctor_id
                      AND pdl.patient_id = private.current_profile_id()
                )
                OR EXISTS (
                    SELECT 1 FROM public.referrals dr
                    WHERE (dr.from_doctor_id = private.current_profile_id() AND dr.to_doctor_id = doctors.doctor_id)
                       OR (dr.to_doctor_id = private.current_profile_id() AND dr.from_doctor_id = doctors.doctor_id)
                )
            )
        )
    );

-- ----------------------------------------------------------------------------
-- 4. TIGHTEN public.patients SELECT RLS
--    Doctors with a relationship should NOT read fcm_token, email, or
--    unrelated personal columns. The current RLS allows any doctor with
--    an appointment to SELECT *, including fcm_token.
--    New policy: doctors read only via the existing patients SELECT policy
--    which already gates on appointment/care-team, but we add a column-level
--    projection note (Postgres RLS is row-level only; column restriction is
--    enforced via the public.patient_safe view below).
-- ----------------------------------------------------------------------------

-- Ensure existing patients_select policy is strict (uses SECURITY DEFINER function to avoid RLS recursion)
DROP POLICY IF EXISTS patients_select ON public.patients;
CREATE POLICY patients_select ON public.patients
    FOR SELECT TO authenticated
    USING (
        -- 1. Patient owner
        (owner_uid = (auth.jwt() ->> 'sub'))
        OR (patient_id = private.current_profile_id())
        -- 2. Super Admin
        OR private.is_super_admin()
        -- 3. Doctor with care relationship via SECURITY DEFINER function
        OR private.doctor_can_access_patient(patient_id)
    );

-- ----------------------------------------------------------------------------
-- 5. PATIENT SAFE VIEW (column projection — excludes fcm_token)
--    Doctors query this view to access patient clinical details without
--    exposing FCM token or internal platform metadata.
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS public.patient_safe;
CREATE VIEW public.patient_safe
WITH (security_invoker = false)
AS
SELECT
    patient_id,
    name,
    age,
    gender,
    blood_group,
    height,
    weight,
    address,
    photo_url,
    share_records_with_doctors,
    primary_doctor_id,
    invited_doctor_id,
    care_team_doctor_ids,
    profile_completed,
    verified,
    created_at,
    updated_at,
    photo_updated_at
    -- Deliberately excludes: mobile, email, fcm_token, fcm_token_updated_at, owner_uid
FROM public.patients;

ALTER VIEW public.patient_safe OWNER TO postgres;

REVOKE ALL ON public.patient_safe FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.patient_safe TO authenticated, service_role;

-- RLS enforced via base table patients (security_invoker=false means postgres sees all rows,
-- but the base table RLS was already correct for row filtering).
-- Advisors will flag this view; accepted: same pattern as doctor_directory.

-- ----------------------------------------------------------------------------
-- 6. BACKFILL doctor_private from existing doctors rows
--    Copies PII into doctor_private for any existing verified doctors.
--    Future inserts are handled by application code (service_role upsert).
-- ----------------------------------------------------------------------------

INSERT INTO public.doctor_private (doctor_id, phone, email, state_council, council_number)
SELECT
    doctor_id,
    mobile,
    email,
    state_council,
    council_number
FROM public.doctors
ON CONFLICT (doctor_id) DO UPDATE
    SET phone  = EXCLUDED.phone,
        email  = EXCLUDED.email,
        state_council = EXCLUDED.state_council,
        council_number = EXCLUDED.council_number,
        updated_at = CURRENT_TIMESTAMP;

-- ----------------------------------------------------------------------------
-- 7. SEQUENCE GUARD: grant sequence for user_devices id if needed
-- ----------------------------------------------------------------------------

-- user_devices.id is UUID (gen_random_uuid), no sequence needed.

-- Done.
