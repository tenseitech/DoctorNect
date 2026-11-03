-- STAGING ONLY — run inside a transaction after seeding fixture users/profiles.
-- Apply db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql first (manual).
-- Replace placeholder UIDs/profile IDs before execute.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Fixture map (edit to match staging seed):
-- patient_uid -> p_staging_patient
-- doctor_verified_uid -> d_staging_verified (doctors.verified=true)
-- doctor_unverified_uid -> d_staging_unverified (doctors.verified=false)
-- lab_verified_uid / lab_unverified_uid
-- pharmacy_verified_uid -> ms_staging_verified
-- ambulance_uid -> amb_staging_1

-- ---------------------------------------------------------------------------
-- PATIENT: can SELECT own appointment; can UPDATE cancel own
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-staging');
SET LOCAL role authenticated;
SELECT 'patient_appointments_select' AS probe, count(*) AS cnt
FROM public.appointments WHERE patient_id = 'p_staging_patient';

-- ---------------------------------------------------------------------------
-- VERIFIED DOCTOR: SELECT/UPDATE appointments where doctor_id = self (expect OK post-000014)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-doctor-verified-staging');
SET LOCAL role authenticated;
SELECT 'verified_doctor_appointments_select' AS probe, count(*) AS cnt
FROM public.appointments WHERE doctor_id = 'd_staging_verified';

-- ---------------------------------------------------------------------------
-- UNVERIFIED DOCTOR: SELECT appointments as doctor (expect 0 rows post-000014)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-doctor-unverified-staging');
SET LOCAL role authenticated;
SELECT 'unverified_doctor_appointments_select' AS probe, count(*) AS cnt
FROM public.appointments WHERE doctor_id = 'd_staging_unverified';

-- ---------------------------------------------------------------------------
-- UNVERIFIED DOCTOR: still SELECT own doctors row (onboarding)
-- ---------------------------------------------------------------------------
SELECT 'unverified_doctor_own_profile' AS probe, count(*) AS cnt
FROM public.doctors
WHERE doctor_id = 'd_staging_unverified';

-- ---------------------------------------------------------------------------
-- VERIFIED LAB: UPDATE lab_bookings (expect 1 row updated on seeded booking)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-verified-staging');
SET LOCAL role authenticated;
UPDATE public.lab_bookings
SET status = 'sample_collected'
WHERE lab_id = 'l_staging_verified' AND booking_id = 'lb_staging_1';

-- ---------------------------------------------------------------------------
-- UNVERIFIED LAB: UPDATE lab_bookings (expect 0 rows post-000014)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-unverified-staging');
SET LOCAL role authenticated;
UPDATE public.lab_bookings
SET status = 'sample_collected'
WHERE lab_id = 'l_staging_unverified' AND booking_id = 'lb_staging_2';

-- ---------------------------------------------------------------------------
-- VERIFIED PHARMACY: SELECT pharmacy_deliveries for store (baseline policy)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-pharmacy-verified-staging');
SET LOCAL role authenticated;
SELECT 'pharmacy_deliveries_select' AS probe, count(*) AS cnt
FROM public.pharmacy_deliveries WHERE store_id = 'ms_staging_verified';

-- ---------------------------------------------------------------------------
-- AMBULANCE: UPDATE own ambulances row (onboarding — round6 ambulances_update)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-ambulance-staging');
SET LOCAL role authenticated;
SELECT 'ambulance_own_row' AS probe, count(*) AS cnt
FROM public.ambulances WHERE ambulance_id = 'amb_staging_1';

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS: SELECT in_app_notifications for recipient (phase_e2 policy)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-staging');
SET LOCAL role authenticated;
SELECT 'notifications_select' AS probe, count(*) AS cnt
FROM public.in_app_notifications
WHERE recipient_uid = (auth.jwt() ->> 'sub');

ROLLBACK;

-- Pass criteria: document actual counts/errors per probe after 000014 vs baseline.
-- Legitimate flows must still pass: own profile SELECT/UPDATE for unverified providers.
