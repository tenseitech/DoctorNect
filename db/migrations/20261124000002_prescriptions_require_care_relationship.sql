-- DoctorNect Migration: 20261124000002_prescriptions_require_care_relationship.sql
-- Description: SECURITY FIX (IDOR / record tampering).
--   * prescriptions_insert / prescriptions_update only checked "caller is a verified doctor and owns
--     doctor_id". Because permissive policies are OR-ed, any verified doctor could INSERT a
--     prescription for ANY patient_id directly via PostgREST (bypassing the relationship check that
--     create_prescription_atomic enforces) and inject records into a stranger's chart.
--   * prescriptions_write (FOR ALL) additionally allowed doctors to DELETE prescriptions
--     (medical record destruction). Only super-admin delete remains.
-- Writes now require private.doctor_has_relationship(patient_id) (active appointment, link,
-- or primary doctor) — the same predicate used elsewhere for doctor -> patient access.
-- Idempotent; safe on Supabase (PG17) and RDS (PG18).

DROP POLICY IF EXISTS "prescriptions_write" ON public.prescriptions;
DROP POLICY IF EXISTS "prescriptions_insert" ON public.prescriptions;
DROP POLICY IF EXISTS "prescriptions_update" ON public.prescriptions;

CREATE POLICY "prescriptions_insert" ON public.prescriptions
    FOR INSERT TO authenticated
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.doctor_has_relationship(patient_id))
        OR private.is_super_admin()
    );

CREATE POLICY "prescriptions_update" ON public.prescriptions
    FOR UPDATE TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        -- Re-targeting a prescription to another patient also requires a care relationship.
        (doctor_id = private.current_profile_id() AND private.doctor_has_relationship(patient_id))
        OR private.is_super_admin()
    );

REVOKE DELETE ON TABLE public.prescriptions FROM anon, authenticated;
