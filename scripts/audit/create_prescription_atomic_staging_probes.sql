-- STAGING ONLY — apply db/proposed/20261103000017_proposed_rpc_verified_checks.sql first.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Fixtures (staging): doc_verified, doc_unverified, doc_deactivated, pat_staging_1, appt_staging_*,
-- super-admin uid_admin mapped in private.is_super_admin().

-- 1) Verified doctor self
SELECT pg_temp.set_jwt('uid_doc_verified');
SET LOCAL role authenticated;
DO $$
DECLARE v jsonb;
BEGIN
  v := public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_self_verified',
    'doctor_id', 'doc_other_should_ignore',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  IF COALESCE(v->>'success', 'false') <> 'true' THEN
    RAISE EXCEPTION 'FAIL [verified_doctor_self]: %', v;
  END IF;
  RAISE NOTICE 'PASS [verified_doctor_self]';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL [verified_doctor_self]: %', SQLERRM;
END;
$$;

-- 2) Unverified doctor self
SELECT pg_temp.set_jwt('uid_doc_unverified');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_unverified',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [unverified_doctor_self]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not verified%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS [unverified_doctor_self]: %', SQLERRM;
END;
$$;

-- 3) Deactivated doctor self
SELECT pg_temp.set_jwt('uid_doc_deactivated');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_deactivated',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [deactivated_doctor_self]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not verified%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS [deactivated_doctor_self]: %', SQLERRM;
END;
$$;

-- 4) Admin for verified doctor (payload doctor_id)
SELECT pg_temp.set_jwt('uid_admin');
SET LOCAL role authenticated;
DO $$
DECLARE v jsonb;
BEGIN
  v := public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_admin_verified',
    'doctor_id', 'doc_verified',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  IF COALESCE(v->>'success', 'false') <> 'true' THEN
    RAISE EXCEPTION 'FAIL [admin_for_verified_doctor]: %', v;
  END IF;
  RAISE NOTICE 'PASS [admin_for_verified_doctor]';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL [admin_for_verified_doctor]: %', SQLERRM;
END;
$$;

-- 5) Admin for unverified doctor
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_admin_unverified',
    'doctor_id', 'doc_unverified',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [admin_for_unverified_doctor]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not verified%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS [admin_for_unverified_doctor]: %', SQLERRM;
END;
$$;

-- 6) Admin for deactivated doctor
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_admin_deactivated',
    'doctor_id', 'doc_deactivated',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [admin_for_deactivated_doctor]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not verified%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS [admin_for_deactivated_doctor]: %', SQLERRM;
END;
$$;

-- 7) owner_uid doctor when current_profile_id() IS NULL (JWT sub = owner_uid, no users.id row)
SELECT pg_temp.set_jwt('uid_doc_owner_only');
SET LOCAL role authenticated;
DO $$
DECLARE v jsonb;
BEGIN
  v := public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_owner_uid_only',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  IF COALESCE(v->>'success', 'false') <> 'true' THEN
    RAISE EXCEPTION 'FAIL [owner_uid_without_profile_id]: %', v;
  END IF;
  RAISE NOTICE 'PASS [owner_uid_without_profile_id]';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL [owner_uid_without_profile_id]: %', SQLERRM;
END;
$$;

-- 8) Non-admin cannot impersonate another doctor via payload doctor_id
SELECT pg_temp.set_jwt('uid_doc_verified');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_spoof_doctor',
    'doctor_id', 'doc_other',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [non_admin_spoof_doctor_id]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%does not have an active appointment or link%' THEN
    RAISE;
  END IF;
  RAISE NOTICE 'PASS [non_admin_spoof_doctor_id]: %', SQLERRM;
END;
$$;

ROLLBACK;
