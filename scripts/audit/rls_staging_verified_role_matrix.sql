-- STAGING ONLY — apply db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql first (manual).
-- Replace fixture IDs/UIDs below, then run: psql "$STAGING_SUPABASE_DB_URL" -f scripts/audit/rls_staging_verified_role_matrix.sql
-- Ends with ROLLBACK so probes are non-destructive unless you change the final line to COMMIT.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.assert_count(
  probe text,
  sql text,
  expected bigint
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v bigint;
BEGIN
  EXECUTE 'SELECT count(*)::bigint FROM (' || sql || ') q' INTO v;
  IF v IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL [%]: expected count %, got %', probe, expected, v;
  END IF;
  RAISE NOTICE 'PASS [%]: count=%', probe, v;
END;
$$;

-- Fixture map (edit):
-- uid-patient-staging -> patient p_staging_patient (owner_uid)
-- uid-patient-owner-staging -> guardian profile; family member fm_staging_1.member_id books as patient
-- uid-doctor-verified / uid-doctor-unverified
-- uid-lab-verified / uid-lab-unverified
-- appointment appt_staging_family on patient_id=fm_staging_1.member_id

-- ---------------------------------------------------------------------------
-- Patient via owner_uid: SELECT child appointment
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'patient_owner_uid_appointments',
  $$SELECT 1 FROM public.appointments a
    JOIN public.patients p ON p.patient_id = a.patient_id
    WHERE p.owner_uid = 'uid-patient-staging'$$,
  1::bigint
);

-- ---------------------------------------------------------------------------
-- Patient via family member: SELECT appointment for member_id
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-patient-guardian-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'patient_family_member_appointments',
  $$SELECT 1 FROM public.appointments WHERE patient_id = 'fm_staging_member_id'$$,
  1::bigint
);

-- ---------------------------------------------------------------------------
-- Unverified doctor: cannot read/update as doctor_id (post-000014 expect 0)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-doctor-unverified-staging');
SET LOCAL role authenticated;
SELECT pg_temp.assert_count(
  'unverified_doctor_appointments_select',
  $$SELECT 1 FROM public.appointments WHERE doctor_id = 'd_staging_unverified'$$,
  0::bigint
);

DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.appointments SET patient_status = patient_status
  WHERE appointment_id = 'appt_staging_doctor_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FAIL [unverified_doctor_appointments_update]: expected ROW_COUNT 0, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_doctor_appointments_update]: ROW_COUNT=0';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified doctor: still read/update OWN doctors row
-- ---------------------------------------------------------------------------
SELECT pg_temp.assert_count(
  'unverified_doctor_own_profile_select',
  $$SELECT 1 FROM public.doctors WHERE doctor_id = 'd_staging_unverified'$$,
  1::bigint
);

DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.doctors SET updated_at = updated_at WHERE doctor_id = 'd_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [unverified_doctor_own_profile_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_doctor_own_profile_update]: ROW_COUNT=1';
END;
$$;

-- ---------------------------------------------------------------------------
-- Verified lab: UPDATE booking (expect 1)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-verified-staging');
SET LOCAL role authenticated;
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.lab_bookings SET status = status
  WHERE booking_id = 'lb_staging_verified' AND lab_id = 'l_staging_verified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [verified_lab_booking_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [verified_lab_booking_update]: ROW_COUNT=1';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified lab: UPDATE booking (expect 0 post-000014)
-- ---------------------------------------------------------------------------
SELECT pg_temp.set_jwt('uid-lab-unverified-staging');
SET LOCAL role authenticated;
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.lab_bookings SET status = status
  WHERE booking_id = 'lb_staging_unverified' AND lab_id = 'l_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FAIL [unverified_lab_booking_update]: expected 0, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_lab_booking_update]: ROW_COUNT=0';
END;
$$;

-- ---------------------------------------------------------------------------
-- Unverified lab: still UPDATE own labs row
-- ---------------------------------------------------------------------------
DO $$
DECLARE v bigint;
BEGIN
  UPDATE public.labs SET updated_at = updated_at WHERE lab_id = 'l_staging_unverified';
  GET DIAGNOSTICS v = ROW_COUNT;
  IF v <> 1 THEN
    RAISE EXCEPTION 'FAIL [unverified_lab_own_profile_update]: expected 1, got %', v;
  END IF;
  RAISE NOTICE 'PASS [unverified_lab_own_profile_update]: ROW_COUNT=1';
END;
$$;

ROLLBACK;
