-- STAGING ONLY — run manually after applying 20261103000014_proposed_role_verified_rls_hardening.sql
-- Proves SELECT/UPDATE expectations per role. Requires Supabase local or staging with auth helpers.
-- Do NOT run against production without change control.

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixture profile IDs (replace with staging seed IDs)
-- ---------------------------------------------------------------------------
\set patient_id '''p_staging_patient'''
\set doctor_verified_id '''d_staging_verified'''
\set doctor_unverified_id '''d_staging_unverified'''
\set lab_verified_id '''l_staging_verified'''
\set lab_unverified_id '''l_staging_unverified'''
\set pharmacy_verified_id '''ms_staging_verified'''
\set ambulance_id '''amb_staging_1'''

-- ---------------------------------------------------------------------------
-- Helper: set JWT claims for authenticated role (Supabase pattern)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', sub,
    'role', role
  )::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Expectation matrix (document results in test run log)
-- Role | appointments SELECT own doctor row | appointments UPDATE accept | prescriptions SELECT | lab_bookings UPDATE status | lab_orders INSERT
-- patient | own patient rows OK | cancel own OK | own Rx OK | own booking OK | N/A
-- verified doctor | linked appts OK | accept OK | own Rx OK | N/A | INSERT OK
-- unverified doctor | DENY doctor branch | DENY accept | DENY doctor branch | N/A | DENY
-- verified lab | N/A | N/A | N/A | UPDATE OK | N/A
-- unverified lab | N/A | N/A | N/A | DENY | N/A
-- verified pharmacy | via delivery join | N/A | via delivery | N/A | N/A
-- ambulance | N/A (no policy change in 000014) | N/A | N/A | N/A | N/A
-- ---------------------------------------------------------------------------

-- Example: unverified doctor must NOT select appointment where doctor_id = self
SELECT pg_temp.set_jwt('uid-unverified-doc');
SET LOCAL role authenticated;
-- Expect 0 rows (policy requires is_verified_doctor())
SELECT count(*) AS unverified_doctor_appointment_select
FROM public.appointments
WHERE doctor_id = :doctor_unverified_id;

-- Example: verified doctor CAN select
SELECT pg_temp.set_jwt('uid-verified-doc');
SET LOCAL role authenticated;
SELECT count(*) AS verified_doctor_appointment_select
FROM public.appointments
WHERE doctor_id = :doctor_verified_id;

-- Example: unverified lab cannot update lab_bookings
SELECT pg_temp.set_jwt('uid-unverified-lab');
SET LOCAL role authenticated;
-- Expect UPDATE 0 rows or permission error depending on RLS
UPDATE public.lab_bookings
SET status = 'sample_collected'
WHERE lab_id = :lab_unverified_id
  AND booking_id = 'lb_test_1';

ROLLBACK;

-- Runbook: replace JWT subs with staging users.owner_uid values tied to profile rows above.
-- For each assertion, record PASS if behavior matches "Expect" column in matrix header.
