-- ==============================================================================
-- Rollback Migration: 20261025000001_least_privilege_grants_and_rls_rollback.sql
-- Description: Reverts changes made by 20261025000001_least_privilege_grants_and_rls.sql.
-- Restores previous view definitions and drops deny policies.
-- ==============================================================================

-- 1. Drop explicit deny policies on internal tables
DROP POLICY IF EXISTS deny_all_abuse_rate_limits ON public.abuse_rate_limits;
DROP POLICY IF EXISTS deny_all_ambulance_locations ON public.ambulance_locations;
DROP POLICY IF EXISTS deny_all_ambulance_trip_contacts ON public.ambulance_trip_contacts;
DROP POLICY IF EXISTS deny_all_otp_challenges ON public.otp_challenges;

-- 2. Restore previous patient_safe view definition (security_invoker = false)
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
FROM public.patients;

ALTER VIEW public.patient_safe OWNER TO postgres;
REVOKE ALL ON public.patient_safe FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.patient_safe TO authenticated, service_role;

-- 3. Restore previous provider insert policies
DROP POLICY IF EXISTS doctors_insert ON public.doctors;
CREATE POLICY doctors_insert ON public.doctors
  FOR INSERT TO authenticated
  WITH CHECK ((owner_uid = (auth.jwt() ->> 'sub')) OR private.is_super_admin());

DROP POLICY IF EXISTS medical_stores_insert ON public.medical_stores;
CREATE POLICY medical_stores_insert ON public.medical_stores
  FOR INSERT TO authenticated
  WITH CHECK ((owner_uid = (auth.jwt() ->> 'sub')) OR private.is_super_admin());

DROP POLICY IF EXISTS labs_insert ON public.labs;
CREATE POLICY labs_insert ON public.labs
  FOR INSERT TO authenticated
  WITH CHECK ((owner_uid = (auth.jwt() ->> 'sub')) OR private.is_super_admin());

DROP POLICY IF EXISTS ambulances_insert ON public.ambulances;
CREATE POLICY ambulances_insert ON public.ambulances
  FOR INSERT TO authenticated
  WITH CHECK ((auth_uid = (auth.jwt() ->> 'sub')) OR private.is_super_admin());
