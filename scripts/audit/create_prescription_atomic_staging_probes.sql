-- STAGING ONLY — apply 000017 create_prescription_atomic first.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Fixtures (ids must exist on staging): doc_verified, doc_unverified, doc_deactivated, admin uid.

SELECT pg_temp.set_jwt('uid_doc_verified');
SET LOCAL role authenticated;
DO $$
DECLARE v jsonb;
BEGIN
  v := public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_self_verified',
    'doctor_id', 'doc_verified',
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

SELECT pg_temp.set_jwt('uid_doc_unverified');
SET LOCAL role authenticated;
DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_unverified',
    'doctor_id', 'doc_unverified',
    'patient_id', 'pat_staging_1',
    'appointment_id', 'appt_staging_1'
  ));
  RAISE EXCEPTION 'FAIL [unverified_doctor_self]: should be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%not verified%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS [unverified_doctor_self]: %', SQLERRM;
END;
$$;

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

DO $$
BEGIN
  PERFORM public.create_prescription_atomic(jsonb_build_object(
    'prescription_id', 'rx_staging_admin_bad',
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

ROLLBACK;
